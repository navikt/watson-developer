#!/usr/bin/env node
// Skriver alle gyldige fnr/dnr i Watson-repoene til en fil, slik at et menneske
// kan sjekke om de tilhører ekte personer. Numrene skrives ALDRI til terminalen,
// bare antall.
//
// Bruk:
//   node scripts/fnr-guard/eksporter-funn.mjs <utfil> [--history] [repo-sti ...]
//
// Uten repo-stier skannes alle git-repoer i watson-developer/repos/.
// --history skanner hvert commit i hele historikken (alle brancher, også
// merge-commits), ellers sporede filer nå. PDF-er skannes når pdftotext finnes.
//
// Utfilen inneholder persondata hvis numrene er ekte:
// - den opprettes atomisk med rettigheter 600, aldri over en eksisterende sti,
//   og kan ikke ligge inne i et git-repo
// - slett den når du er ferdig

import { execFileSync } from "node:child_process";
import { openSync, writeSync, closeSync, existsSync, readdirSync } from "node:fs";
import { resolve, dirname, join, basename } from "node:path";
import { fileURLToPath } from "node:url";
import { finnIRad, masker } from "./fnr-guard.mjs";
import { lagGit, tillagteLinjer, endredeFiler, arbeidstre, pdfTilTekst, erPdf } from "./git-kilder.mjs";

const HER = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const historikk = args.includes("--history");
const [utfil, ...repoArgs] = args.filter((a) => a !== "--history");

if (!utfil) {
  console.error("Bruk: eksporter-funn.mjs <utfil> [--history] [repo-sti ...]");
  process.exit(2);
}
const utsti = resolve(utfil);
try {
  execFileSync("git", ["-C", dirname(utsti), "rev-parse", "--is-inside-work-tree"], { stdio: "ignore" });
  console.error("Utfilen kan ikke ligge inne i et git-repo. Bruk for eksempel ~/fnr-funn.txt.");
  process.exit(2);
} catch {
  // ikke i et repo: ok
}

// Opprett utfilen før skanningen, atomisk: `wx` feiler hvis stien finnes
// (også som symlink), og rettighetene settes ved opprettelse.
let fd;
try {
  fd = openSync(utsti, "wx", 0o600);
} catch (e) {
  console.error(
    e.code === "EEXIST"
      ? "Utfilen finnes allerede. Velg et annet navn eller slett den først."
      : `Kunne ikke opprette utfilen: ${e.code}`,
  );
  process.exit(2);
}

const reposDir = resolve(HER, "../../repos");
const repoer = (repoArgs.length ? repoArgs.map((r) => resolve(r)) : readdirSync(reposDir).map((d) => join(reposDir, d)))
  .filter((r) => existsSync(join(r, ".git")));

function skannRepo(cwd) {
  const git = lagGit(cwd);
  const rader = [];
  const legg = (commit, fil, linje, tekst) => {
    for (const { type, nummer } of finnIRad(tekst)) rader.push({ commit: commit ?? "", fil, linje, type, nummer });
  };
  const leggPdf = (commit, sti, buffer) => {
    const tekst = buffer && pdfTilTekst(buffer);
    if (tekst) tekst.split(/\r?\n/).forEach((t, i) => legg(commit, `${sti} (pdf)`, i + 1, t));
  };

  if (historikk) {
    const kilde = { type: "historikk" };
    for (const l of tillagteLinjer(kilde, git)) legg(l.commit, l.fil, l.linje, l.tekst);
    for (const f of endredeFiler(kilde, git)) {
      legg(f.commit, f.sti, 0, f.sti);
      if (erPdf(f.sti)) leggPdf(f.commit, f.sti, f.les());
    }
  } else {
    for (const { sti, les } of arbeidstre(git, cwd)) {
      legg("", sti, 0, sti);
      const b = les();
      if (!b) continue;
      if (erPdf(sti)) leggPdf("", sti, b);
      else if (!b.includes(0)) b.toString("utf8").split(/\r?\n/).forEach((t, i) => legg("", sti, i + 1, t));
    }
  }
  return rader;
}

const funn = [];
const oppsummering = [];
for (const repo of repoer) {
  const navn = basename(repo);
  try {
    const rader = skannRepo(repo);
    const unike = [...new Map(rader.map((r) => [[r.commit, r.fil, r.linje, r.nummer].join("\t"), r])).values()];
    for (const r of unike) funn.push({ repo: navn, ...r });
    oppsummering.push({
      navn,
      funn: unike.length,
      numre: new Set(unike.map((r) => r.nummer)).size,
      filer: new Set(unike.map((r) => r.fil)).size,
    });
  } catch (e) {
    // Feilmeldinger kan inneholde filstier med fnr
    oppsummering.push({ navn, feil: masker(e.message.split("\n")[0]) });
  }
}

// Per nummer på tvers av repoer
const perNummer = new Map();
for (const f of funn) {
  const p = perNummer.get(f.nummer) ?? { type: f.type, repoer: new Set(), funn: 0 };
  p.repoer.add(f.repo);
  p.funn++;
  perNummer.set(f.nummer, p);
}

const tsv = (rader) => rader.map((r) => r.join("\t")).join("\n");
const innhold = [
  `# fnr-guard eksport (${historikk ? "historikk" : "nåværende filer"}), ${new Date().toISOString()}`,
  "# INNEHOLDER PERSONDATA HVIS NUMRENE ER EKTE. Slett filen når du er ferdig.",
  "",
  "## Per nummer på tvers av repoer",
  tsv([
    ["nummer", "type", "antall funn", "repoer"],
    ...[...perNummer]
      .sort((a, b) => b[1].funn - a[1].funn)
      .map(([n, p]) => [n, p.type, p.funn, [...p.repoer].join(", ")]),
  ]),
  "",
  "## Alle funn",
  tsv([
    ["repo", "commit", "fil", "linje (0 = filnavn)", "type", "nummer"],
    ...funn.map((f) => [f.repo, f.commit, f.fil, f.linje, f.type, f.nummer]),
  ]),
  "",
].join("\n");
writeSync(fd, innhold);
closeSync(fd);

// Terminal: bare antall
const bredde = Math.max(...oppsummering.map((o) => o.navn.length), 4);
console.log(`\n${"repo".padEnd(bredde)}  funn  numre  filer`);
for (const o of oppsummering) {
  if (o.feil) console.log(`${o.navn.padEnd(bredde)}  feil: ${o.feil}`);
  else console.log(`${o.navn.padEnd(bredde)}  ${String(o.funn).padStart(4)}  ${String(o.numre).padStart(5)}  ${String(o.filer).padStart(5)}`);
}
const iFlere = [...perNummer.values()].filter((p) => p.repoer.size > 1).length;
console.log(`\nTotalt: ${funn.length} funn, ${perNummer.size} ulike numre (${iFlere} finnes i flere repoer).`);
console.log(`Skrevet til ${utsti}. Slett filen når du er ferdig.`);
