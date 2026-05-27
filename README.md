# watson-developer

![Holmes og Watson](docs/holmes-og-watson.png)

Inngangsport og utviklermiljø for **Team Holmes** sin Watson-portefølje.

> Watson er Nav Kontrolls system for å avdekke og forebygge misbruk av Nav-ytelser.
> Saksbehandlere bruker Watson til å administrere kontrollsaker og søke opp brukere.

---

## Portefølje

| Repo | Teknologi | Beskrivelse | Dokumentasjon |
|------|-----------|-------------|---------------|
| [watson-admin-api](https://github.com/navikt/watson-admin-api) | Spring Boot 4 + Kotlin | Kjernebackend — kontrollsaker, tilgangskontroll, Kafka | |
| [watson-sak-frontend](https://github.com/navikt/watson-sak-frontend) | React Router v7 + Aksel | Saksbehandler-UI for kontrollsaker | [Confluence](https://confluence.adeo.no/spaces/THLMS/pages/720913429/Watson+Sak) |
| [watson-sok](https://github.com/navikt/watson-sok) | React Router v7 + Aksel | Oppslag på brukere (fnr / d-nummer) | [Confluence](https://confluence.adeo.no/spaces/THLMS/pages/720908266/Watson+S%C3%B8k) |
| [nav-persondata-api](https://github.com/navikt/nav-persondata-api) | Spring Boot + Kotlin | Persondata, ytelser og arbeidsforhold | [Confluence](https://confluence.adeo.no/spaces/THLMS/pages/720908266/Watson+S%C3%B8k) |

Se [docs/arkitektur/](docs/arkitektur/README.md) for systemkart og dataflyt.

---

## Kom i gang

> 💡 Ny i teamet? Start med [docs/onboarding/sjekkliste.md](docs/onboarding/sjekkliste.md).

### 1. Sett opp AI-verktøy (cplt + nav-pilot)

```bash
./scripts/setup-copilot.sh
```

Installerer [cplt](https://github.com/navikt/cplt) (kernel-sandbox for AI-agenter) og
[nav-pilot](https://ki-utvikling.nav.no/nav-pilot/docs) (Nav-kunnskap for Copilot).
Genererer cplt-config tilpasset Watson-porteføljen. Idempotent — trygt å kjøre flere ganger.

### 2. Sjekk at verktøyene er på plass

```bash
./scripts/doctor.sh
```

Skriptet verifiserer at alle nødvendige verktøy er installert med riktig versjon.

### 3. Klon alle Watson-repoer

```bash
./scripts/clone-repos.sh
```

Idempotent — kjør igjen for å oppdatere eksisterende repoer med `git pull`.

### 4. Opprett kind-kluster

```bash
./scripts/setup-kind.sh
```

Idempotent — trygt å kjøre flere ganger. Oppretter kluster `watson` og setter kubectl-kontekst.

### 5. Start lokalmiljøet

```bash
tilt up
```

Åpne [Tilt UI](http://localhost:10350) for status og logger.

---

## Verktøykrav

| Verktøy | Installasjon | Brukes til |
|---------|-------------|-----------|
| [cplt](https://github.com/navikt/cplt) | `brew install navikt/tap/cplt` | Kernel-sandbox for AI-agenter |
| [nav-pilot](https://ki-utvikling.nav.no/nav-pilot/docs) | `brew install navikt/tap/nav-pilot` | Nav-kunnskap for GitHub Copilot |
| [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) | `brew install kind` | Lokal Kubernetes-kluster |
| [tilt](https://docs.tilt.dev/install.html) | `brew install tilt` | Lokal utviklingsserver |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | `brew install kubectl` | Kubernetes-klient |
| [gcloud](https://cloud.google.com/sdk/docs/install) | se lenke | GCP-autentisering og secrets |
| [k9s](https://k9scli.io/topics/install/) | `brew install k9s` | Kubernetes dashboard (valgfritt) |
| Java 21 | `brew install --cask temurin@21` | watson-admin-api, nav-persondata-api |
| Node.js LTS | `brew install node` | watson-sak-frontend, watson-sok |
| [pnpm](https://pnpm.io/installation) | `corepack enable` | Pakkebehandler for frontend |

Usikker? Kjør `./scripts/doctor.sh` — det forteller deg hva som mangler.

---

## Lokalmiljø: Hybrid-modus

Infrastruktur kjører i kind (Kubernetes), applikasjoner som lokale prosesser:

| Tjeneste | Kjøres i | Port |
|----------|----------|------|
| PostgreSQL | kind | 5432 |
| mock-oauth2-server | kind | 8090 |
| watson-admin-api | lokal (`bootRun`) | 8080 |
| watson-sak-frontend | lokal (`pnpm run dev:local`) | 5174 |

> Token til watson-sak-frontend hentes automatisk fra mock-oauth2-server ved Tilt-oppstart.

`watson-admin-api` og `watson-sak-frontend` restartes **manuelt** via Tilt UI eller `tilt trigger <navn>`.

### Nyttige lenker (når Tilt er oppe)

| Tjeneste | URL |
|----------|-----|
| Swagger UI | http://localhost:8080/swagger-ui/index.html |
| Health | http://localhost:8080/actuator/health |
| Watson Sak | http://localhost:5174 |
| mock-oauth2-server | http://localhost:8090 |
| Tilt UI | http://localhost:10350 |

### Hent token for lokal testing

```bash
curl -s -X POST http://localhost:8090/azuread/token \
  -d "grant_type=client_credentials&client_id=watson-admin-api&client_secret=mock" \
  | python3 -m json.tool
```

---

## Katalogstruktur

```
parent/
├── watson-developer/          ← dette repoet
│   ├── Tiltfile
│   ├── kind/cluster.yaml
│   ├── k8s/watson-admin-api/
│   ├── scripts/
│   │   ├── clone-repos.sh
│   │   ├── setup-kind.sh
│   │   └── doctor.sh
│   └── docs/
│       ├── arkitektur/
│       ├── domene/
│       └── onboarding/
├── nav-persondata-api/
├── watson-admin-api/
├── watson-sak-frontend/
└── watson-sok/
```

---

## Miljøer og deployment

| Miljø | Plattform | Deployment |
|-------|-----------|-----------|
| dev | Nais GCP (nav-dev-gcp) | Ved merge til `main` |
| prod | Nais GCP (nav-prod-gcp) | Ved ny GitHub Release |

Se GitHub Actions i hvert repo for detaljer. Dev-deployment kan trigges manuelt via Actions-fanen.

---

## Nyttige lenker

| Ressurs | Lenke |
|---------|-------|
| GitHub-team | [navikt/holmes](https://github.com/orgs/navikt/teams/holmes) |
| Nais console | [console.nav.cloud.nais.io](https://console.nav.cloud.nais.io) |
| Slack | `#team-holmes` — legg til kanalene manuelt |
| Confluence | [Team Holmes](https://confluence.adeo.no/spaces/THLMS) |

---

## Fallback: docker-compose

`watson-admin-api` har en `docker-compose.yml` som alternativ til Tilt:

```bash
cd ../watson-admin-api
docker-compose up
```

> **Merk:** `docker-compose` er ikke lenger primær kjøremetode og støtter ikke full portefølje.