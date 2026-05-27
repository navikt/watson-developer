# Sjekkliste for nye utviklere — Team Holmes

Velkommen til Team Holmes! Følg denne sjekklisten for å komme i gang med Watson-porteføljen.
Spør en kollega dersom noe er uklart — vi hjelper gjerne.

> 💡 **Tips:** Aktiver Copilot-skillen `watson-setup` (`@.github/skills/watson-setup/SKILL.md`)
> for å automatisere hele oppsettet.

---

## 🔑 Tilganger (be om hjelp fra leder eller teammedlem)

- [ ] Tilgang til GitHub-organisasjon [navikt](https://github.com/navikt) og team [holmes](https://github.com/orgs/navikt/teams/holmes)
- [ ] Tilgang til [Nais console](https://console.nav.cloud.nais.io) — namespace `holmes` i dev og prod
- [ ] Azure AD-grupper: `0000-GA-kontroll-Oppslag-Bruker-Basic` og `0000-GA-kontroll-Oppslag-Bruker-Utvidet`
- [ ] Tilgang til [Grafana](https://grafana.nav.cloud.nais.io) for overvåking
- [ ] Invitasjon til relevante Slack-kanaler (se teammedlem for liste)

---

## 🛠 Verktøy

Kjør `./scripts/doctor.sh` — det sjekker hva som mangler automatisk.

Manuell sjekkliste:

- [ ] [Homebrew](https://brew.sh) er installert (`/opt/homebrew/bin/brew` eller `/usr/local/bin/brew`)
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

- [ ] Klon `watson-developer`: `git clone git@github.com:navikt/watson-developer.git`
- [ ] Klon alle Watson-repoer: `./scripts/clone-repos.sh`
- [ ] Opprett kind-kluster: `./scripts/setup-kind.sh`
- [ ] Start lokalmiljøet: `tilt up`
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
