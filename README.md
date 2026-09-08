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

## Starte lokalmiljøet interaktivt

```bash
./scripts/start.sh
```

Spør hvilken bruker du vil logge inn som i `watson-sak-frontend` (saksbehandler eller leder,
se tabellen under), setter `BRUKERPROFIL` deretter, og kjører `tilt up` med output direkte i
terminalen. Praktisk når du ikke trenger å huske hvilken profil-id som hører til hvem.

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
BRUKERPROFIL=leder-øst tilt up watson-sak-frontend
```

`BRUKERPROFIL` styrer hvilket OAuth-token `start-sak-frontend.sh` henter fra
mock-oauth2-server, og dermed hvilken mock-bruker (via `NomClientMock`/`mock-saksbehandlere.json`)
backenden logger deg inn som:

| `BRUKERPROFIL`         | Navn                 | NAVident  | Enhet                        | Leder? |
| ---------------------- | -------------------- | --------- | ---------------------------- | ------ |
| `saksbehandler-analyse` (default) | Bjarte Byråkratsen | `L999999` | NAV Kontroll Analyse Seksjon 1 | Nei    |
| `leder-analyse`        | Stian Sjeferud       | `L900006` | NAV Kontroll Analyse Seksjon 1 | Ja     |
| `leder-øst`            | Ove Overordnerud     | `L900000` | NAV Kontroll Øst Seksjon 1   | Ja     |
| `leder-vest`           | Kari Kommandørsen    | `L900001` | NAV Kontroll Vest Seksjon 1  | Ja     |
| `saksbehandler-øst-1`  | Ulrikke Utrederson   | `L900002` | NAV Kontroll Øst Seksjon 1   | Nei    |
| `saksbehandler-øst-2`  | Trine Trygdesen      | `L900003` | NAV Kontroll Øst Seksjon 2   | Nei    |
| `saksbehandler-vest-1` | Kjell Kontrollsen    | `L900004` | NAV Kontroll Vest Seksjon 1  | Nei    |
| `saksbehandler-vest-2` | Gunnar Granskeren    | `L900005` | NAV Kontroll Vest Seksjon 2  | Nei    |

De tre lederprofilene og deres saksbehandlere under seg (én leder per enhet) gjør det mulig å
teste overføring av saker mellom saksbehandlere i samme enhet og på tvers av enheter
(Analyse/Øst/Vest). Uten `BRUKERPROFIL` beholder Tilt dagens standard og logger deg inn som
`saksbehandler-analyse`.

Starter du Tilt fra en allerede kjørende sesjon, stopp frontend-ressursen først og start den
på nytt med miljøvariabelen satt, f.eks. `BRUKERPROFIL=leder-øst tilt trigger watson-sak-frontend`
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