import { group, sleep } from "k6";
import { ENHET, MERKING, testpersoner, tenketid, tilfeldig } from "./config.js";
import { json, les, lesParallelt, skriv, sok } from "./klient.js";

const SAK = "/api/v1/kontrollsaker";

/**
 * Henter sak-ID-er brukeren ser i saklista. Kalles fra setup() slik at lesetesten
 * har eksisterende saker å åpne.
 */
export function hentSakIder(bruker, antallSider = 5) {
  const ider = [];
  for (let side = 1; side <= antallSider; side++) {
    const data = json(les(bruker, `${SAK}?page=${side}&size=100`, "setup sakliste"));
    if (!data || data.items.length === 0) break;
    data.items.forEach((sak) => ider.push(sak.id));
    if (side >= data.totalPages) break;
  }
  return ider;
}

export function forside(bruker) {
  group("forside", () => {
    lesParallelt(bruker, [
      ["/api/innlogget-bruker", "innlogget-bruker"],
      [`${SAK}/mine/oppsummering`, "mine oppsummering"],
      ["/api/v1/varsler?kunUleste=true&page=1&size=20", "varsler uleste"],
    ]);
  });
  sleep(tenketid());
}

export function mineSaker(bruker) {
  group("mine saker", () => {
    les(bruker, `${SAK}?ansvarlig=MEG&page=1&size=20`, "sakliste mine");
    les(bruker, `${SAK}?tilknyttet=MEG&page=1&size=20`, "sakliste tilknyttet");
  });
  sleep(tenketid());
}

export function alleSaker(bruker) {
  group("alle saker", () => {
    lesParallelt(bruker, [
      [`${SAK}?page=1&size=20`, "sakliste alle"],
      ["/api/v1/kodeverk", "kodeverk"],
      [`${SAK}/merker`, "merker"],
    ]);
    les(bruker, `${SAK}?page=2&size=20&enhet=${ENHET}&sortering=oppdatert,DESC`, "sakliste filtrert");
  });
  sleep(tenketid());
}

/**
 * Speiler SakDetaljSide.loader.server.ts i watson-sak-frontend: én sak, så sju parallelle kall,
 * så personsøk etter andre saker. Frontend godtar 403 på kallene som krever at saksbehandleren
 * er knyttet til saken, så det gjør vi også. Personsøket teller mot søkegrensen per ident,
 * så 429 er tillatt der.
 */
export function sakDetalj(bruker, sakId) {
  let sak = null;
  group("sakdetalj", () => {
    sak = json(les(bruker, `${SAK}/${sakId}`, "sak"));
    lesParallelt(bruker, [
      [`${SAK}/${sakId}/hendelser`, "sak hendelser", [403]],
      [`${SAK}/${sakId}/journalposter`, "sak journalposter", [403]],
      ["/api/v1/saksbehandlere", "saksbehandlere"],
      [`${SAK}/${sakId}/filer`, "sak filer", [403]],
      [`${SAK}/${sakId}/tillatte-handlinger`, "sak tillatte-handlinger", [403]],
      ["/api/innlogget-bruker", "innlogget-bruker"],
      [`${SAK}/${sakId}/mapper`, "sak mapper", [403]],
    ]);
    if (sak && sak.tilgang && sak.tilgang.kanSeRelaterteSaker) {
      sok(bruker, `${SAK}/sok?page=1&size=100`, "sok person", {
        personIdent: sak.kontrollobjekt.personIdent,
      }, { tillatt: [403] });
    }
  });
  sleep(tenketid());
  return sak;
}

export function dokumentVisning(bruker, sak) {
  if (!sak || !sak.dokumenter || sak.dokumenter.length === 0) return;
  const dokId = tilfeldig(sak.dokumenter).id;
  group("dokument", () => {
    lesParallelt(bruker, [
      [`${SAK}/${sak.id}/dokumenter/${dokId}`, "dokument"],
      [`${SAK}/${sak.id}/dokumenter/${dokId}/kommentartraader`, "dokument kommentarer"],
      [`${SAK}/${sak.id}/dokumenter/${dokId}/historikk`, "dokument historikk"],
    ]);
  });
  sleep(tenketid());
}

function dokumentInnhold(avsnitt) {
  const innhold = [];
  for (let i = 0; i < avsnitt; i++) {
    innhold.push({ type: "p", children: [{ text: `Lasttest avsnitt ${i}. ${"Lorem ipsum ".repeat(20)}` }] });
  }
  return innhold;
}

/**
 * Skriveflyt mot egen database og GCS. Utelater journalføring (dokarkiv),
 * oppgaveopprettelse (Oppgave) og filopplasting (ClamAV).
 * Krever minst én testperson i TESTPERSONER. Utvidet tilgang trengs bare hvis testpersonen er skjermet.
 */
export function registrerOgBehandleSak(bruker) {
  if (testpersoner.length === 0) return;
  group("registrer og behandle sak", () => {
    const sak = json(
      skriv(bruker, "POST", SAK, "opprett sak", {
        personIdent: tilfeldig(testpersoner),
        kategori: "ARBEID",
        kilde: "NAV_KONTROLL",
        enhet: ENHET,
        merking: [MERKING],
      }),
    );
    if (!sak) return;
    sleep(tenketid());

    // Dokumenter og mapper krever at saksbehandleren er ansvarlig, så hun tar saken først.
    skriv(bruker, "POST", `${SAK}/${sak.id}/saksbehandler`, "tildel sak", {
      navIdent: bruker.navIdent,
      aksjon: "TILDEL",
    });

    const dok = json(skriv(bruker, "POST", `${SAK}/${sak.id}/dokumenter`, "opprett dokument"));
    if (dok) {
      const dokSti = `${SAK}/${sak.id}/dokumenter/${dok.id}`;
      skriv(bruker, "POST", `${dokSti}/laas`, "dokument laas");
      // Autolagring fra editoren: dokumentet vokser for hver lagring.
      for (let i = 1; i <= 3; i++) {
        skriv(bruker, "PUT", dokSti, "lagre dokument", {
          tittel: "Lasttest notat",
          innhold: dokumentInnhold(i * 10),
          opprettHistorikk: i === 3,
        });
        sleep(2);
      }
      skriv(bruker, "DELETE", `${dokSti}/laas`, "dokument frigjor laas");
    }

    skriv(bruker, "POST", `${SAK}/${sak.id}/mapper`, "opprett mappe", { sti: `lasttest-${__VU}-${__ITER}` });

    const hendelse = json(
      skriv(bruker, "POST", `${SAK}/${sak.id}/hendelser`, "opprett hendelse", {
        tittel: "Lasttest",
        beskrivelse: "Manuell hendelse fra lasttest",
      }),
    );
    if (hendelse) {
      const hendelseSti = `${SAK}/${sak.id}/hendelser/${hendelse.hendelseId}`;
      skriv(bruker, "PUT", hendelseSti, "rediger hendelse", {
        tittel: "Lasttest redigert",
        beskrivelse: null,
      });
      skriv(bruker, "DELETE", hendelseSti, "slett hendelse");
    }

    skriv(bruker, "PATCH", `${SAK}/${sak.id}`, "rediger sak", { merking: [MERKING] });
  });
  sleep(tenketid());
}

export function lederVisning(bruker) {
  const iDag = new Date();
  const fra = new Date(iDag.getFullYear(), 0, 1).toISOString().slice(0, 10);
  group("leder", () => {
    les(bruker, "/api/v1/leder/statistikk", "leder statistikk");
    sleep(tenketid());
    lesParallelt(bruker, [
      [`/api/v1/statistikk?nivaa=NAV_KONTROLL&fra=${fra}`, "statistikk nav-kontroll"],
      [`/api/v1/statistikk?nivaa=HOVEDAVDELING&fra=${fra}`, "statistikk hovedavdeling"],
      ["/api/v1/saksbehandlere", "saksbehandlere"],
    ]);
    sleep(tenketid());
    les(bruker, `${SAK}?utenAnsvarlig=true&page=1&size=50`, "sakliste fordeling");
  });
  sleep(tenketid());
}
