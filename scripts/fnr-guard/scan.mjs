#!/usr/bin/env node
// 🔴 Rød sone: bestemmer hva som blir skannet. Gå gjennom nøye.
//
// Bruk (kjøres fra roten av repoet som skal skannes):
//   node scan.mjs --staged          linjer som legges til i staged diff (pre-commit)
//   node scan.mjs --range A...B     linjer som legges til mellom to commits (CI)
//   node scan.mjs --all             alle sporede filer i arbeidstreet (manuelt)
//   node scan.mjs --history         hele git-historikken, alle brancher (manuelt)
//
// Exit-kode: 0 = ingen funn, 1 = funn, 2 = feil. Alt annet enn 0 stopper commit.
// Utskriften inneholder aldri nummeret, bare fil, linje og type.

import { execFileSync } from "node:child_process";
import { readFileSync, existsSync } from "node:fs";
import { finnIRad, skannTekst, lesUnntak, masker } from "./fnr-guard.mjs";

const UNNTAKSFIL = ".fnr-allowlist";
const MAKS_BUFFER = 1024 * 1024 * 1024;

function git(args, opts = {}) {
  return execFileSync("git", ["-c", "core.quotePath=false", ...args], {
    maxBuffer: MAKS_BUFFER,
    stdio: ["ignore", "pipe", "pipe"],
    ...opts,
  });
}

function gitTekst(args) {
  return git(args).toString("utf8");
}

function fjernAnforsel(sti) {
  return sti.startsWith('"') && sti.endsWith('"') ? sti.slice(1, -1) : sti;
}

let pdfAdvart = false;
function pdfTilTekst(buffer) {
  try {
    return execFileSync("pdftotext", ["-q", "-", "-"], {
      input: buffer,
      maxBuffer: MAKS_BUFFER,
      stdio: ["pipe", "pipe", "ignore"],
    }).toString("utf8");
  } catch (e) {
    if (e.code === "ENOENT") {
      if (!pdfAdvart) {
        console.error("⚠️  pdftotext mangler, PDF-er skannes ikke (brew install poppler)");
        pdfAdvart = true;
      }
      return null;
    }
    throw e;
  }
}

/**
 * Leser unified diff med -U0 og returnerer funn i linjer som legges til.
 * Linjer som starter med `@@COMMIT ` (fra --history) setter gjeldende commit.
 */
function skannDiff(diff, unntak) {
  const funn = [];
  let commit = null;
  let fil = null;
  let linjenr = 0;
  for (const rad of diff.split("\n")) {
    if (rad.startsWith("@@COMMIT ")) {
      commit = rad.slice(9).trim();
      fil = null;
    } else if (rad.startsWith("+++ ")) {
      const sti = fjernAnforsel(rad.slice(4));
      fil = sti === "/dev/null" ? null : sti.replace(/^b\//, "");
    } else if (rad.startsWith("@@ ")) {
      const m = /\+(\d+)/.exec(rad);
      linjenr = m ? Number(m[1]) : 0;
    } else if (rad.startsWith("+") && fil) {
      for (const { type } of finnIRad(rad.slice(1), unntak)) {
        funn.push({ commit, fil, linje: linjenr, type });
      }
      linjenr++;
    }
  }
  return funn;
}

/** Skanner filnavn, og PDF-er via pdftotext. `lesBlob(sti)` gir innholdet. */
function skannFilnavnOgPdf(stier, lesBlob, unntak) {
  const funn = [];
  for (const sti of stier) {
    for (const { type } of finnIRad(sti, unntak)) {
      funn.push({ fil: sti, linje: 0, type, filnavn: true });
    }
    if (sti.toLowerCase().endsWith(".pdf")) {
      const tekst = pdfTilTekst(lesBlob(sti));
      if (tekst) {
        for (const f of skannTekst(tekst, unntak)) funn.push({ fil: sti, ...f, pdf: true });
      }
    }
  }
  return funn;
}

function unntakFraGit(ref) {
  try {
    git(["cat-file", "-e", `${ref}:${UNNTAKSFIL}`]);
  } catch {
    return new Set(); // filen finnes ikke i index/commit
  }
  return lesUnntak(gitTekst(["show", `${ref}:${UNNTAKSFIL}`]));
}

function navnListe(args) {
  return gitTekst([...args, "-z"]).split("\0").filter(Boolean);
}

function skannStaged() {
  const unntak = unntakFraGit("");
  const diff = gitTekst(["diff", "--cached", "--no-color", "--no-ext-diff", "-U0", "--diff-filter=d"]);
  const stier = navnListe(["diff", "--cached", "--name-only", "--diff-filter=d"]);
  return {
    unntak,
    funn: [
      ...skannDiff(diff, unntak),
      ...skannFilnavnOgPdf(stier, (s) => git(["show", `:${s}`]), unntak),
    ],
  };
}

function skannRange(range) {
  const head = range.split(/\.\.\.?/).pop() || "HEAD";
  const unntak = unntakFraGit(head);
  const diff = gitTekst(["diff", "--no-color", "--no-ext-diff", "-U0", "--diff-filter=d", range]);
  const stier = navnListe(["diff", "--name-only", "--diff-filter=d", range]);
  return {
    unntak,
    funn: [
      ...skannDiff(diff, unntak),
      ...skannFilnavnOgPdf(stier, (s) => git(["show", `${head}:${s}`]), unntak),
    ],
  };
}

function lesUnntakFraDisk() {
  return existsSync(UNNTAKSFIL) ? lesUnntak(readFileSync(UNNTAKSFIL, "utf8")) : new Set();
}

function skannAlt() {
  const unntak = lesUnntakFraDisk();
  const funn = [];
  const stier = navnListe(["ls-files"]);
  for (const sti of stier) {
    if (!existsSync(sti)) continue;
    const buffer = readFileSync(sti);
    if (sti.toLowerCase().endsWith(".pdf") || buffer.includes(0)) continue; // PDF tas under
    for (const f of skannTekst(buffer.toString("utf8"), unntak)) funn.push({ fil: sti, ...f });
  }
  funn.push(...skannFilnavnOgPdf(stier, (s) => readFileSync(s), unntak));
  return { unntak, funn };
}

function skannHistorikk() {
  const unntak = lesUnntakFraDisk();
  const diff = gitTekst([
    "log", "--all", "-p", "-U0", "--no-color", "--no-ext-diff", "--diff-filter=d",
    "--format=@@COMMIT %h",
  ]);
  // Filnavn i historikken
  const navnLogg = gitTekst(["log", "--all", "--name-only", "--diff-filter=d", "--format=@@COMMIT %h"]);
  const funn = skannDiff(diff, unntak);
  let commit = null;
  for (const rad of navnLogg.split("\n")) {
    if (rad.startsWith("@@COMMIT ")) commit = rad.slice(9).trim();
    else if (rad) {
      for (const { type } of finnIRad(rad, unntak)) {
        funn.push({ commit, fil: rad, linje: 0, type, filnavn: true });
      }
    }
  }
  return { unntak, funn };
}

function skrivFunn(funn, unntak) {
  for (const f of funn) {
    const sted = f.filnavn ? `${masker(f.fil, unntak)} (filnavn)` : `${masker(f.fil, unntak)}:${f.linje}`;
    const prefiks = f.commit ? `${f.commit} ` : "";
    console.error(`  ${prefiks}${sted}  type=${f.type}${f.pdf ? " (pdf)" : ""}`);
    if (process.env.GITHUB_ACTIONS === "true" && !f.commit) {
      const linje = f.linje > 0 ? `,line=${f.linje}` : "";
      console.log(`::error file=${masker(f.fil, unntak)}${linje}::Gyldig ${f.type} funnet`);
    }
  }
}

function main(argv) {
  const [modus, verdi] = argv;
  let resultat;
  if (modus === "--staged") resultat = skannStaged();
  else if (modus === "--range" && verdi) resultat = skannRange(verdi);
  else if (modus === "--all") resultat = skannAlt();
  else if (modus === "--history") resultat = skannHistorikk();
  else {
    console.error("Bruk: scan.mjs --staged | --range A...B | --all | --history");
    return 2;
  }

  const { funn, unntak } = resultat;
  if (funn.length === 0) return 0;

  console.error(`\n🛑 fnr-guard: fant ${funn.length} gyldig(e) fødselsnummer/D-nummer:\n`);
  skrivFunn(funn, unntak);
  console.error(`
Fjern nummeret, eller bytt det med et syntetisk nummer (Dolly/Tenor).
Er nummeret bekreftet syntetisk, kan det legges i ${UNNTAKSFIL} med en kommentar om kilden.
`);
  return 1;
}

try {
  process.exitCode = main(process.argv.slice(2));
} catch (e) {
  console.error(`🛑 fnr-guard: feil under skanning: ${e.message}`);
  process.exitCode = 2;
}
