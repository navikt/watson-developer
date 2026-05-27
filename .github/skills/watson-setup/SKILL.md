---
name: watson-setup
description: Sett opp watson-developer lokalmiljø fra scratch — installerer verktøy, kloner repoer, starter infrastruktur
license: MIT
compatibility: macOS with Homebrew
metadata:
  domain: onboarding
  tags: setup onboarding watson lokalmiljø kind tilt
---

# Watson Developer — Fullstendig oppsett

Denne skillen kjører hele onboarding-prosessen for watson-developer steg for steg.
Etter fullført setup har utvikleren et fungerende lokalmiljø med alle verktøy,
alle repoer klonet, kind-kluster oppe og Tilt klar til å starte.

## Forutsetninger

- macOS
- Homebrew installert
- GitHub-tilgang til navikt/watson-* repoene
- Scriptet kjøres fra watson-developer-repoets rotkatalog

## Workflow

Kjør hvert steg sekvensielt. Stopp og rapporter status mellom hvert steg.
Hvis et steg feiler, vis feilen tydelig og foreslå løsning før du fortsetter.

### Steg 1: AI-verktøy (cplt + nav-pilot)

```bash
./scripts/setup-copilot.sh
```

**Hva dette gjør:**
- Installerer `cplt` (kernel-sandbox for AI-agenter)
- Installerer `nav-pilot` (Nav-kunnskap for Copilot)
- Detekterer node version manager og genererer cplt-config
- Aktiverer shell-alias slik at `copilot` kjører gjennom sandboxen

**Forventet resultat:** `✅ Ferdig!` uten feil.

**Hvis det feiler:**
- `Homebrew er ikke installert` → Kjør `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
- `Dette scriptet støtter kun macOS` → Denne skillen er kun for macOS

### Steg 2: Pre-flight sjekk

```bash
./scripts/doctor.sh
```

**Hva dette gjør:**
- Verifiserer at alle nødvendige verktøy er installert
- Sjekker minsteversjonskrav (Java 21+, Node 20+)

**Forventet resultat:** `✅ Alt er på plass`

**Hvis det feiler — installer manglende verktøy:**

| Verktøy | Installasjonskommando |
|---------|----------------------|
| kind | `brew install kind` |
| tilt | `brew install tilt` |
| kubectl | `brew install kubectl` |
| gcloud | Se https://cloud.google.com/sdk/docs/install |
| java 21 | `brew install --cask temurin@21` |
| node | `brew install node` |
| pnpm | `corepack enable` |

Etter installasjon av manglende verktøy, kjør `./scripts/doctor.sh` på nytt for å bekrefte.

### Steg 3: Klon alle Watson-repoer

```bash
./scripts/clone-repos.sh
```

**Hva dette gjør:**
- Kloner alle Watson-porteføljens repoer til forelderkatalogen
- Hvis de allerede finnes: kjører `git pull --ff-only`

**Forventet resultat:** Alle repoer klonet/oppdatert uten feil.

**Hvis det feiler:**
- `Permission denied (publickey)` → SSH-nøkkel er ikke konfigurert for GitHub. Kjør `gh auth login` eller legg til SSH-nøkkel.
- `Kloning feilet` → Sjekk at du har tilgang til navikt-organisasjonen.

### Steg 4: Opprett kind-kluster

```bash
./scripts/setup-kind.sh
```

**Hva dette gjør:**
- Oppretter et Kubernetes-kluster kalt `watson` via kind
- Setter kubectl-kontekst til `kind-watson`

**Forventet resultat:** `✓ Klar — kjør 'tilt up' for å starte lokalmiljøet`

**Hvis det feiler:**
- Docker må kjøre. Start Docker Desktop og prøv igjen.
- Hvis kind finnes men Docker er nede: `kind delete cluster --name watson` og prøv igjen.

### Steg 5: Start Tilt

```bash
tilt up
```

**Hva dette gjør:**
- Starter lokalt utviklingsmiljø med PostgreSQL og mock-oauth2-server i kind
- Starter watson-admin-api og watson-sak-frontend som lokale prosesser

**Vent til infrastrukturen er oppe, deretter verifiser:**

```bash
# Sjekk at mock-oauth2-server svarer
curl -sf http://localhost:8090/.well-known/openid-configuration | head -1

# Sjekk at watson-admin-api svarer (kan ta opptil 30 sek)
curl -sf http://localhost:8080/actuator/health | head -1
```

**Forventet resultat:** Begge curl-kommandoene returnerer JSON.

### Steg 6: Verifiser med testtoken

```bash
TOKEN=$(curl -sf -X POST http://localhost:8090/azuread/token \
  -d "grant_type=client_credentials&client_id=watson-admin-api&client_secret=mock-secret" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

curl -sf -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/kontrollsaker | head -1
```

**Forventet resultat:** JSON-respons (tom liste `[]` er OK for nytt miljø).

## Etter fullført setup

Vis denne oppsummeringen:

```
────────────────────────────────────────
✅ Watson-lokalmiljø er klart!

Nyttige lenker:
  • Tilt UI:          http://localhost:10350
  • Swagger UI:       http://localhost:8080/swagger-ui/index.html
  • Watson Sak:       http://localhost:5174
  • mock-oauth2:      http://localhost:8090

Neste steg:
  • Les arkitekturkartet:  docs/arkitektur/README.md
  • Les domeneordbok:      docs/domene/ordbok.md
  • Spør i Slack:          #team-holmes

Tips:
  • Start Copilot med sandbox: copilot
  • Restart shell først for å aktivere cplt-alias
────────────────────────────────────────
```

## Feilsøking

Hvis noe feiler underveis:

| Problem | Løsning |
|---------|---------|
| Docker kjører ikke | Start Docker Desktop |
| Port opptatt (5432, 8080, 8090) | Stopp prosessen som bruker porten: `lsof -i :<port>` |
| kind-kluster i dårlig tilstand | `kind delete cluster --name watson && ./scripts/setup-kind.sh` |
| Tilt viser røde ressurser | Sjekk logger i Tilt UI, restart med `tilt down && tilt up` |
| npm/pnpm feil i frontend | `cd ../watson-sak-frontend && pnpm install` |
| Gradle-feil i backend | `cd ../watson-admin-api && ./gradlew clean build` |
