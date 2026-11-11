#!/usr/bin/env node
// 🔴 Rød sone: bestemmer hva som blir skannet og hva som skrives ut. Gå gjennom nøye.
//
// Bruk (kjøres fra roten av repoet som skal skannes):
//   node scan.mjs --staged          linjer som legges til i staged diff (pre-commit)
//   node scan.mjs --range A..B      hvert commit i B som ikke er i A (CI)
//   node scan.mjs --all             alle sporede filer i arbeidstreet (manuelt)
//   node scan.mjs --history         hvert commit i hele historikken, alle brancher (manuelt)
//
// Exit-kode: 0 = ingen funn, 1 = funn, 2 = feil. Alt annet enn 0 stopper commit.
// Utskriften inneholder aldri et gyldig nummer, heller ikke i feilmeldinger.

import { readFileSync, existsSync } from "node:fs";
import { finnIRad, skannTekst, lesUnntak, masker } from "./fnr-guard.mjs";
import { lagGit, tillagteLinjer, endredeFiler, arbeidstre, pdfTilTekst, erPdf } from "./git-kilder.mjs";

const UNNTAKSFIL = ".fnr-allowlist";
const git = lagGit();

function unntakFraGit(ref) {
  try {
    git(["cat-file", "-e", `${ref}:${UNNTAKSFIL}`]);
  } catch {
    return new Set(); // filen finnes ikke i index/commit
  }
  return lesUnntak(git.tekst(["show", `${ref}:${UNNTAKSFIL}`]));
}

function unntakFraDisk() {
  return existsSync(UNNTAKSFIL) ? lesUnntak(readFileSync(UNNTAKSFIL, "utf8")) : new Set();
}

/** Filnavn og PDF-innhold. `filer` gir { commit?, sti, les }. */
function skannFiler(filer, unntak) {
  const funn = [];
  for (const { commit, sti, les } of filer) {
    for (const { type } of finnIRad(sti, unntak)) {
      funn.push({ commit, fil: sti, linje: 0, type, filnavn: true });
    }
    if (erPdf(sti)) {
      const buffer = les();
      const tekst = buffer && pdfTilTekst(buffer);
      if (tekst) {
        for (const f of skannTekst(tekst, unntak)) funn.push({ commit, fil: sti, ...f, pdf: true });
      }
    }
  }
  return funn;
}

function skannLinjer(linjer, unntak) {
  const funn = [];
  for (const { commit, fil, linje, tekst } of linjer) {
    for (const { type } of finnIRad(tekst, unntak)) funn.push({ commit, fil, linje, type });
  }
  return funn;
}

function skannKilde(kilde, unntak) {
  return [
    ...skannLinjer(tillagteLinjer(kilde, git), unntak),
    ...skannFiler(endredeFiler(kilde, git), unntak),
  ];
}

function skannAlt() {
  const unntak = unntakFraDisk();
  const funn = [];
  const filer = [...arbeidstre(git)];
  for (const { sti, les } of filer) {
    if (erPdf(sti)) continue; // tas i skannFiler
    const buffer = les();
    if (!buffer || buffer.includes(0)) continue;
    for (const f of skannTekst(buffer.toString("utf8"), unntak)) funn.push({ fil: sti, ...f });
  }
  funn.push(...skannFiler(filer, unntak));
  return funn;
}

function skrivFunn(funn) {
  for (const f of funn) {
    const fil = masker(f.fil);
    const sted = f.filnavn ? `${fil} (filnavn)` : `${fil}:${f.linje}`;
    const prefiks = f.commit ? `${f.commit.slice(0, 10)} ` : "";
    console.error(`  ${prefiks}${sted}  type=${f.type}${f.pdf ? " (pdf)" : ""}`);
    if (process.env.GITHUB_ACTIONS === "true") {
      const linje = f.linje > 0 ? `,line=${f.linje}` : "";
      const commit = f.commit ? ` i commit ${f.commit.slice(0, 10)}` : "";
      console.log(`::error file=${fil}${linje}::Gyldig ${f.type} funnet${commit}`);
    }
  }
}

function main(argv) {
  const [modus, verdi] = argv;
  let funn;
  if (modus === "--staged") {
    funn = skannKilde({ type: "staged" }, unntakFraGit(""));
  } else if (modus === "--range" && verdi) {
    // A...B betyr symmetrisk differanse i git log. Vi vil bare ha commits i B.
    const range = verdi.replace("...", "..");
    const head = range.split("..").pop() || "HEAD";
    funn = skannKilde({ type: "range", range }, unntakFraGit(head));
  } else if (modus === "--all") {
    funn = skannAlt();
  } else if (modus === "--history") {
    funn = skannKilde({ type: "historikk" }, unntakFraDisk());
  } else {
    console.error("Bruk: scan.mjs --staged | --range A..B | --all | --history");
    return 2;
  }

  // Samme nummer kan dukke opp flere ganger (f.eks. i en merge mot første forelder)
  const unike = [...new Map(funn.map((f) => [JSON.stringify(f), f])).values()];
  if (unike.length === 0) return 0;

  console.error(`\n🛑 fnr-guard: fant ${unike.length} gyldig(e) fødselsnummer/D-nummer:\n`);
  skrivFunn(unike);
  console.error(`
Fjern nummeret, eller bytt det med et syntetisk nummer (Dolly/Tenor).
Er nummeret bekreftet syntetisk, kan det legges i ${UNNTAKSFIL} med en kommentar om kilden.
`);
  return 1;
}

try {
  process.exitCode = main(process.argv.slice(2));
} catch (e) {
  // Feilmeldinger fra git og fs kan inneholde filstier med fnr
  console.error(`🛑 fnr-guard: feil under skanning: ${masker(e.message)}`);
  process.exitCode = 2;
}
