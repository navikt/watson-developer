# Watson Developer — Copilot-instruksjoner

Watson er Nav Kontrolls system for å avdekke trygdesvindel. `watson-developer` inneholder lokalmiljø (Tilt + kind), skript og dokumentasjon — ikke applikasjonskode.

## Svarsstil

- Konklusjonen først — si «si 'forklar' for detaljer» når begrunnelse hoppes over
- Kode direkte uten innledningsprosa
- Dropp: oppsummering av oppgaven, høflighetsfraser, avsnitt som bare gjentar hva som skal gjøres
- Still bare spørsmål når svaret faktisk endrer implementeringen
- Les filer direkte — ikke be brukeren lime inn innhold
- Kjør målrettede tester (`./gradlew test --tests *Test` / `pnpm test MinTest`) før full pipeline

## Portefølje

| Repo | Beskrivelse |
|------|-------------|
| `watson-admin-api` | Spring Boot 4 + Kotlin — kontrollsaker, tilgangsstyring, Kafka, PostgreSQL |
| `watson-sak-frontend` | React Router v7 + Aksel — saksbehandler-UI |
| `watson-sok` | React Router v7 + Aksel — brukeroppslag (fnr/d-nummer) |
| `nav-persondata-api` | Spring Boot + Kotlin — persondata, ytelser, arbeidsforhold |

Repoer klones til `../` med `./scripts/clone-repos.sh`.

## Plattform og autentisering

- **Plattform**: Nais (Kubernetes/GCP) — namespace `holmes`
- **Autentisering**: Azure AD med Wonderwall sidecar
- **Tilgangsgrupper**: Basic (`0000-GA-kontroll-Oppslag-Bruker-Basic`) og Utvidet
- **Lokal mock**: mock-oauth2-server på port 8090

## Regler for dette repoet

### Shell-skript
- Alltid `set -euo pipefail` øverst
- Idempotente — trygge å kjøre flere ganger
- Fargeutskrift: grønn (✓ OK), gul (⟳ hopper over), rød (✗ feil)
- Legg skript i `scripts/` — ikke i rotkatalogen

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
- Start med: `./scripts/setup-kind.sh && tilt up`

## Arbeidsflyt for Copilot

### Repoer og terminologi

- **«frontend»** betyr `../watson-sak-frontend`
- **«backend»** betyr `../watson-admin-api`
- For detaljer om frontend, se `../watson-sak-frontend/.github/copilot-instructions.md`
- For detaljer om backend, se `../watson-admin-api/.github/copilot-instructions.md`

### Før du begynner

1. Spør om Aha!-ID dersom den ikke er nevnt i oppgaven
2. Hent nyeste `main` i repoene som skal endres (`git pull`)
3. Opprett ny branch: `<Aha!-ID>/<beskrivende-navn>` (f.eks. `SAK-50/legg-til-filter`) — samme navn i alle berørte repoer
4. Etter pull av backend: restart Tilt

### Branching og commits

- Aldri commit direkte til `main`
- Opprett bare branch i repoer som faktisk endres
- Commit underveis — ikke samle alt i én stor commit

### Pull requests

- Legg til lenke til Aha!-saken i PR-beskrivelsen: `https://nav1.aha.io/features/<Aha!-ID>`

### Verifisering før du er ferdig

- **Frontend**: `pnpm verify`
- **Backend**: `./gradlew build`

### Kjente begrensninger i sandbox

- SSH mot GitHub (port 22) er blokkert — bruk HTTPS-remotes
- Frontend bruker `pnpm`, ikke npm eller yarn
