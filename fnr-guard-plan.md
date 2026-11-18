# Plan: navikt/fnr-guard

Vi flytter fnr-guard ut av `watson-developer/scripts/fnr-guard` til et eget public repo, så andre team i seksjonen kan bruke det som pre-commit-hook, til en engangsskanning og som GitHub Action.

Status: Fase 1–3 er godkjent. Neste steg er Fase 4 (leveranse).

## Beslutninger

| Tema | Valg |
|---|---|
| Repo | `navikt/fnr-guard`, public, MIT, eies av Team Holmes (CODEOWNERS `@navikt/holmes`) |
| Distribusjon | `@navikt/fnr-guard` på GitHub Packages, `bin: fnr-guard` |
| Pre-commit | Egen `install`-kommando, pluss dokumentert oppsett for husky og lefthook |
| CI | Composite action i rotmappen (`uses: navikt/fnr-guard@<sha>`) som kjører fra `action_path` og ikke trenger token |
| Kjøretid | Node 20+, ingen avhengigheter i runtime. Validatoren er en kopi av `@navikt/fnrvalidator` |
| Config | `.fnr-guard.json` (JSONC) |
| Første kjøring | Lokalt genereres config og kjøringen stopper. I CI og hooks brukes standardverdier, og ingenting skrives |
| Exclude | Hver exclude må ha en begrunnelse. Testdata skannes alltid |
| Blokkerte typer | fnr og dnr blokkeres alltid. Config kan bare legge til hnr og tnr |
| Unntak | Linjemarkør `fnr-guard-ignore: <begrunnelse>`. Ingen allowlist og ingen hash |
| Eksport | `eksporter-funn.mjs` blir i watson-developer og publiseres ikke |
| Språk | Norsk bokmål i dokumentasjon og feilmeldinger |
| Watson | Bytter til det nye verktøyet, kjører parallelt i én sprint og sletter deretter `scripts/fnr-guard` |

## Repostruktur

```
fnr-guard/
├── bin/fnr-guard.mjs          # CLI: scan | init | install | uninstall | status
├── src/
│   ├── kjerne.mjs             # fra fnr-guard.mjs, flyttes uendret (🔴)
│   ├── fnrvalidator.mjs       # uendret kopi, med kilde og lisens i header
│   ├── git-kilder.mjs         # fra watson
│   ├── config.mjs             # les, valider, standardverdier, strenghetsregler (🔴)
│   ├── unntak.mjs             # markøren fnr-guard-ignore (🔴)
│   ├── miljo.mjs              # skiller CI, hook og lokal kjøring (🔴)
│   ├── init.mjs               # gjenkjenning og generering av config
│   ├── glob.mjs               # include/exclude uten backtracking
│   ├── jsonc.mjs              # JSON med kommentarer
│   └── hooks.mjs              # install/uninstall, videresending, husky/lefthook-hint
├── action.yml
├── schema/fnr-guard.schema.json
├── test/                      # karakteriseringstester fra watson + nye
├── docs/
│   ├── konfigurasjon.md
│   ├── pre-commit.md
│   ├── github-actions.md
│   ├── unntak.md
│   └── nar-noe-blir-funnet.md
├── README.md, SECURITY.md, CHANGELOG.md, LICENSE, CODEOWNERS
└── .github/
    ├── dependabot.yml
    └── workflows/
        ├── ci.yml
        ├── publish.yml
        └── fnr-guard.yml       # repoet skanner seg selv med ./
```

## `.fnr-guard.json`

```jsonc
{
  "$schema": "https://raw.githubusercontent.com/navikt/fnr-guard/main/schema/fnr-guard.schema.json",
  "versjon": 1,
  "roots": ["."],                       // multi-repo: ["repos/*"]
  "include": ["**/*"],
  "exclude": [
    { "mønster": "**/node_modules/**", "begrunnelse": "Tredjepartskode" }
  ],
  "ekstraBlokkerteTyper": [],           // bare "hnr" | "tnr"
  "pdf": true,
  "maksFilstørrelseKb": 2048,
  "manglendeNode": "stopp"              // "stopp" | "advar". Alltid "stopp" i CI
}
```

Valideringsregler. Alle brudd er harde feil, og verktøyet godkjenner aldri noe stille:

- Ukjente felt gir feil.
- En exclude uten begrunnelse gir feil.
- En exclude som treffer `**/test*/**`, `**/*mock*/**` eller `**/testdata/**` gir feil.
- En ugyldig type i `ekstraBlokkerteTyper` gir feil.
- Stier med `..`, absolutte stier og stier som etter `realpath` havner utenfor repo-roten gir feil.
- En config som ikke kan valideres stopper alltid kjøringen.

## CLI

| Kommando | Oppførsel |
|---|---|
| `fnr-guard` / `scan --staged\|--range A..B\|--all\|--history` | Samme moduser som i dag. Uten config lokalt kjøres `init`, og kjøringen stopper med exit 1 og en melding om hva som skal gjøres videre. Hvis `CI=true` eller kjøringen skjer i en hook, brukes standardverdier og ingenting skrives. |
| `init [--force] [--roots …]` | Gjenkjenner multi-repo (flere `.git` under én mappe), workspaces (npm, pnpm, gradle, `go.work`), støymapper og eksisterende hook-oppsett (husky, lefthook, `core.hooksPath`). Skriver config og forklarer hva den fant. |
| `install [--force]` | Setter `core.hooksPath` i hver root og videresender til hooks i `.git/hooks`. Hvis den finner husky eller lefthook, stopper den og skriver ut en snutt som kan limes inn. |
| `status` | Viser for hver root om hooken er aktiv og om config er gyldig. |

## Unntak

Et nummer som ser ut som et gyldig fnr eller D-nummer, men ikke er det, markeres på samme linje:

```kotlin
val id = "12345678901" // fnr-guard-ignore: generert testnummer, ikke ekte person
```

- Det må stå en begrunnelse. En markør uten begrunnelse gir feil.
- Markøren gjelder bare linjen den står på.
- Ingen numre lagres noe sted, og unntaket er synlig i diffen.
- README anbefaler fortsatt numre fra Dolly eller Tenor fremfor unntak.

## Sikkerhetskrav (fra review)

1. **CI leser config fra base-branchen** (`git show <base>:.fnr-guard.json`). Hvis PR-en endrer config, feiler CI, med mindre det finnes godkjenning fra CODEOWNERS. Action-en har dette som standard.
2. **I CI gjelder alltid `manglendeNode: stopp`.** Filer over `maksFilstørrelseKb` skannes strømmende og blir ikke hoppet over.
3. **Symlenker:** bruk `lstat`. Følg aldri symlenker. Skann lenkemålet som tekst.
4. **`action.yml`:** inputs sendes bare via `env:` og siteres som `"$VAR"`. Aldri `${{ inputs.* }}` i `run:`.
5. **ReDoS:** kandidat-regexen beholdes, siden den ikke har nøstede kvantifiserere. Glob-modulen må bygges uten backtracking og ha fuzz-test.
6. **Pakkeinnhold:** begrens med `files` i `package.json`. En test sjekker at `npm pack` ikke inneholder eksport-kode.
7. **Utskrift:** vis bare fil, linje og type. Aldri linjeinnhold, heller ikke maskert. Filstier maskeres. En test sjekker at feilmeldinger aldri inneholder input.
8. **README:** forklar at CI håndhever og hooken bare hjelper. Anbefal at jobben gjøres påkrevd med branch protection.
9. **Ingen nettverkskall og ingen telemetri.**

## Public-flipp

Gjør ikke repoet public før alle punktene er gjort:

- [ ] Historikken trekkes ut med `filter-repo --subdirectory-filter scripts/fnr-guard --refs main`. Dette er gjort.
- [ ] Skann alle objekter (`git rev-list --objects --all`) og `scan --history`.
- [ ] Push til et nytt, tomt GitHub-repo, uten PR-refs og uten forks.
- [ ] En annen person går gjennom historikken og innholdet.
- [ ] Gå gjennom issues og PR-tekst før repoet gjøres public.

## CI/CD for repoet

- `ci.yml` kjører `node --test` på Node 20, 22 og 24, i tillegg til zizmor og actionlint. Alle actions er SHA-pinnet, og `permissions: contents: read`.
- `publish.yml` kjører når en release opprettes og publiserer til GitHub Packages med `packages: write` og `--provenance`.
- `fnr-guard.yml` lar repoet skanne seg selv med `uses: ./`.
- Dependabot oppdaterer actions.

## Tester

1. Watson-testene (19 stk.) flyttes uendret først og blir karakteriseringstester. De skal være grønne før noe annet endres.
2. Nye tester:
   - config-validering, med vekt på strenghetsreglene
   - glob-matching med fuzz
   - JSONC
   - init-gjenkjenning med fixtures for multi-repo, pnpm, gradle og enkeltrepo
   - markøren for unntak
   - forskjellen på CI, hook og lokal kjøring
   - at CI leser config fra base-branchen
   - symlenker
   - install og videresending av hooks
   - innholdet i `npm pack`
3. Testene lager gyldige numre mens de kjører. Skriv aldri et gyldig fnr rett inn i en testfil.

## Migrering i watson-developer

1. Publiser v1.0.0.
2. Legg til `.fnr-guard.json` med `roots: ["repos/*"]`.
3. `install-git-hooks.sh` kaller `fnr-guard install`, og `doctor.sh` kaller `fnr-guard status`.
4. Den gamle hooken kjører parallelt med den nye i én sprint.
5. Slett `scripts/fnr-guard/`. Flytt `eksporter-funn.mjs` til `scripts/` og la den importere kjernen fra pakken.

**Rollback:** sett `install-git-hooks.sh` tilbake med `git revert`. Ingen data er avhengig av byttet.

**Exit-kriterium:** `fnr-guard status` er grønn for alle repoer under `repos/`, og ingen avvik er sett mellom gammel og ny hook i parallellperioden.

## Dokumentasjon

README starter med tre veier inn: hook, engangsskanning og CI, med 30 sekunder til hver. Øverst står en oppskrift for `.npmrc` mot GitHub Packages. Detaljene ligger i `docs/`. Til slutt kommer en kort annonsering til seksjonen.

Bruken måles med GitHub code search på `navikt/fnr-guard` og nedlastingstall i GitHub Packages.

## 🔴 Rød sone

Disse delene implementeres av nav-pilot, og utvikleren reviewer i PR:

- [ ] `kjerne.mjs` flyttes uendret. Sjekk at diffen mot watson er tom.
- [ ] `config.mjs`: fnr og dnr kan ikke slås av. Ingen exclude for testdata. Ugyldig config stopper alltid. Stier må ligge under repo-roten.
- [ ] `unntak.mjs`: markøren gjelder bare sin egen linje og krever begrunnelse. Ingen nummer lagres.
- [ ] `miljo.mjs`: CI og hook skriver aldri config. CI tvinger `stopp` og leser config fra base-branchen.
