# Sjekkliste for nye utviklere — Team Holmes

Velkommen til Team Holmes! Følg denne sjekklisten for å komme i gang med Watson-porteføljen.
Spør en kollega dersom noe er uklart — vi hjelper gjerne.

> 💡 **Tips:** Følg «Kom i gang» i [README](../../README.md): klon repoet, kjør
> `./scripts/bootstrap.sh` og be agenten kjøre skillen `watson-setup`.

---

## 🔑 Tilganger (be om hjelp fra leder eller teammedlem)

- [ ] Tilgang til GitHub-organisasjon [navikt](https://github.com/navikt) og team [holmes](https://github.com/orgs/navikt/teams/holmes)
- [ ] Tilgang til [Nais console](https://console.nav.cloud.nais.io) — namespace `holmes` i dev og prod
- [ ] Azure AD-grupper: `0000-CA-kontroll-Watson` (ledere: `0000-CA-kontroll-Watson-Leder`) for Watson Sak, og `0000-GA-kontroll-Oppslag-Bruker-Basic` og `0000-GA-kontroll-Oppslag-Bruker-Utvidet` for watson-sok
- [ ] Tilgang til [Grafana](https://grafana.nav.cloud.nais.io) for overvåking
- [ ] Invitasjon til relevante Slack-kanaler (se teammedlem for liste)

---

## 🛠 Verktøy

Kjør `./scripts/doctor.sh` — det sjekker hva som mangler automatisk.

Manuell sjekkliste:

- [ ] Xcode Command Line Tools — `xcode-select --install`
- [ ] [Homebrew](https://brew.sh) er installert (`/opt/homebrew/bin/brew` eller `/usr/local/bin/brew`)
- [ ] `git` og `gh` — `brew install git gh`, logg inn med `gh auth login`
- [ ] KI-agent (opencode, Copilot CLI eller pi) — `./scripts/bootstrap.sh`
- [ ] Docker Desktop — `brew install --cask docker`, start den én gang og godta lisensen
- [ ] `kind` — `brew install kind`
- [ ] `tilt` — `brew install tilt`
- [ ] `kubectl` — `brew install kubectl`
- [ ] `gcloud` — [installer fra Google](https://cloud.google.com/sdk/docs/install)
- [ ] `k9s` — `brew install k9s` (valgfritt, men anbefalt)
- [ ] Java 21 — `brew install --cask temurin@21`
- [ ] Node.js LTS — `brew install node`
- [ ] pnpm — `corepack enable` (etter Node er installert)

---

## 📂 Lokal oppsett

- [ ] Klon `watson-developer`: `git clone https://github.com/navikt/watson-developer.git`
- [ ] Kjør `./scripts/bootstrap.sh` i en vanlig terminal
- [ ] Sett opp MCP-serverne i `mcp-servere.txt`: `./scripts/setup-mcp.sh` (gjøres av bootstrap)
- [ ] Klon alle Watson-repoer: `./scripts/clone-repos.sh`
- [ ] Opprett kind-kluster: `./scripts/setup-kind.sh`
- [ ] Start lokalmiljøet: `./start`
- [ ] Verifiser at [Tilt UI](http://localhost:10350) viser grønne ressurser
- [ ] Verifiser at [Swagger UI](http://localhost:8080/swagger-ui/index.html) svarer
- [ ] Hent et testtoken og gjør et API-kall (se [LOKALMILJO.md](../LOKALMILJO.md#hent-token-for-lokal-testing))

---

## 📚 Les deg opp

- [ ] [Arkitekturkart](../arkitektur/README.md) — systemkart, dataflyt og integrasjoner
- [ ] [Domeneordbok](../domene/ordbok.md) — Watson-spesifikke begreper
- [ ] [watson-admin-api README](https://github.com/navikt/watson-admin-api) — backend-arkitektur
- [ ] [watson-sak-frontend Confluence](https://confluence.adeo.no/spaces/THLMS/pages/720913429/Watson+Sak) — frontend-oversikt
- [ ] [Nais docs](https://docs.nais.io) — plattformdokumentasjon
- [ ] [Aksel designsystem](https://aksel.nav.no) — UI-komponenter

---

## ✅ Du er klar når

- Tilt kjører uten feil
- Du kan hente et token fra mock-oauth2-server
- Du har lest arkitekturkartet og kjenner flyten mellom tjenestene
- Du har funnet Slack-kanalene og presentert deg

---

> Problemer med oppsettet? Se [docs/SETUP.md](../SETUP.md) eller spør i `#team-holmes` på Slack.
