# Oppsett av utviklermiljø

Detaljert guide for å sette opp Watson-porteføljens lokale utviklingsmiljø.

> 💡 **Automatisk oppsett:** Aktiver Copilot-skillen `watson-setup`
> (`@.github/skills/watson-setup/SKILL.md`) for å automatisere hele prosessen.

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

Kjør `./scripts/doctor.sh` for å se hva som mangler.

---

## Steg-for-steg oppsett

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

Kloner alle repoer i porteføljen til foreldrekatalogen (`../`).
Idempotent — kjør igjen for å oppdatere eksisterende repoer med `git pull`.

### 4. Opprett kind-kluster

```bash
./scripts/setup-kind.sh
```

Oppretter kind-klusteret `watson` og setter kubectl-kontekst.
Idempotent — trygt å kjøre flere ganger.

### 5. Start lokalmiljøet

```bash
tilt up
```

Åpne [Tilt UI](http://localhost:10350) for status og logger.

---

## Verifiser at alt fungerer

Når Tilt er oppe, sjekk følgende:

1. Tilt UI viser grønne ressurser → [localhost:10350](http://localhost:10350)
2. Health-endepunkt svarer → [localhost:8080/actuator/health](http://localhost:8080/actuator/health)
3. Swagger UI er tilgjengelig → [localhost:8080/swagger-ui/index.html](http://localhost:8080/swagger-ui/index.html)

---

## Fallback: docker-compose

`watson-admin-api` har en `docker-compose.yml` som alternativ til Tilt:

```bash
cd ../watson-admin-api
docker-compose up
```

> **Merk:** `docker-compose` er ikke lenger primær kjøremetode og støtter ikke full portefølje.
> Bruk Tilt for å kjøre hele Watson-miljøet lokalt.

---

## Neste steg

- [docs/LOKALMILJO.md](LOKALMILJO.md) — teknisk info om lokalmiljøet (porter, token, hybrid-modus)
- [docs/onboarding/sjekkliste.md](onboarding/sjekkliste.md) — full sjekkliste for nye utviklere
