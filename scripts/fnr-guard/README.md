# fnr-guard

Stopper commits som inneholder gyldige fødselsnumre eller D-numre. Det er et siste vern mot at persondata om ekte personer havner i git.

## Hva som stoppes

| Type | Eksempel på kilde | Resultat |
|---|---|---|
| Fødselsnummer (fnr) | ekte person | 🛑 stoppes |
| D-nummer (dag + 40) | ekte person | 🛑 stoppes |
| H-nummer (måned + 40) | Dolly | ✅ slipper gjennom |
| T-nummer (måned + 80) | Tenor | ✅ slipper gjennom |
| Ugyldige tall, som `12345678901` | mock | ✅ slipper gjennom |

Numrene valideres med [@navikt/fnrvalidator](https://github.com/navikt/fnrvalidator). Skanneren finner 11 siffer etter hverandre, også med mellomrom, bindestrek eller punktum mellom de 6 første og de 5 siste. Filnavn skannes også. PDF-er skannes når `pdftotext` er installert (`brew install poppler`).

Utskriften inneholder aldri selve nummeret, bare fil, linje og type.

## Installasjon

`scripts/clone-repos.sh` og `./sync.sh` installerer hooken automatisk. Du kan også kjøre den selv:

```sh
./scripts/install-git-hooks.sh          # hopper over repoer med egen core.hooksPath
./scripts/install-git-hooks.sh --force  # overstyrer
```

Skriptet setter `core.hooksPath` i hvert repo under `repos/` til `scripts/git-hooks/`. Hooken kjører også repoets egen `.git/hooks/pre-commit` etterpå, hvis den finnes. Mangler Node eller avhengighetene, stopper hooken commiten.

## CI

`git commit --no-verify` hopper over hooken. Derfor kjører hvert repo samme sjekk i GitHub Actions. Kopier `caller-workflow.yml` til `.github/workflows/fnr-guard.yml` og bytt `REPLACE_WITH_SHA` med en commit-SHA fra `main` i watson-developer.

## Unntak

Et nummer som er bekreftet syntetisk, men likevel gyldig som fnr eller D-nummer, kan føres i `.fnr-allowlist` i roten av repoet:

```
# Kilde: <hvor nummeret kommer fra, og hvem som har bekreftet at det er syntetisk>
<11 siffer>
```

Hold filen tom så langt det går. Et gyldig nummer kan tilhøre en ekte person, og da publiserer unntakslisten det. Bytt heller til et nummer fra Dolly eller Tenor.

## Manuell skanning

Kjør fra roten av repoet som skal skannes:

```sh
node <watson-developer>/scripts/fnr-guard/scan.mjs --all       # alle sporede filer nå
node <watson-developer>/scripts/fnr-guard/scan.mjs --history   # hele historikken, alle brancher
```

### Eksportere numrene for gjennomgang

For å sjekke om numrene tilhører ekte personer, kan du skrive dem til en fil. Kjør fra roten av watson-developer:

```sh
node scripts/fnr-guard/eksporter-funn.mjs ~/fnr-funn.txt --history [repo-sti ...]
```

Uten repo-stier skanner skriptet alle repoene i `repos/`. Terminalen viser bare antall funn per repo. Fila viser hvert nummer på tvers av repoene, og deretter alle funn med repo, commit, fil og linje.

⚠️ Fila inneholder persondata hvis numrene er ekte. Den får rettigheter `600`, og skriptet nekter å legge den i et git-repo. Slett den når du er ferdig.

## Når CI finner et nummer

Da er nummeret allerede på GitHub. Behandle det som et personvernavvik, ikke som en vanlig byggfeil:

1. Ikke merge. Lukk PR-en.
2. Meld avviket i Navs avvikssystem.
3. Fjern nummeret fra historikken med `git filter-repo`, og be GitHub Support fjerne cachede visninger og PR-referanser.

## Utvikling

```sh
cd scripts/fnr-guard && npm ci --ignore-scripts && npm test
```

Testene lager gyldige numre mens de kjører. Skriv aldri et gyldig fnr rett inn i en testfil, for da stopper hooken sin egen commit.
