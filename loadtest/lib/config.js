import { SharedArray } from "k6/data";

export const BASE_URL = (__ENV.BASE_URL || "https://watson-admin-api.intern.dev.nav.no").replace(/\/$/, "");
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

/** Velger bruker for gjeldende VU, fordelt jevnt over identene med riktig rolle. */
export function brukerForVu(rolle) {
  // SharedArray støtter bare length, indeks og for-of, ikke filter().
  const aktuelle = [];
  for (const b of brukere) {
    if (b.rolle === rolle) aktuelle.push(b);
  }
  if (aktuelle.length > 0) return aktuelle[(__VU - 1) % aktuelle.length];
  return brukere[(__VU - 1) % brukere.length];
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
