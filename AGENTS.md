# Watson Developer — Porteføljekontekst for Copilot

Dette repoet er inngangsporten til **Team Holmes** sin Watson-portefølje.
Watson er Nav Kontrolls system for å avdekke og forebygge misbruk av Nav-ytelser (trygdesvindel).

## Portefølje

| Repo | Rolle | Teknologi |
|------|-------|-----------|
| `watson-admin-api` | Kjernebackend | Spring Boot 4 + Kotlin + PostgreSQL + Kafka |
| `watson-sak-frontend` | Saksbehandler-UI | React Router v7 + Aksel + TypeScript |
| `watson-sok` | Brukeroppslag | React Router v7 + Aksel + TypeScript |
| `nav-persondata-api` | Persondata-API | Spring Boot + Kotlin |

Sibling-repoer klones til `../` (foreldrekatalog) med `./scripts/clone-repos.sh`.

## Dette repoet

`watson-developer` inneholder:
- `Tiltfile` — lokal utviklingsserver (Tilt + kind)
- `kind/cluster.yaml` — lokal Kubernetes-kluster
- `k8s/` — Kubernetes-manifester for lokal infrastruktur
- `scripts/` — hjelpeskript (klon repoer, sett opp kluster, pre-flight sjekk)
- `docs/` — arkitektur, domene og onboarding-dokumentasjon

## Domene

- **Kontrollsak** — en sak opprettet av en saksbehandler i Nav Kontroll for å undersøke mulig misbruk
- **Saksbehandler** — Nav Kontroll-ansatt som bruker Watson
- **Tilgangskontroll** — to grupper: Basic (oppslag) og Utvidet (full tilgang)
- **Kontrollsakstype** — kategoriserer type mulig misbruk

## Tekniske regler for dette repoet

- Shell-skript følger `set -euo pipefail` og er idempotente
- Markdown bruker norsk bokmål
- Tiltfile er `starlark` (Python-dialekt) — bruk `load()` for delte funksjoner

## Relaterte agenter

Hver applikasjon i porteføljen har egne agenter under `.github/agents/`:
- `auth-agent` — Azure AD, token-validering
- `nais-agent` — Nais-deployment, GCP-ressurser
- `observability-agent` — Prometheus, Grafana
- `security-champion-agent` — trusselmodellering, personvern
