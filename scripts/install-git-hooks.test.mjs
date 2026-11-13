import assert from "node:assert/strict";
import { chmod, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { afterEach, test } from "node:test";

const temporaryDirectories = [];
const sourceScript = path.join(path.dirname(fileURLToPath(import.meta.url)), "install-git-hooks.sh");

afterEach(async () => {
  await Promise.all(temporaryDirectories.splice(0).map((directory) => rm(directory, { recursive: true, force: true })));
});

async function createFixture({ repos = { repo: undefined }, failWrites = [] } = {}) {
  const directory = await mkdtemp(path.join(os.tmpdir(), "install-git-hooks-"));
  temporaryDirectories.push(directory);

  const scriptsDirectory = path.join(directory, "scripts");
  const reposDirectory = path.join(directory, "repos");
  const binDirectory = path.join(directory, "bin");
  await Promise.all([
    mkdir(scriptsDirectory, { recursive: true }),
    mkdir(reposDirectory, { recursive: true }),
    mkdir(binDirectory, { recursive: true }),
  ]);
  const scriptPath = path.join(scriptsDirectory, "install-git-hooks.sh");
  await writeFile(scriptPath, await readFile(sourceScript));

  const values = {};
  for (const [name, value] of Object.entries(repos)) {
    await mkdir(path.join(reposDirectory, name));
    if (value !== undefined) values[name] = value;
  }
  const statePath = path.join(directory, "fake-git-state.json");
  await writeFile(statePath, JSON.stringify({ values, writes: [], failWrites }));

  const fakeGitPath = path.join(binDirectory, "git");
  await writeFile(
    fakeGitPath,
    `#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");
const args = process.argv.slice(2);
const repo = path.basename(args[1]);
const statePath = process.env.FAKE_GIT_STATE;
const state = JSON.parse(fs.readFileSync(statePath, "utf8"));
if (args[2] === "rev-parse") process.exit(0);
if (args[2] !== "config") process.exit(2);
if (args[3] === "--get") {
  if (state.values[repo] === undefined) process.exit(1);
  console.log(state.values[repo]);
  process.exit(0);
}
if (args[3] !== "core.hooksPath") process.exit(2);
state.writes.push({ repo, value: args[4] });
fs.writeFileSync(statePath, JSON.stringify(state));
if (state.failWrites.includes(repo)) {
  console.error("fake git write denied");
  process.exit(3);
}
state.values[repo] = args[4];
fs.writeFileSync(statePath, JSON.stringify(state));
`,
  );
  await chmod(fakeGitPath, 0o755);

  return {
    directory,
    scriptPath,
    statePath,
    hooksPath: path.join(scriptsDirectory, "git-hooks"),
    run(...args) {
      const result = spawnSync("bash", [scriptPath, ...args], {
        encoding: "utf8",
        env: {
          ...process.env,
          PATH: `${binDirectory}${path.delimiter}${process.env.PATH}`,
          FAKE_GIT_STATE: statePath,
        },
      });
      return { status: result.status, stdout: result.stdout, stderr: result.stderr };
    },
    async state() {
      return JSON.parse(await readFile(statePath, "utf8"));
    },
  };
}

test("identisk core.hooksPath hoppes over uten skriving", async () => {
  const fixture = await createFixture();
  const state = await fixture.state();
  state.values.repo = fixture.hooksPath;
  await writeFile(fixture.statePath, JSON.stringify(state));

  const result = fixture.run();
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual((await fixture.state()).writes, []);
  assert.match(result.stdout, /Ferdig: 1 installert, 0 hoppet over/);
});

test("--force skriver ikke når core.hooksPath allerede er identisk", async () => {
  const fixture = await createFixture();
  const state = await fixture.state();
  state.values.repo = fixture.hooksPath;
  await writeFile(fixture.statePath, JSON.stringify(state));

  const result = fixture.run("--force");
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual((await fixture.state()).writes, []);
});

test("manglende core.hooksPath installeres", async () => {
  const fixture = await createFixture();

  const result = fixture.run();
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual((await fixture.state()).writes, [{ repo: "repo", value: fixture.hooksPath }]);
  assert.match(result.stdout, /Ferdig: 1 installert, 0 hoppet over/);
});

test("annen core.hooksPath beholdes uten --force", async () => {
  const fixture = await createFixture({ repos: { repo: "/existing/hooks" } });

  const result = fixture.run();
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual((await fixture.state()).writes, []);
  assert.match(result.stdout, /Ferdig: 0 installert, 1 hoppet over/);
});

test("--force erstatter en annen core.hooksPath", async () => {
  const fixture = await createFixture({ repos: { repo: "/existing/hooks" } });

  const result = fixture.run("--force");
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual((await fixture.state()).writes, [{ repo: "repo", value: fixture.hooksPath }]);
});

test("skrivefeil gir feilstatus og forklarer hvordan hooken installeres", async () => {
  const fixture = await createFixture({ failWrites: ["repo"] });

  const result = fixture.run();
  assert.equal(result.status, 1);
  assert.match(result.stderr, /repo: kunne ikke installere fnr-guard/);
  assert.match(result.stderr, /utenfor sandkassen/);
  assert.doesNotMatch(result.stdout, /Ferdig:/);
});

test("--status godkjenner riktig core.hooksPath", async () => {
  const fixture = await createFixture();
  const state = await fixture.state();
  state.values.repo = fixture.hooksPath;
  await writeFile(fixture.statePath, JSON.stringify(state));

  const result = fixture.run("--status");
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /repo/);
  assert.deepEqual((await fixture.state()).writes, []);
});

test("--status rapporterer manglende core.hooksPath", async () => {
  const fixture = await createFixture();

  const result = fixture.run("--status");
  assert.equal(result.status, 1);
  assert.match(result.stdout, /repo: fnr-guard er ikke installert/);
  assert.deepEqual((await fixture.state()).writes, []);
});

test("--status rapporterer en annen core.hooksPath", async () => {
  const fixture = await createFixture({ repos: { repo: "/existing/hooks" } });

  const result = fixture.run("--status");
  assert.equal(result.status, 1);
  assert.match(result.stdout, /core\.hooksPath peker et annet sted \(\/existing\/hooks\)/);
  assert.deepEqual((await fixture.state()).writes, []);
});
