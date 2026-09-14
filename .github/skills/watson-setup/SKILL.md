---
name: watson-setup
description: Sett opp watson-developer lokalmiljø fra scratch — installerer verktøy, kloner repoer og oppretter kind-kluster
license: MIT
compatibility: macOS with Homebrew
metadata:
  domain: onboarding
  tags: setup onboarding watson lokalmiljø kind tilt
---

# Watson Developer — oppsett

Denne skillen kjører onboarding-prosessen for watson-developer steg for steg.
Etter fullført setup har utvikleren alle verktøy, repoer,
frontend-avhengigheter og kind-kluster klart. Tilt startes som neste steg av
utvikleren.

## Forutsetninger

- macOS
- Homebrew installert
- Docker Desktop installert og kjørende
- Python 3.11+ (`brew install python@3.12`) — kreves for `tomllib` i steg 1
- GitHub-tilgang til navikt-repoene
- Skillen kjøres fra watson-developer-repoets rotkatalog

## Instruksjoner til agenten

Denne skillen skal kjøres i implementeringsmodus, ikke i planmodus. Hvis
planmodus er aktiv, skal du advare brukeren om at watson-setup utfører
kommandoer og endrer lokalmiljøet, og be brukeren velge at den ikke skal kjøre
i planmodus før du fortsetter.

Du skal **kjøre** kommandoene i dette dokumentet — ikke bare vise dem til brukeren.
For hvert steg:

1. Kjør kommandoen.
2. Vent på output.
3. Verifiser at resultatet matcher «Forventet resultat».
4. Hvis det feiler: vis feilen og foreslå løsningen fra «Hvis det feiler».
5. Ikke gå videre før gjeldende steg er vellykket.

## Workflow

Kjør stegene sekvensielt. Stopp og rapporter status mellom hvert steg. Hvis et
steg feiler, vis feilen tydelig og foreslå løsning før du fortsetter.

### Steg 1: AI-verktøy

```bash
./scripts/setup-copilot.sh
```

Skriptet installerer `cplt` og `nav-pilot`, detekterer node version manager og
genererer cplt-konfigurasjon med lesetilgang til Gradle-credentials og
skrivetilgang til prosjektet og repoene. Sandboxen får bevisst ikke
lesetilgang til `~/.kube/config` (inneholder cluster-admin-credentials) —
kjør `kubectl`/`tilt` direkte i terminalen utenfor sandboxen, eller legg til
tilgangen selv hvis du ønsker det.

**Forventet resultat:** `✅ Ferdig!` uten feil.

**Hvis det feiler:**

- `Homebrew er ikke installert` → Se https://brew.sh.
- `Dette scriptet støtter kun macOS` → Skillen støtter bare macOS.
- `python3 er ikke installert` eller `python3 … er for gammel` → Scriptet
  prøver å installere `python@3.12` automatisk med Homebrew (kreves for
  `tomllib`, som brukes til å lese/oppdatere cplt-config). Hvis dette feiler,
  kjør `brew install python@3.12` manuelt og prøv igjen.

**Stopp her hvis skriptet varsler at cplt-tilgangene først trer i kraft etter
restart** (meldingen «Denne økten kjører allerede inne i cplt-sandboxen …»
eller «Restart 'copilot' …»). Den nye tilgangen til Gradle er da ikke aktiv i
denne økten ennå, og de neste stegene (spesielt klargjøring av `repos/`) kan
feile med «Operation not permitted». Be
brukeren avslutte og starte Copilot-økten på nytt, og fortsett først når en
ny økt kjører skriptet på nytt uten dette varselet.

### Steg 2: Pre-flight-sjekk

```bash
./scripts/doctor.sh
```

**Forventet resultat:** `✅ Alt er på plass`.

Utenfor cplt-sandboxen installerer skriptet manglende verktøy automatisk via
Homebrew der det er mulig (kind, tilt, kubectl, gcloud, k9s, java, node,
pnpm, python). **Kjører denne skillen inni cplt-sandboxen** (som er det
vanlige), **skjer ingen auto-installasjon** — Homebrew skriver til
`/opt/homebrew`/`/usr/local`, utenfor det sandboxen har skrivetilgang til.
Skriptet varsler om dette og lister opp hva som mangler; be brukeren
installere de manglende verktøyene i en vanlig terminal utenfor Copilot-økten
(eller kjøre `./scripts/doctor.sh` der selv), og fortsett når `./scripts/doctor.sh`
rapporterer `✅ Alt er på plass` i denne sandboxen.

### Steg 3: Klon repoene

```bash
./scripts/clone-repos.sh
```

Skriptet kloner repoene til `repos/`, oppdaterer eksisterende repoer med
`git pull --ff-only` og kjører `pnpm install` i `watson-sak-frontend` og
`watson-sok`.

**Forventet resultat:** Alle repoer klonet eller oppdatert uten feil, og
frontend-avhengighetene er installert.

**Hvis det feiler:**

- `Repository not found` eller `403` → Avslutt cplt/Copilot, kjør `gh auth login`
  i en vanlig terminal utenfor sandboxen, og kontroller at du har tilgang til
  navikt-organisasjonen. Start deretter Copilot på nytt og kjør kloningen igjen.
- `Kloning feilet` → Kontroller tilgang til repoet og kjør skriptet på nytt.
- `pnpm install` feiler → Kontroller Node.js/pnpm-versjon og kjør installasjonen
  på nytt i det aktuelle frontend-repoet.

### Steg 4: Verifiser Docker

```bash
docker info > /dev/null 2>&1 && echo "Docker kjører" || echo "Docker kjører IKKE"
```

**Forventet resultat:** `Docker kjører`.

Hvis det feiler, start Docker Desktop, vent 10–15 sekunder og prøv igjen.

### Steg 5: Opprett kind-kluster

**Dette steget må kjøres i en vanlig terminal utenfor cplt-sandboxen** —
`setup-copilot.sh` (steg 1) gir bevisst ikke sandboxen lese-/skrivetilgang til
`~/.kube/config` (se steg 1), og `kind create cluster`/
`kubectl config use-context` må kunne opprette og skrive til den filen. Be
brukeren kjøre kommandoen selv i et vanlig terminalvindu, og fortsett først
når brukeren bekrefter at den er ferdig.

```bash
./scripts/setup-kind.sh
```

Skriptet oppretter klusteret `watson` og setter kubectl-konteksten til
`kind-watson`.

**Forventet resultat:** `✓ Klar — kjør './start' for å starte lokalmiljøet`.

Hvis det feiler, kontroller at Docker kjører. Hvis kind-klusteret er i dårlig
tilstand, kjør `kind delete cluster --name watson` og prøv på nytt.

## Etter fullført setup

Vis denne oppsummeringen:

```
────────────────────────────────────────
✅ Watson-oppsettet er klart!

Neste steg:
  • Start lokalmiljøet med: ./start
  • Tilt UI:                http://localhost:10350
  • Swagger UI:             http://localhost:8080/swagger-ui/index.html
  • Watson Sak:             http://localhost:5174
  • mock-oauth2:            http://localhost:8090
  • Les arkitekturkartet:   docs/arkitektur/README.md
  • Les domeneordbok:       docs/domene/ordbok.md
  • Spør i Slack:           #team-holmes

Tips:
  • Start Copilot med sandbox: copilot
  • Restart shell først for å aktivere cplt-alias
────────────────────────────────────────
```

## Feilsøking

| Problem | Løsning |
| --- | --- |
| Docker kjører ikke | Start Docker Desktop. |
| Port opptatt (5432, 8080, 8090) | Finn prosessen med `lsof -i :<port>` og stopp den. |
| kind-kluster i dårlig tilstand | `kind delete cluster --name watson && ./scripts/setup-kind.sh` |
| Tilt viser røde ressurser | Sjekk logger i Tilt UI etter at du har kjørt `./start`. |
| pnpm-feil i frontend | Kjør `cd repos/watson-sak-frontend && pnpm install` eller tilsvarende for `watson-sok`. |
| Gradle-feil i backend | `cd repos/watson-admin-api && ./gradlew clean build` |
