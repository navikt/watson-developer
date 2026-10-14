# Lasttest av Watson Sak

k6-skript som sender kall mot `watson-admin-api` i dev-gcp og simulerer saksbehandlere og ledere. Vi bruker dem til å finne ut hvor appen, databasen og avhengighetene trenger justering før prod.

Skriptene er JavaScript. Det er et bevisst unntak fra regelen om at watson-developer ikke skal ha applikasjonskode: lasttesten gjelder hele porteføljen og har ikke noe naturlig hjem i ett app-repo.

## Kom i gang

1. Installer k6 i en vanlig terminal (ikke i cplt-sandboxen): `brew install k6`.
2. Hent tokens for testidentene:

   ```bash
   ./scripts/lasttest-tokens.sh
   ```

   Skriptet viser lenken til azure-token-generator. Logg inn som testident i et privat nettleservindu, og lim inn tokenet. Legg inn minst én saksbehandler og én leder. Testen stopper hvis en rolle mangler. Tokenet vises ikke på skjermen. Det lagres i `loadtest/.tokens/tokens.json`, som er git-ignorert og bare lesbar for deg.

3. Kjør smoke-testen:

   ```bash
   TESTPERSONER=<fnr1>,<fnr2> ./scripts/lasttest.sh smoke
   ```

4. Kjør lasttesten:

   ```bash
   TESTPERSONER=<fnr1>,<fnr2> ./scripts/lasttest.sh watson-sak baseline
   ```

`./scripts/lasttest-tokens.sh --status` viser hvor lenge tokenene er gyldige. Tokenene varer omtrent én time, så hent nye før hver kjøring. `lasttest.sh` stopper før k6 starter hvis et token er utløpt eller ugyldig.

## Forutsetninger

- **Prodlikt oppsett i dev**: navikt/watson-admin-api#332 må være deployet. Uten den måler vi `db-f1-micro` og én replika, ikke det prod skal kjøre på.
- **Testidenter** i `trygdeetaten.no` med Watson-grupper. Bruk 10–20 identer. Søkegrensen gjelder per ident, og med få identer treffer flere VU-er den samme kvoten. Skriveflyten trenger utvidet tilgang, og lederflyten trenger ledergruppe.
- **Testpersoner** (syntetiske fra Dolly) som testidentene har tilgang til i tilgangsmaskin. De settes i `TESTPERSONER` og brukes når skriveflyten oppretter saker. Uten dem hopper testen over skriveflyten.
- **Saker i dev** som testidentene ser. `setup()` henter opptil 500 sak-ID-er fra saklista og avbryter hvis den ikke finner noen. Seed dev med en realistisk datamengde: lister og statistikk oppfører seg annerledes med 50 saker enn med 50 000.
- **Varsling**: Gi beskjed til teamene bak tilgangsmaskin, NOM og nav-persondata-api før lasttest og stresstest. Lesekallene går mot deres dev-tjenester.

## Scenarioer

| Scenario | Kommando | Innhold |
|---|---|---|
| `smoke` | `./scripts/lasttest.sh smoke` | Én bruker går gjennom alle flytene én gang |
| `watson-sak` | `./scripts/lasttest.sh watson-sak <profil>` | 80 % lesing, 15 % skriving og 5 % leder |
| `sok-ratelimit` | `SOK_IDENT=<navIdent> TESTPERSONER=<fnr> ./scripts/lasttest.sh sok-ratelimit` | Sjekker at søkegrensen gir 429 |

Lesing speiler loaderne i watson-sak-frontend. Sakdetaljsida henter saken og gjør så sju kall parallelt, slik `SakDetaljSide.loader.server.ts` gjør. Deretter søker den etter andre saker på personen.

Skriveflyten oppretter en sak og et dokument med låsing og tre autolagringer. Den lager også en mappe og en manuell hendelse som redigeres og slettes, og til slutt endres saken.

`sok-ratelimit` bruker opp søkekvoten til identen i inntil en time. Bruk en ident som ikke er med i de andre kjøringene.

### Profiler

| Profil | Samtidige brukere | Varighet |
|---|---|---|
| `baseline` | 10 | 12 min |
| `last` | 100 | 27 min |
| `stress` | 100 → 200 → 300 | 22 min |
| `utholdenhet` | 100 | 52 min |

### Terskler

- p95 under 500 ms for lesing og under 1500 ms for skriving
- under 1 % feilede kall
- over 99 % godkjente sjekker

k6 avslutter med feilkode når en terskel brytes. Tersklene ligger i `lib/profiler.js`.

## Hva testen ikke gjør

Testen skriver ikke til andre teams systemer i delte testmiljøer:

- journalføring (dokarkiv)
- oppretting av oppgaver (Oppgave)
- filopplasting (ClamAV og GCS)

Hvis vi trenger tall for disse, avtaler vi en egen kjøring med lav frekvens med eierteamene.

Saker fra testen får merkingen `LASTTEST`. API-et har ikke noe endepunkt for å slette saker. Sakene blir derfor liggende i dev og kommer med i statistikken i BigQuery.

## Rate limits

Grensene står på under testen.

- **Ingress**: `limit-rps: "20"` per klient-IP. Når grensen er nådd, svarer ingress-nginx med 503, som telles i `avvist_rate_limit_ingress`. 100 brukere med 3–10 sekunders tenketid gir omtrent 15–30 req/s fra én maskin, mens ekte brukere har hver sin IP. Hvis vi ser 503 i `last` eller `stress`, kjører vi k6 fra flere maskiner eller ber om en midlertidig høyere grense i dev.
- **Søk**: `SokRateLimitFilter` tillater 30 kall i burst og 120 per time per Nav-ident. Svar med 429 telles i `avvist_rate_limit_app`. På sakdetaljsida regnes ikke 429 som feil, fordi søket der skyldes at flere VU-er deler én ident.

## Overvåking under kjøring

Følg med i Grafana mens testen går:

- `http_server_requests_seconds` per URI: p95, p99 og feilrate
- `hikaricp_connections_active`, `_pending` og `_timeout`: om tilkoblingspoolen tar slutt
- `http_client_requests_seconds` per ekstern tjeneste
- JVM-heap, GC-pauser, CPU-throttling og minne i poden
- Cloud SQL: CPU, antall tilkoblinger og Query Insights. `db-custom-1-3840` tillater 100 tilkoblinger, og 4 pods med standard Hikari-pool bruker opptil 40.
- Tempo for de tregeste kallene og Loki for feil

Hvis `K6_PROMETHEUS_RW_SERVER_URL` er satt, sender `scripts/lasttest.sh` k6-metrikkene til Prometheus. Hver kjøring merkes med `testid`.

## Resultater

`scripts/lasttest.sh` lagrer oppsummeringen fra k6 i `loadtest/resultater/` (git-ignorert). Skriv funn og tiltak i holmes-brain. Typiske tiltak er større Cloud SQL-tier, større Hikari-pool, høyere CPU-request, flere replikaer, nye indekser, færre N+1-spørringer og caching av NOM og kodeverk.

## Miljøvariabler

| Variabel | Standard | Brukes til |
|---|---|---|
| `BASE_URL` | `https://watson-admin-api.intern.dev.nav.no` | Backend-adressen. Testen stopper hvis adressen ikke er HTTPS mot en host som slutter på `.dev.nav.no` |
| `TILLAT_BASE_URL` | (tom) | Sett til `true` for å kjøre mot en godkjent lokal stub |
| `TESTPERSONER` | (tom) | Kommaseparerte fødselsnumre for syntetiske testpersoner |
| `ENHET` | `ka864v` | NOM-enhet for nye saker og filtre |
| `SOK_IDENT` | (tom) | Identen til `sok-ratelimit` |
| `TENKETID_MIN` / `TENKETID_MAKS` | `3` / `10` | Pause mellom sidevisninger, i sekunder |
| `K6_PROMETHEUS_RW_SERVER_URL` | (tom) | Sender metrikker til Prometheus |
