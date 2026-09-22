# Watson Developer: Copilot-instruksjoner

Watson er Nav Kontrolls system for å avdekke trygdesvindel. `watson-developer` inneholder lokalmiljø (Tilt + kind), skript og dokumentasjon, ikke applikasjonskode.

## Svarsstil

- Konklusjonen først. Skriv «si «forklar» for detaljer» når du hopper over begrunnelsen
- Kode direkte uten innledningsprosa
- Dropp: oppsummering av oppgaven, høflighetsfraser, avsnitt som bare gjentar hva som skal gjøres
- Still bare spørsmål når svaret faktisk endrer implementeringen
- Les filer direkte. Ikke be brukeren lime inn innhold
- Kjør målrettede tester (`./gradlew test --tests '*Test'` / `pnpm test -- <args>`) før full pipeline

## Portefølje

| Repo                  | Beskrivelse                                                                |
| --------------------- | -------------------------------------------------------------------------- |
| `holmes-brain`        | TypeScript, KI-drevet internwiki for Team Holmes                          |
| `nav-persondata-api`  | Spring Boot + Kotlin, persondata, ytelser, arbeidsforhold                 |
| `watson-admin-api`    | Spring Boot 4 + Kotlin, kontrollsaker, tilgangsstyring, Kafka, PostgreSQL |
| `watson-pdfgen`       | pdfgenrs + Docker, PDF-renderer for Watson                                |
| `watson-sak-frontend` | React Router v7 + Aksel, saksbehandler-UI                                 |
| `watson-sok`          | React Router v7 + Aksel, brukeroppslag (fnr/d-nummer)                     |

Repoer klones til `repos/` med `./scripts/clone-repos.sh`.

Synkroniser `watson-developer` og alle repoene i `repos/` med `./sync.sh`. Skriptet sjekker ut standardbranch og kjører `pull --ff-only`. Det hopper over repoer med ukommiterte endringer i sporede filer.

## Plattform og autentisering

- **Plattform**: Nais (Kubernetes/GCP), namespace `holmes`
- **Autentisering**: Azure AD med Wonderwall sidecar
- **Tilgangsgrupper**: Basic (`0000-GA-kontroll-Oppslag-Bruker-Basic`) og Utvidet
- **Lokal mock**: mock-oauth2-server på port 8090

## Regler for dette repoet

### Shell-skript

- Alltid `set -euo pipefail` øverst
- Idempotente og trygge å kjøre flere ganger
- Fargeutskrift: grønn (✓ OK), gul (⟳ hopper over), rød (✗ feil)
- Legg skript i `scripts/`, ikke i rotkatalogen. Eneste unntak er `sync.sh`, en tynn wrapper som `exec`-er `scripts/sync-repos.sh`

### Tiltfile

- Starlark (Python-dialekt)
- Infrastruktur-ressurser merkes `labels=['infra']`, backend merkes `labels=['backend']`
- Bruk `local_resource()` for prosesser som kjører utenfor kind

### Dokumentasjon

- Norsk bokmål i all dokumentasjon
- Arkitekturdokumenter i `docs/arkitektur/`
- Onboarding-innhold i `docs/onboarding/`
- Domenebegreper i `docs/domene/ordbok.md`

### Hva dette repoet IKKE er

Ikke legg til Kotlin-, TypeScript- eller Java-filer her. Applikasjonene bor i sine egne repoer.

## Lokalt utviklingsmiljø

- Kind-kluster: postgres (5432) og mock-oauth2-server (8090)
- Lokale prosesser: watson-admin-api (8080) via `./gradlew bootRun`
- Start med: `./scripts/setup-kind.sh && ./start` (kjør `setup-kind.sh` i en
  vanlig terminal utenfor cplt-sandboxen, siden den trenger tilgang til
  `~/.kube/config`, som sandboxen bevisst ikke får)

## Arbeidsflyt for Copilot

### Repoer og terminologi

- **«frontend»** betyr `repos/watson-sak-frontend`
- **«backend»** betyr `repos/watson-admin-api`
- For detaljer om frontend, se `repos/watson-sak-frontend/.github/copilot-instructions.md`
- For detaljer om backend, se `repos/watson-admin-api/.github/copilot-instructions.md`

### Når sesjonen starter

1. Ikke kjør Homebrew-kommandoer i cplt-sandboxen. Homebrew skriver til mapper utenfor det sandboxen har tilgang til.
2. Be brukeren kjøre `brew update && brew outdated --greedy nav-pilot cplt` i en vanlig terminal.
3. Hvis kommandoen viser en oppdatering, be brukeren kjøre `brew upgrade --greedy nav-pilot cplt` og starte nav-pilot på nytt før arbeidet fortsetter.

### Før du begynner

1. Kjør `./sync.sh` fra `watson-developer` før hver oppgave.
2. Sammenlign commit på `main` i `watson-developer` før og etter synkroniseringen. Hvis `main` endret seg, be brukeren starte nav-pilot på nytt slik at endringene blir lest inn. Ikke fortsett oppgaven i den gamle sesjonen.
3. Spør om Aha!-ID hvis oppgaven hører til en Aha!-sak og ID-en ikke er nevnt.
4. Opprett en ny branch fra oppdatert `main` i hvert repo som skal endres. Bruk samme branch-navn i alle berørte repoer.
5. Bruk `<Aha!-ID>/<beskrivende-navn>` når oppgaven har en Aha!-ID, for eksempel `SAK-50/legg-til-filter`. Bruk ellers et beskrivende navn med prefiks som `chore/`, `fix/` eller `feature/`.
6. Start Tilt på nytt etter at backend er oppdatert.

### Branching og commits

- Aldri commit direkte til `main`
- Opprett bare branch i repoer som faktisk endres
- Commit underveis. Ikke samle alt i én stor commit

### Pull requests

- Opprett én pull request i hvert repo som er endret, etter at lokal verifisering er fullført.
- Legg til `https://nav1.aha.io/features/<Aha!-ID>` i PR-beskrivelsen når oppgaven har en Aha!-ID.

### Verifisering før du er ferdig

- **Frontend**: `pnpm verify`
- **Backend**: `./gradlew build`

### Kjente begrensninger i sandbox

- SSH mot GitHub (port 22) er blokkert. Bruk HTTPS-remotes
- Frontend bruker `pnpm`, ikke npm eller yarn
