// 🔴 Rød sone: avgjør hvilke tall som stopper en commit. Gå gjennom nøye.
//
// Kjernen i fnr-guard. Finner kandidater på 11 siffer i tekst og avgjør om de
// er gyldige fødselsnumre eller D-numre. H-nummer (Dolly, +40 på måned) og
// T-nummer (Tenor, +80 på måned) er syntetiske og slippes gjennom.
//
// Funnene inneholder aldri selve nummeret, bare linje og type, slik at ingen
// logg (lokal eller CI) gjengir persondata.

// idnr() godtar alle typer (også hnr/tnr). Vi filtrerer på type selv.
import { idnr } from "./fnrvalidator.mjs";

const BLOKKERTE_TYPER = new Set(["fnr", "dnr"]);

// 6 siffer, valgfritt ett skilletegn (mellomrom, bindestrek, punktum), 5 siffer.
// Ingen siffer rett før eller etter, så lengre tall (12+ siffer) ikke gir treff.
const KANDIDAT = /(?<![0-9])([0-9]{6})[ .-]?([0-9]{5})(?![0-9])/g;

/** Returnerer "fnr" eller "dnr" hvis nummeret skal blokkeres, ellers null. */
export function blokkertType(elleveSiffer) {
  const resultat = idnr(elleveSiffer);
  if (resultat.status !== "valid") return null;
  return BLOKKERTE_TYPER.has(resultat.type) ? resultat.type : null;
}

/** Alle blokkerte numre i én linje som { type, nummer }. */
export function finnIRad(rad, unntak = new Set()) {
  const funn = [];
  for (const treff of rad.matchAll(KANDIDAT)) {
    const nummer = treff[1] + treff[2];
    if (unntak.has(nummer)) continue;
    const type = blokkertType(nummer);
    if (type) funn.push({ type, nummer });
  }
  return funn;
}

/** Skanner en tekst linje for linje. Returnerer [{ linje, type }] uten nummer. */
export function skannTekst(tekst, unntak = new Set(), forsteLinje = 1) {
  const funn = [];
  tekst.split(/\r?\n/).forEach((rad, i) => {
    for (const { type } of finnIRad(rad, unntak)) {
      funn.push({ linje: forsteLinje + i, type });
    }
  });
  return funn;
}

/**
 * Erstatter alle gyldige fnr/D-numre i en tekst (filnavn, feilmeldinger) med
 * stjerner før utskrift. Unntakslisten gjelder bare blokkering, ikke maskering.
 */
export function masker(tekst) {
  return String(tekst).replace(KANDIDAT, (hele, a, b) =>
    blokkertType(a + b) ? "*".repeat(hele.length) : hele,
  );
}

/**
 * Leser innholdet i .fnr-allowlist. Ett nummer per linje, `#` starter en
 * kommentar. Linjer som ikke er nøyaktig 11 siffer etter at kommentaren er
 * fjernet, gir feil: en skrivefeil i unntakslisten skal ikke passere stille.
 */
export function lesUnntak(innhold) {
  const unntak = new Set();
  if (!innhold) return unntak;
  innhold.split(/\r?\n/).forEach((rad, i) => {
    const verdi = rad.replace(/#.*$/, "").trim();
    if (verdi === "") return;
    if (!/^[0-9]{11}$/.test(verdi)) {
      throw new Error(`.fnr-allowlist linje ${i + 1}: forventet 11 siffer`);
    }
    unntak.add(verdi);
  });
  return unntak;
}
