import http from "k6/http";
import { check } from "k6";
import { Counter } from "k6/metrics";
import { BASE_URL } from "./config.js";

/**
 * Alle kallnavn. k6 lager bare tidsserier per kall for navn med en terskel, så rapporten
 * (lib/rapport.js) trenger lista. Nye kall må legges inn her, ellers advarer testen.
 */
export const KALLNAVN = [
  "setup sakliste",
  "innlogget-bruker",
  "mine oppsummering",
  "varsler uleste",
  "sakliste mine",
  "sakliste tilknyttet",
  "sakliste alle",
  "sakliste filtrert",
  "kodeverk",
  "merker",
  "sak",
  "sak hendelser",
  "sak journalposter",
  "sak filer",
  "sak tillatte-handlinger",
  "sak mapper",
  "saksbehandlere",
  "sok person",
  "dokument",
  "dokument kommentarer",
  "dokument historikk",
  "opprett sak",
  "tildel sak",
  "opprett dokument",
  "dokument laas",
  "lagre dokument",
  "dokument frigjor laas",
  "opprett mappe",
  "opprett hendelse",
  "rediger hendelse",
  "slett hendelse",
  "rediger sak",
  "leder statistikk",
  "statistikk nav-kontroll",
  "statistikk hovedavdeling",
  "sakliste fordeling",
];
const kjenteNavn = new Set(KALLNAVN);
const ukjenteNavn = new Set();

/** 429 fra SokRateLimitFilter (per Nav-ident). */
export const avvistAvApp = new Counter("avvist_rate_limit_app");
/** 503 fra ingress-nginx (limit-rps per klient-IP). */
export const avvistAvIngress = new Counter("avvist_rate_limit_ingress");

// Én responseCallback per kombinasjon av tillatte statuskoder utenom 2xx.
const callbacks = {};
function forventet(tillatt) {
  const nokkel = tillatt.join(",");
  if (!callbacks[nokkel]) callbacks[nokkel] = http.expectedStatuses({ min: 200, max: 299 }, ...tillatt);
  return callbacks[nokkel];
}

// Logger hver kombinasjon av kall og statuskode én gang per VU, så feil i podene kan kobles til kallet.
const loggetFeil = new Set();
function loggFeil(res, navn) {
  const nokkel = `${navn}:${res.status}`;
  if (loggetFeil.has(nokkel)) return;
  loggetFeil.add(nokkel);
  let detalj = res.error || "";
  try {
    const body = res.json();
    detalj = body.detail || body.title || body.message || detalj;
  } catch (_) {
    // Ikke JSON.
  }
  // Maskerer fødselsnumre i tilfelle backend tar dem med i feilmeldingen.
  detalj = String(detalj).replace(/\d{11}/g, "***********").slice(0, 200);
  console.warn(`${navn}: HTTP ${res.status} ${res.request.method} ${res.url}${detalj ? ` (${detalj})` : ""}`);
}

function parametere(bruker, navn, type, tillatt) {
  return {
    headers: {
      Authorization: `Bearer ${bruker.token}`,
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    // `name` samler kall med ulike sakId-er til én metrikk.
    tags: { name: navn, type },
    responseCallback: forventet(tillatt),
  };
}

/**
 * `tillatt` er statuskoder utenom 2xx som frontend håndterer som gyldige svar,
 * for eksempel 403 når saksbehandleren ikke er knyttet til saken.
 */
function registrer(res, navn, tillatt = []) {
  if (!kjenteNavn.has(navn) && !ukjenteNavn.has(navn)) {
    ukjenteNavn.add(navn);
    console.warn(`Kallet "${navn}" mangler i KALLNAVN i lib/klient.js og kommer ikke med i rapporten.`);
  }
  if (res.status === 429) avvistAvApp.add(1, { name: navn });
  if (res.status === 503) avvistAvIngress.add(1, { name: navn });
  const ok = (res.status >= 200 && res.status < 300) || tillatt.includes(res.status);
  if (!ok) loggFeil(res, navn);
  check(res, { [`${navn} ok`]: () => ok });
  return res;
}

export function les(bruker, sti, navn, { tillatt = [] } = {}) {
  return registrer(http.get(`${BASE_URL}${sti}`, parametere(bruker, navn, "les", tillatt)), navn, tillatt);
}

export function skriv(bruker, metode, sti, navn, body, { tillatt = [] } = {}) {
  const payload = body === undefined ? null : JSON.stringify(body);
  const res = http.request(metode, `${BASE_URL}${sti}`, payload, parametere(bruker, navn, "skriv", tillatt));
  return registrer(res, navn, tillatt);
}

/** Personsøk er POST, men leser data og måles mot terskelen for lesing. 429 er alltid tillatt. */
export function sok(bruker, sti, navn, body, { tillatt = [] } = {}) {
  const koder = [429, ...tillatt];
  const params = parametere(bruker, navn, "les", koder);
  return registrer(http.post(`${BASE_URL}${sti}`, JSON.stringify(body), params), navn, koder);
}

/** Parallelle lesekall, slik frontend-loaderen gjør med Promise.all. Hvert kall: [sti, navn, tillatt?]. */
export function lesParallelt(bruker, kall) {
  const svar = http.batch(
    kall.map(([sti, navn, tillatt = []]) => ["GET", `${BASE_URL}${sti}`, null, parametere(bruker, navn, "les", tillatt)]),
  );
  return svar.map((res, i) => registrer(res, kall[i][1], kall[i][2] || []));
}

export function json(res) {
  if (res.status < 200 || res.status >= 300 || !res.body) return null;
  try {
    return res.json();
  } catch (_) {
    return null;
  }
}
