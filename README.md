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

---

## Kom i gang

> 💡 **Automatisk oppsett med Copilot:**
> Aktiver skillen `watson-setup` (`@.github/skills/watson-setup/SKILL.md`).
> Den installerer verktøy, kloner repoer og starter infrastrukturen.

For manuelt oppsett, se [docs/SETUP.md](docs/SETUP.md).

Ny i teamet? Start med [onboarding-sjekklisten](docs/onboarding/sjekkliste.md).

---

## Synkroniser repoene

```bash
./sync.sh
```

Sjekker ut standardbranchen (det `origin/HEAD` peker på, med fallback til `main`/`master`) og henter nyeste endringer i alle git-repoer i foreldrekatalogen.
Repoer med ukommiterte endringer i sporede filer hoppes over, slik at ingenting går tapt.

---

## Katalogstruktur

```
parent/
├── watson-developer/          ← dette repoet
│   ├── Tiltfile
│   ├── sync.sh
│   ├── kind/cluster.yaml
│   ├── k8s/watson-admin-api/
│   ├── scripts/
│   │   ├── clone-repos.sh
│   │   ├── setup-kind.sh
│   │   ├── sync-repos.sh
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

## Dokumentasjon

| Dokument | Innhold |
|----------|---------|
| [docs/SETUP.md](docs/SETUP.md) | Detaljert oppsett — verktøykrav og steg-for-steg |
| [docs/LOKALMILJO.md](docs/LOKALMILJO.md) | Teknisk: hybrid-modus, porter, token, deployment |
| [docs/arkitektur/](docs/arkitektur/README.md) | Systemkart, autentisering og dataflyt |
| [docs/domene/ordbok.md](docs/domene/ordbok.md) | Domenebegreper og forkortelser |
| [docs/onboarding/sjekkliste.md](docs/onboarding/sjekkliste.md) | Sjekkliste for nye utviklere |

---

## Nyttige lenker

| Ressurs | Lenke |
|---------|-------|
| GitHub-team | [navikt/holmes](https://github.com/orgs/navikt/teams/holmes) |
| Nais console | [console.nav.cloud.nais.io](https://console.nav.cloud.nais.io) |
| Slack | `#team-holmes` — legg til kanalene manuelt |
| Confluence | [Team Holmes](https://confluence.adeo.no/spaces/THLMS) |