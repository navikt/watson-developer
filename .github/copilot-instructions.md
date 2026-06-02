# Watson Developer — Copilot-instruksjoner

Dette er `watson-developer`, portefølje-huben for Team Holmes. Repoet inneholder
lokalt utviklingsmiljø (Tilt + kind), skript og dokumentasjon for Watson-porteføljen.

## Hva Watson er

Watson er Nav Kontrolls system for å avdekke trygdesvindel. Saksbehandlere i Nav Kontroll
bruker Watson til å opprette og administrere kontrollsaker, søke opp brukere og se
brukerens ytelseshistorikk og arbeidsforhold.

## Porteføljeoversikt

| Repo | Beskrivelse |
|------|-------------|
| `watson-admin-api` | Spring Boot 4 + Kotlin — kontrollsaker, tilgangsstyring, Kafka, PostgreSQL |
| `watson-sak-frontend` | React Router v7 + Aksel — saksbehandler-UI |
| `watson-sok` | React Router v7 + Aksel — brukeroppslag (fnr/d-nummer) |
| `nav-persondata-api` | Spring Boot + Kotlin — persondata, ytelser, arbeidsforhold |

Alle repoer klones til foreldrekatalogen (`../`) med `./scripts/clone-repos.sh`.

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
Dette repoet inneholder ikke applikasjonskode. Ikke legg til Kotlin-, TypeScript- eller
Java-filer her. Applikasjonene bor i sine egne repoer.

## Lokalt utviklingsmiljø

Hybrid-modus: infrastruktur i kind, applikasjoner som lokale prosesser.

```
kind-kluster (watson)
├── postgres (5432)
└── mock-oauth2-server (8090)

Lokale prosesser
└── watson-admin-api (8080) via ./gradlew bootRun
```

Start med: `./scripts/setup-kind.sh && tilt up`

## Arbeidsflyt for Copilot

### Repoer og terminologi

- **«frontend»** betyr `../watson-sak-frontend`
- **«backend»** betyr `../watson-admin-api`
- For detaljer om frontend, se `../watson-sak-frontend/.github/copilot-instructions.md`
- For detaljer om backend, se `../watson-admin-api/.github/copilot-instructions.md`

### Før du begynner

1. Spør om Aha!-ID dersom den ikke er nevnt i oppgaven
2. Hent nyeste `main` i repoene som skal endres (`git pull`)
3. Opprett og sjekk ut en ny branch i repoene som skal endres
   - Format: `<Aha!-ID>/<beskrivende-navn>`, f.eks. `SAK-50/legg-til-filter`
   - Bruk samme branch-navn i alle berørte repoer
4. Etter pull av backend: restart Tilt — nye kontrollere plukkes ikke opp av en kjørende JVM

### Branching og commits

- Lag alle endringer i nye branches (ikke commit direkte til `main`)
- Opprett bare branch i repoer som faktisk endres
- Branch-navn på formatet `<Aha!-ID>/<beskrivende-navn>` (f.eks. `SAK-50/legg-til-filter`)
- Commit underveis — ikke samle alt i én stor commit

### Pull requests

- Legg til lenke til Aha!-saken i PR-beskrivelsen: `https://nav1.aha.io/features/<Aha!-ID>`

### Verifisering før du er ferdig

- **Frontend**: kjør `pnpm verify` (inkluderer test, lint, format, typecheck, unused)
- **Backend**: kjør `./gradlew build` (inkluderer test og kompilering)

### Kjente begrensninger i sandbox

- SSH mot GitHub (port 22) er blokkert — bruk HTTPS-remotes
- Frontend bruker `pnpm`, ikke npm eller yarn
