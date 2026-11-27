# Lokalmiljø — Teknisk oversikt

Beskriver hvordan Watson-porteføljens lokale utviklingsmiljø fungerer.

---

## Hybrid-modus

Infrastruktur kjører i kind (Kubernetes), applikasjoner kjører som lokale prosesser:

| Tjeneste            | Kjøres i                     | Port |
| ------------------- | ---------------------------- | ---- |
| PostgreSQL          | kind                         | 5432 |
| mock-oauth2-server  | kind                         | 8090 |
| watson-admin-api    | lokal (`bootRun`)            | 8080 |
| watson-sak-frontend | lokal (`pnpm run dev:local`) | 5174 |
| watson-pdfgen       | lokal Docker-container       | 8082 |
| watson-gotenberg    | lokal Docker-container       | 8083 |

> OAuth2 access token for watson-sak-frontend hentes automatisk fra mock-oauth2-server ved Tilt-oppstart.

---

## Start og restart

`watson-admin-api` og `watson-sak-frontend` restartes **manuelt** via Tilt UI eller:

```bash
tilt trigger <ressursnavn>
```

---

## Nyttige lenker (når Tilt er oppe)

| Tjeneste              | URL                                         |
| --------------------- | ------------------------------------------- |
| Tilt UI               | http://localhost:10350                      |
| Swagger UI            | http://localhost:8080/swagger-ui/index.html |
| Health                | http://localhost:8080/actuator/health       |
| Watson Sak            | http://localhost:5174                       |
| Watson PDF-gen health | http://localhost:8082/internal/is_ready     |
| Watson Gotenberg      | http://localhost:8083/health              |
| mock-oauth2-server    | http://localhost:8090                       |

---

## Hent token for lokal testing

```bash
curl -s -X POST http://localhost:8090/azuread/token \
  -d "grant_type=client_credentials&client_id=watson-admin-api&client_secret=mock" \
  | python3 -m json.tool
```

Tokenet kan brukes i `Authorization: Bearer <token>` for å kalle watson-admin-api lokalt.

---

## Miljøer og deployment

| Miljø | Plattform               | Deployment            |
| ----- | ----------------------- | --------------------- |
| dev   | Nais GCP (nav-dev-gcp)  | Ved merge til `main`  |
| prod  | Nais GCP (nav-prod-gcp) | Ved ny GitHub Release |

Se GitHub Actions i hvert repo for detaljer. Dev-deployment kan trigges manuelt via Actions-fanen.

---

## Videre lesning

- [docs/arkitektur/](arkitektur/README.md) — systemkart, autentisering og dataflyt
- [docs/domene/ordbok.md](domene/ordbok.md) — domenebegreper

## DSOP

De fire DSOP-appene starter sammen med Watson i Tilt. Oppsettet bruker faste,
syntetiske roller og lokale mocker. Ikke bruk ekte personopplysninger, bankdata
eller dokumenter. Ingen tjenester i dev eller prod trengs for normalflyten.
Installasjon av pakker og Docker-images krever nettverk.

| Tjeneste | Port | Kjøring |
| --- | ---: | --- |
| `dsop-kontroll` | 8100 | Gradle, Java 17 eller 21 |
| `dsop-kontroll-frontend` | 8000 | Lokal Express-server med bygget frontend |
| `dsop-kontroll-bank-frontend` | 3000 | Next.js med lokal integrasjonsmodus |
| `dsop-kontroll-pdf-generator` | 9000 | Node.js |
| DSOP `pdfgen` | 8070 | Docker |
| DSOP WireMock | 7165 | Lokal Java-prosess |

Alle nye tjenester bindes til loopback. Backend bruker en midlertidig Embedded
PostgreSQL-database. Sakene forsvinner ved omstart. Porten skrives til
`.local/dsop-db-port`, uten passord eller data, slik at statusskriptet finner den.

### Oppstart

Kjør oppsettet og tjenestene utenfor cplt-sandboxen. Embedded PostgreSQL trenger
delt minne som sandboxen ikke tillater.

```bash
./scripts/clone-repos.sh
./start
```

Node.js 24 brukes til kontrollfrontend og PDF-tjenesten. Bankfrontendens README
oppgir Node.js 22. Bruk repoenes låsefiler. Oppsettet oppgraderer ingen pakker.
Kontrollfrontend trenger `npm ci --legacy-peer-deps`, slik repoets CI også gjør.

Vent til DSOP-ressursene er klare i Tilt. Åpne kontrollfrontend på
<http://127.0.0.1:8000>. DSOP-rollene er faste og påvirkes ikke av Watson-profilen
du valgte i `./start`. Backend validerer fortsatt signatur, issuer, audience og
banktilgang mot lokale mocktjenester. Lokal tokenhåndtering er avgrenset med
`DSOP_LOCAL_MODE` og sperret på Nais.

### Banklenke og journalførte dokumenter

Etter en bankforespørsel viser denne kommandoen banklenken og lagret status:

```bash
bash scripts/dsop-status.sh
```

Den krever `psql` i `PATH` og kobler bare til den lokale DSOP-databasen.
Åpne banklenken og send inn syntetisk kontaktinformasjon og et syntetisk vedlegg.
Kjør statuskommandoen igjen for å kontrollere at status er `MOTTATT` og
`archive_reference` er satt.

Altinn sender ikke meldinger i lokal profil. SAF-mocken returnerer den faste
PDF-en i `mocks/dsop/__files/syntetisk.pdf`. Den er ikke et dokumentarkiv.
Faktisk genererte forespørsels- og svarbrev sendes til Dokarkiv-mocken og kan
kontrolleres i WireMocks requestjournal på <http://127.0.0.1:7165/__admin/requests>.
Journalen inneholder syntetiske dokumenter og headere i minnet. Ikke dump den til
logg eller fil.

### Verifiser normalflyten

Kjør mot et nystartet DSOP-miljø, i en annen vanlig terminal:

```bash
node scripts/verify-dsop.mjs
```

Sjekken bruker Playwright fra kontrollfrontendens eksisterende avhengigheter og
krever at Chromium er installert for den Playwright-versjonen. Den oppretter en
syntetisk sak og forespørsel via kontrollfrontendens API-proxy, åpner bankskjemaet
i nettleseren, laster opp et syntetisk vedlegg og sender svaret. Til slutt
kontrollerer den PDF-ene i journalføringskallene og faktisk `MOTTATT` i databasen.
Eksterne nettleserkall blokkeres. Sjekken tester ikke utgående trafikk fra serverne.

Mockene har faste journalpost-ID-er for ett scenario. Start både
`dsop-kontroll` og `dsop-wiremock` på nytt før du gjentar sjekken. Ingen automatisk
nullstilling sletter pågående lokalt arbeid.

### Avgrensning og rollback

V1 dekker normalflyten, ikke interaktiv innlogging eller egne feilscenarier.
Bankfrontendens vanlige dummymodus beholdes når lokal integrasjonsmodus er av.
Kontrollfrontend bruker en separat lokal Express-startfil. Ordinær server og
sesjonshåndtering er uendret.

Ved rollback reverserer du DSOP-integrasjonscommittene i berørte repoer og
starter Tilt på nytt. Ingen produksjonskonfigurasjon eller databaseskjemaer er
endret. Backendens lokale database er midlertidig og skal ikke sikkerhetskopieres.
