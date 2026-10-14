import http from "k6/http";
import { check } from "k6";
import { Counter } from "k6/metrics";
import { BASE_URL } from "./config.js";

/** 429 fra SokRateLimitFilter (per Nav-ident). */
export const avvistAvApp = new Counter("avvist_rate_limit_app");
/** 503 fra ingress-nginx (limit-rps per klient-IP). */
export const avvistAvIngress = new Counter("avvist_rate_limit_ingress");

const OK = http.expectedStatuses({ min: 200, max: 299 });
const OK_ELLER_429 = http.expectedStatuses({ min: 200, max: 299 }, 429);

function parametere(bruker, navn, type, tillat429) {
  return {
    headers: {
      Authorization: `Bearer ${bruker.token}`,
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    // `name` samler kall med ulike sakId-er til én metrikk.
    tags: { name: navn, type },
    responseCallback: tillat429 ? OK_ELLER_429 : OK,
  };
}

function registrer(res, navn, tillat429 = false) {
  if (res.status === 429) avvistAvApp.add(1, { name: navn });
  if (res.status === 503) avvistAvIngress.add(1, { name: navn });
  check(res, {
    [`${navn} 2xx`]: (r) => (r.status >= 200 && r.status < 300) || (tillat429 && r.status === 429),
  });
  return res;
}

export function les(bruker, sti, navn, { tillat429 = false } = {}) {
  return registrer(http.get(`${BASE_URL}${sti}`, parametere(bruker, navn, "les", tillat429)), navn, tillat429);
}

export function skriv(bruker, metode, sti, navn, body, { tillat429 = false } = {}) {
  const payload = body === undefined ? null : JSON.stringify(body);
  const res = http.request(metode, `${BASE_URL}${sti}`, payload, parametere(bruker, navn, "skriv", tillat429));
  return registrer(res, navn, tillat429);
}

/** Personsøk er POST, men leser data og måles mot terskelen for lesing. 429 er tillatt. */
export function sok(bruker, sti, navn, body) {
  const params = parametere(bruker, navn, "les", true);
  return registrer(http.post(`${BASE_URL}${sti}`, JSON.stringify(body), params), navn, true);
}

/** Parallelle lesekall, slik frontend-loaderen gjør med Promise.all. */
export function lesParallelt(bruker, kall) {
  const svar = http.batch(
    kall.map(([sti, navn]) => ["GET", `${BASE_URL}${sti}`, null, parametere(bruker, navn, "les", false)]),
  );
  return svar.map((res, i) => registrer(res, kall[i][1]));
}

export function json(res) {
  if (res.status < 200 || res.status >= 300 || !res.body) return null;
  try {
    return res.json();
  } catch (_) {
    return null;
  }
}
