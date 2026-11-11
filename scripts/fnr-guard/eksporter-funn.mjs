#!/usr/bin/env node
// Skriver alle gyldige fnr/dnr i Watson-repoene til en fil, slik at et menneske
// kan sjekke om de tilhører ekte personer. Numrene skrives ALDRI til terminalen,
// bare antall.
//
// Bruk:
//   node scripts/fnr-guard/eksporter-funn.mjs <utfil> [--history] [repo-sti ...]
//
// Uten repo-stier skannes alle git-repoer i watson-developer/repos/.
// --history skanner hele historikken (alle brancher), ellers sporede filer nå.
//
// Utfilen inneholder persondata hvis numrene er ekte:
// - den lages med rettigheter 600 og kan ikke ligge inne i et git-repo
// - slett den når du er ferdig

import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync, existsSync, readdirSync } from "node:fs";
import { resolve, dirname, join, basename } from "node:path";
import { fileURLToPath } from "node:url";
import { finnIRad } from "./fnr-guard.mjs";

const HER = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const historikk = args.includes("--history");
const [utfil, ...repoArgs] = args.filter((a) => a !== "--history");

if (!utfil) {
  console.error("Bruk: eksporter-funn.mjs <utfil> [--history] [repo-sti ...]");
  process.exit(2);
}
const utsti = resolve(utfil);
if (existsSync(utsti)) {
  console.error("Utfilen finnes allerede. Velg et annet navn eller slett den først.");
  process.exit(2);
}
try {
  execFileSync("git", ["-C", dirname(utsti), "rev-parse", "--is-inside-work-tree"], { stdio: "ignore" });
  console.error("Utfilen kan ikke ligge inne i et git-repo. Bruk for eksempel ~/fnr-funn.txt.");
  process.exit(2);
} catch {
  // ikke i et repo: ok
}

const reposDir = resolve(HER, "../../repos");
const repoer = (repoArgs.length ? repoArgs.map((r) => resolve(r)) : readdirSync(reposDir).map((d) => join(reposDir, d)))
  .filter((r) => existsSync(join(r, ".git")));

function skannRepo(cwd) {
  const git = (a) =>
    execFileSync("git", ["-c", "core.quotePath=false", ...a], { cwd, maxBuffer: 1024 ** 3 }).toString("utf8");
  const rader = [];
  const legg = (commit, fil, linje, tekst) => {
    for (const { type, nummer } of finnIRad(tekst)) rader.push({ commit, fil, linje, type, nummer });
  };

  if (historikk) {
    let commit = "", fil = null, nr = 0;
    for (const rad of git(["log", "--all", "-p", "-U0", "--no-color", "--no-ext-diff", "--format=@@COMMIT %h"]).split("\n")) {
      if (rad.startsWith("@@COMMIT ")) commit = rad.slice(9);
      else if (rad.startsWith("+++ ")) fil = rad === "+++ /dev/null" ? null : rad.slice(4).replace(/^"?b\//, "").replace(/"$/, "");
      else if (rad.startsWith("@@ ")) nr = Number(/\+(\d+)/.exec(rad)?.[1] ?? 0);
      else if (rad.startsWith("+") && fil) { legg(commit, fil, nr, rad.slice(1)); nr++; }
    }
    let c = "";
    for (const rad of git(["log", "--all", "--name-only", "--format=@@COMMIT %h"]).split("\n")) {
      if (rad.startsWith("@@COMMIT ")) c = rad.slice(9);
      else if (rad) legg(c, rad, 0, rad);
    }
  } else {
    for (const f of git(["ls-files", "-z"]).split("\0").filter(Boolean)) {
      legg("", f, 0, f);
      const full = join(cwd, f);
      if (!existsSync(full)) continue;
      const b = readFileSync(full);
      if (b.includes(0)) continue;
      b.toString("utf8").split(/\r?\n/).forEach((t, i) => legg("", f, i + 1, t));
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
    const unike = new Map(rader.map((r) => [[r.commit, r.fil, r.linje, r.nummer].join("\t"), r]));
    for (const r of unike.values()) funn.push({ repo: navn, ...r });
    oppsummering.push({
      navn,
      funn: unike.size,
      numre: new Set([...unike.values()].map((r) => r.nummer)).size,
      filer: new Set([...unike.values()].map((r) => r.fil)).size,
    });
  } catch (e) {
    oppsummering.push({ navn, feil: e.message.split("\n")[0] });
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
writeFileSync(utsti, innhold, { mode: 0o600 });

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
