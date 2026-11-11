// Gyldige numre lages mens testen kjører. Ingen gyldige fnr står som tekst i
// filen, ellers ville fnr-guard stoppet sin egen commit.
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { blokkertType, skannTekst, lesUnntak, masker } from "./fnr-guard.mjs";

const HER = dirname(fileURLToPath(import.meta.url));

/** Lager et gyldig 11-sifret nummer fra 6 datosiffer ved å finne individnummer med gyldige kontrollsiffer. */
function lagNummer(dato6, start = 100) {
  const v1 = [3, 7, 6, 1, 8, 9, 4, 5, 2];
  const v2 = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
  for (let ind = start; ind < 1000; ind++) {
    const ni = (dato6 + String(ind).padStart(3, "0")).split("").map(Number);
    let k1 = 11 - (ni.reduce((s, n, i) => s + n * v1[i], 0) % 11);
    if (k1 === 11) k1 = 0;
    if (k1 === 10) continue;
    const ti = [...ni, k1];
    let k2 = 11 - (ti.reduce((s, n, i) => s + n * v2[i], 0) % 11);
    if (k2 === 11) k2 = 0;
    if (k2 === 10) continue;
    return ti.join("") + k2;
  }
  throw new Error("fant ikke gyldig nummer");
}

const FNR = lagNummer("150385");
const FNR2 = lagNummer("010190");
const DNR = lagNummer("550385"); // dag + 40
const HNR = lagNummer("154385"); // måned + 40 (Dolly)
const TNR = lagNummer("158385"); // måned + 80 (Tenor)

test("blokkerer gyldig fnr og dnr", () => {
  assert.equal(blokkertType(FNR), "fnr");
  assert.equal(blokkertType(DNR), "dnr");
});

test("slipper syntetiske og ugyldige numre gjennom", () => {
  assert.equal(blokkertType(HNR), null);
  assert.equal(blokkertType(TNR), null);
  assert.equal(blokkertType("12345678901"), null);
  assert.equal(blokkertType("11111111111"), null);
  // Eksempler fra fnrvalidator: T-nummer og D-nummer + T-nummer
  assert.equal(blokkertType("10915596784"), null);
  assert.equal(blokkertType("50846202355"), null);
});

test("finner numre i JSON-strenger og JSON-tall", () => {
  assert.deepEqual(skannTekst(`{"fnr": "${FNR}"}`), [{ linje: 1, type: "fnr" }]);
  assert.deepEqual(skannTekst(`{\n  "ident": ${DNR}\n}`), [{ linje: 2, type: "dnr" }]);
});

test("finner numre med skilletegn mellom 6 og 5 siffer", () => {
  for (const skille of [" ", "-", "."]) {
    const tekst = `${FNR.slice(0, 6)}${skille}${FNR.slice(6)}`;
    assert.equal(skannTekst(tekst).length, 1, `skilletegn '${skille}'`);
  }
});

test("treffer ikke når nummeret er del av et lengre tall", () => {
  assert.deepEqual(skannTekst(`1${FNR}`), []);
  assert.deepEqual(skannTekst(`${FNR}9`), []);
});

test("unntakslisten slipper gjennom bare oppførte numre", () => {
  const unntak = lesUnntak(`# Bekreftet syntetisk, kilde: test\n${FNR}  # kommentar\n\n`);
  assert.deepEqual(skannTekst(`${FNR} ${FNR2}`, unntak), [{ linje: 1, type: "fnr" }]);
});

test("ugyldig linje i unntakslisten gir feil", () => {
  assert.throws(() => lesUnntak("1234"), /linje 1/);
});

test("masker skjuler blokkerte numre", () => {
  assert.equal(masker(`data/${FNR}.json`), "data/***********.json");
  assert.equal(masker(`data/${TNR}.json`), `data/${TNR}.json`);
});

test("scan.mjs --staged: stopper commit, skriver ikke nummeret og slipper unntak", () => {
  const repo = mkdtempSync(join(tmpdir(), "fnr-guard-"));
  try {
    const g = (...a) => execFileSync("git", a, { cwd: repo });
    g("init", "-q");
    writeFileSync(join(repo, "ok.json"), `{"a": "${HNR}", "b": "12345678901"}\n`);
    writeFileSync(join(repo, "feil.json"), `{\n"fnr": "${FNR}"\n}\n`);
    g("add", ".");
    const kjør = () => spawnSync("node", [join(HER, "scan.mjs"), "--staged"], { cwd: repo, encoding: "utf8" });

    const r = kjør();
    assert.equal(r.status, 1);
    assert.match(r.stderr, /feil\.json:2 {2}type=fnr/);
    assert.doesNotMatch(r.stdout + r.stderr, new RegExp(FNR.slice(0, 6)));

    writeFileSync(join(repo, ".fnr-allowlist"), `${FNR} # syntetisk, kilde: test\n`);
    g("add", ".fnr-allowlist");
    assert.equal(kjør().status, 0);
  } finally {
    rmSync(repo, { recursive: true, force: true });
  }
});
