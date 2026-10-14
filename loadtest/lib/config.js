import { SharedArray } from "k6/data";

export const BASE_URL = (__ENV.BASE_URL || "https://watson-admin-api.intern.dev.nav.no").replace(/\/$/, "");

// Testen lager saker som blir liggende og sender bearer-tokens. Stopp før første kall hvis
// BASE_URL ikke er HTTPS mot dev, for eksempel etter en gammel miljøvariabel.
// TILLAT_BASE_URL=true åpner for godkjente lokale stubber.
const HOST = (BASE_URL.match(/^https:\/\/([^/:?#]+)/i) || [])[1] || "";
if (!/\.dev\.nav\.no$/i.test(HOST) && __ENV.TILLAT_BASE_URL !== "true") {
  throw new Error(
    `BASE_URL ${BASE_URL} er ikke HTTPS mot dev (https://*.dev.nav.no). Sett TILLAT_BASE_URL=true for en godkjent lokal stub.`,
  );
}
export const ENHET = __ENV.ENHET || "ka864v";
export const MERKING = "LASTTEST";

// Settes absolutt av scripts/lasttest.sh. open() må kalles i init-konteksten.
const TOKEN_FIL = __ENV.TOKEN_FIL;
if (!TOKEN_FIL) {
  throw new Error("TOKEN_FIL mangler. Kjør testen via scripts/lasttest.sh.");
}

/** [{ navIdent, rolle: "saksbehandler" | "leder", token }] */
export const brukere = new SharedArray("brukere", () => {
  const liste = JSON.parse(open(TOKEN_FIL));
  if (!Array.isArray(liste) || liste.length === 0) {
    throw new Error("Tokenfila inneholder ingen brukere. Kjør scripts/lasttest-tokens.sh.");
  }
  return liste;
});

/** Syntetiske testpersoner (Dolly) som testidentene har tilgang til. Brukes ved opprettelse av saker. */
export const testpersoner = (__ENV.TESTPERSONER || "")
  .split(",")
  .map((s) => s.trim())
  .filter((s) => /^[0-9]{11}$/.test(s));

export function harRolle(rolle) {
  for (const b of brukere) {
    if (b.rolle === rolle) return true;
  }
  return false;
}

/**
 * Velger bruker nummer `indeks` blant identene med riktig rolle. Feiler hvis rollen mangler,
 * slik at testen ikke måler med feil tilgangsnivå.
 */
export function brukerMedRolle(rolle, indeks = 0) {
  // SharedArray støtter bare length, indeks og for-of, ikke filter().
  const aktuelle = [];
  for (const b of brukere) {
    if (b.rolle === rolle) aktuelle.push(b);
  }
  if (aktuelle.length === 0) {
    throw new Error(`Tokenfila mangler identer med rollen "${rolle}". Kjør scripts/lasttest-tokens.sh.`);
  }
  return aktuelle[indeks % aktuelle.length];
}

/** Velger bruker for gjeldende VU, fordelt jevnt over identene med riktig rolle. */
export function brukerForVu(rolle) {
  return brukerMedRolle(rolle, __VU - 1);
}

export function tilfeldig(liste) {
  return liste[Math.floor(Math.random() * liste.length)];
}

/** Tenketid mellom sidevisninger. Overstyres med TENKETID_MIN/TENKETID_MAKS (sekunder). */
export function tenketid() {
  const min = Number(__ENV.TENKETID_MIN || 3);
  const maks = Number(__ENV.TENKETID_MAKS || 10);
  return min + Math.random() * (maks - min);
}
