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

## Lokal ledervisning

I `watson-sak-frontend` kan lederoversikten startes direkte med mockdata:

```bash
cd ../watson-sak-frontend
pnpm dev:leder
```

Dette starter frontend på `http://localhost:5174` med mockdata og logger deg inn som leder.

Med Tilt kjører lederoversikten i stedet mot en ekte lokal `watson-admin-api`
(`ENVIRONMENT=local-backend`), slik at du får reelle saker og ansatte tilbake fra backenden.
Sett profilen ved oppstart:

```bash
BRUKERPROFIL=leder tilt up watson-sak-frontend
```

`BRUKERPROFIL` styrer hvilket OAuth-token `start-sak-frontend.sh` henter fra
mock-oauth2-server: `leder` gir et token for lokal-lederbrukeren (NAVident `L900000`), som
backenden (via `NomClientMock`/`mock-saksbehandlere.json`) anerkjenner som leder for enheten
`ka864v` (NAV Kontroll Analyse Seksjon 1). Uten `BRUKERPROFIL` (eller med
`BRUKERPROFIL=saksbehandler`) beholder Tilt dagens standard og logger deg inn som vanlig
saksbehandler (`L999999`).

Starter du Tilt fra en allerede kjørende sesjon, stopp frontend-ressursen først og start den
på nytt med miljøvariabelen satt, f.eks. `BRUKERPROFIL=leder tilt trigger watson-sak-frontend`
(eller restart via Tilt UI etter å ha eksportert variabelen i terminalen Tilt kjører i).

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