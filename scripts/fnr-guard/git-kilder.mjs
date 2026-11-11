// 🔴 Rød sone: bestemmer hvilke linjer og filer som blir skannet. Gå gjennom nøye.
//
// Felles kilder for scan.mjs og eksporter-funn.mjs:
//   - tillagteLinjer(): linjer som legges til, fra staged diff, et commit-område
//     eller hele historikken. Hvert commit skannes for seg, også merge-commits
//     (mot første forelder), slik at et nummer som legges til og fjernes i
//     neste commit, likevel blir funnet.
//   - endredeFiler(): stier som legges til eller endres, med lesefunksjon for
//     innholdet (brukes til filnavn og PDF-er).
//   - arbeidstre(): alle sporede filer slik de er nå.

import { execFileSync } from "node:child_process";
import { readFileSync, statSync } from "node:fs";
import { join } from "node:path";

const MAKS_BUFFER = 1024 * 1024 * 1024;
const COMMIT_MERKE = "@@COMMIT ";

export function lagGit(cwd = process.cwd()) {
  const git = (args, opts = {}) =>
    execFileSync("git", ["-c", "core.quotePath=false", ...args], {
      cwd,
      maxBuffer: MAKS_BUFFER,
      stdio: ["ignore", "pipe", "pipe"],
      ...opts,
    });
  git.tekst = (args) => git(args).toString("utf8");
  return git;
}

/**
 * Kilde:
 *   { type: "staged" }
 *   { type: "range", range: "A..B" }   (commits i B som ikke er i A)
 *   { type: "historikk" }              (alle brancher)
 */
function diffArgs(kilde) {
  const felles = ["-U0", "--no-color", "--no-ext-diff", "--no-renames", "--diff-filter=d"];
  if (kilde.type === "staged") return ["diff", "--cached", ...felles];
  const logg = ["log", "-p", ...felles, "--diff-merges=first-parent", `--format=${COMMIT_MERKE}%H`];
  if (kilde.type === "range") return [...logg, kilde.range];
  if (kilde.type === "historikk") return [...logg, "--all"];
  throw new Error(`ukjent kilde: ${kilde.type}`);
}

function navneArgs(kilde) {
  // -z: filnavn skilles med NUL. %x00%H gir et tomt felt foran hver commit-hash.
  // Et filnavn kan aldri være tomt, så filnavn kan ikke forveksles med commits.
  const felles = ["-z", "--name-only", "--no-renames", "--diff-filter=d"];
  if (kilde.type === "staged") return ["diff", "--cached", ...felles];
  const logg = ["log", ...felles, "--diff-merges=first-parent", "--format=%x00%H"];
  if (kilde.type === "range") return [...logg, kilde.range];
  return [...logg, "--all"];
}

/** Git siterer stier med spesialtegn i C-stil: "a\"b". */
export function avsiterSti(sti) {
  if (!sti.startsWith('"')) return sti;
  try {
    return JSON.parse(sti);
  } catch {
    return sti.slice(1, -1);
  }
}

/**
 * Leser unified diff og gir linjer som legges til: { commit, fil, linje, tekst }.
 * Holder rede på hunk-tilstand med antallet fra `@@ -a,b +c,d @@`, slik at en
 * innholdslinje som starter med `++ ` aldri blir lest som et filhode.
 */
export function* parseDiff(diff) {
  let commit = null;
  let fil = null;
  let linje = 0;
  let igjenNy = 0;
  let igjenGammel = 0;

  for (const rad of diff.split("\n")) {
    if (igjenNy > 0 || igjenGammel > 0) {
      const tegn = rad[0];
      if (tegn === "+") {
        if (fil) yield { commit, fil, linje, tekst: rad.slice(1) };
        linje++;
        igjenNy--;
      } else if (tegn === "-") {
        igjenGammel--;
      } else if (tegn === " ") {
        linje++;
        igjenNy--;
        igjenGammel--;
      }
      // `\ No newline at end of file` påvirker ikke tellingen
      continue;
    }

    if (rad.startsWith(COMMIT_MERKE)) {
      commit = rad.slice(COMMIT_MERKE.length).trim();
      fil = null;
    } else if (rad.startsWith("diff --git ")) {
      fil = null;
    } else if (rad.startsWith("+++ ")) {
      const sti = avsiterSti(rad.slice(4));
      fil = sti === "/dev/null" ? null : sti.replace(/^b\//, "");
    } else if (rad.startsWith("@@ ")) {
      const m = /^@@ -\d+(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/.exec(rad);
      if (!m) throw new Error("kunne ikke lese hunk-hode i diff");
      igjenGammel = m[1] === undefined ? 1 : Number(m[1]);
      linje = Number(m[2]);
      igjenNy = m[3] === undefined ? 1 : Number(m[3]);
    }
  }
}

export function tillagteLinjer(kilde, git = lagGit()) {
  return parseDiff(git.tekst(diffArgs(kilde)));
}

/**
 * Leser utdata fra navneArgs() og gir { commit, sti }.
 * Staged: `sti\0sti\0`. Logg: `\0<hash>\0\n<sti>\0<sti>\0` per commit, der
 * første sti etter hashen har en ledende linjeskift.
 */
export function* parseNavneliste(utdata, staged) {
  const felter = utdata.split("\0");
  let commit = null;
  let forsteEtterHash = false;
  for (let i = 0; i < felter.length; i++) {
    let felt = felter[i];
    if (felt === "") {
      if (!staged && i + 1 < felter.length) {
        commit = felter[++i];
        forsteEtterHash = true;
      }
      continue;
    }
    if (forsteEtterHash && felt.startsWith("\n")) felt = felt.slice(1);
    forsteEtterHash = false;
    yield { commit, sti: felt };
  }
}

/** Gir { commit, sti, les } for hver fil som legges til eller endres. */
export function* endredeFiler(kilde, git = lagGit()) {
  const staged = kilde.type === "staged";
  for (const { commit, sti } of parseNavneliste(git.tekst(navneArgs(kilde)), staged)) {
    const ref = staged ? `:${sti}` : `${commit}:${sti}`;
    yield { commit, sti, les: () => git(["show", ref]) };
  }
}

/** Gir { sti, les } for hver sporet fil som finnes i arbeidstreet. */
export function* arbeidstre(git = lagGit(), cwd = process.cwd()) {
  for (const sti of git.tekst(["ls-files", "-z"]).split("\0").filter(Boolean)) {
    const full = join(cwd, sti);
    // Slettede filer og submoduler (kataloger) har ikke innhold å skanne
    yield { sti, les: () => (statSync(full, { throwIfNoEntry: false })?.isFile() ? readFileSync(full) : null) };
  }
}

let pdfAdvart = false;
/** Tekst fra en PDF, eller null hvis pdftotext mangler. */
export function pdfTilTekst(buffer) {
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

export const erPdf = (sti) => sti.toLowerCase().endsWith(".pdf");
