# Lasttest av Watson Sak

k6-skript som sender kall mot `watson-admin-api` i dev-gcp og simulerer saksbehandlere og ledere. Vi bruker dem til å finne ut hvor appen, databasen og avhengighetene trenger justering før prod.

Skriptene er JavaScript. Det er et bevisst unntak fra regelen om at watson-developer ikke skal ha applikasjonskode: lasttesten gjelder hele porteføljen og har ikke noe naturlig hjem i ett app-repo.

## Kom i gang

1. Installer k6 i en vanlig terminal (ikke i cplt-sandboxen): `brew install k6`.
2. Sjekk testidentene. Saksbehandlerne er testbrukerne med `enhetId: lasttest` i `nom.ekstra-saksbehandlere` i `application-dev.yml` i watson-admin-api. Skriptet leser fila på `origin/main` i `repos/watson-admin-api`, siden det er den som er deployet. Nye saksbehandlere legger du altså inn i watson-admin-api, ikke her. Ledere står i `loadtest/ledere`, én navIdent per linje. Fila kan være tom, og da hopper testen over lederflyten. Begge stedene skal bare ha fiktive testidenter.

3. Hent tokens:

   ```bash
   ./scripts/lasttest-tokens.sh
   ```

   Skriptet går gjennom saksbehandlerne og lederne og ber bare om token for dem som mangler et token, eller har et som utløper innen 30 minutter. For hver ident logger du inn som identen i et privat nettleservindu, åpner lenken skriptet viser, og kopierer tokenet. Trykk Enter for å bruke utklippstavla, eller lim inn tokenet. Skriv `h` for å hoppe over en ident. Skriptet avviser tokenet hvis det tilhører en annen ident.

   Tokenet vises ikke på skjermen. Det lagres i `loadtest/.tokens/tokens.json`, som er git-ignorert og bare lesbar for deg. Når en ident forsvinner fra `application-dev.yml` eller `loadtest/ledere`, sletter skriptet tokenet. `--alle` henter nye tokens for alle identene.

4. Kjør smoke-testen. Den holder med én saksbehandler, og uten `TESTPERSONER` er den bare lesing:

   ```bash
   ./scripts/lasttest.sh smoke
   ```

   Med `TESTPERSONER` oppretter den også én sak merket `LASTTEST`. Med en leder i tokenfila tar den også med lederflyten.

5. Kjør lasttesten:

   ```bash
   TESTPERSONER=<fnr1>,<fnr2> ./scripts/lasttest.sh watson-sak baseline
   ```

`./scripts/lasttest-tokens.sh --status` viser hvor lenge tokenene er gyldige. Tokenene varer omtrent én time. Kjør `./scripts/lasttest-tokens.sh` før hver kjøring, så fornyer den bare tokenene som trengs. `lasttest.sh` stopper før k6 starter hvis et token er utløpt eller ugyldig.

## Forutsetninger

- **Prodlikt oppsett i dev**: navikt/watson-admin-api#332 må være deployet. Uten den måler vi `db-f1-micro` og én replika, ikke det prod skal kjøre på.
- **Testidenter** i `trygdeetaten.no` med Watson-grupper. Bruk 10–20 identer. Søkegrensen gjelder per ident, og med få identer treffer flere VU-er den samme kvoten. Skriveflyten trenger utvidet tilgang, og lederflyten trenger ledergruppe.
- **Enheten Lasttest**: Saksbehandlerne skal ikke finnes i NOM. De må stå i `nom.ekstra-saksbehandlere` i `application-dev.yml` i watson-admin-api med `enhetId: lasttest` (navikt/watson-admin-api#335). Uten dem stopper `lasttest-tokens.sh`. Da får sakene fra testen enheten Lasttest når de tildeles, og ingen ledervarsler går til ekte ledere. En saksbehandler som finnes i NOM, flytter saken til sin egen enhet. Lederen kan finnes i NOM, siden lederflyten bare leser.
- **Testpersoner** (syntetiske fra Dolly) som testidentene har tilgang til i tilgangsmaskin. De settes i `TESTPERSONER` og brukes når skriveflyten oppretter saker. Uten dem hopper testen over skriveflyten.
- **Saker i dev** som testidentene ser. `setup()` henter opptil 500 sak-ID-er fra saklista og avbryter hvis den ikke finner noen. Seed dev med en realistisk datamengde: lister og statistikk oppfører seg annerledes med 50 saker enn med 50 000.
- **Varsling**: Gi beskjed til teamene bak tilgangsmaskin, NOM og nav-persondata-api før lasttest og stresstest. Lesekallene går mot deres dev-tjenester.

## Scenarioer

| Scenario | Kommando | Innhold |
|---|---|---|
| `smoke` | `./scripts/lasttest.sh smoke` | Én saksbehandler går gjennom flytene én gang. Skriving og leder hoppes over hvis `TESTPERSONER` eller leder-token mangler |
| `watson-sak` | `./scripts/lasttest.sh watson-sak <profil>` | 80 % lesing, 15 % skriving og 5 % leder. Uten leder går lederandelen til lesing |
| `sok-ratelimit` | `SOK_IDENT=<navIdent> TESTPERSONER=<fnr> ./scripts/lasttest.sh sok-ratelimit` | Sjekker at søkegrensen gir 429 |

Lesing speiler loaderne i watson-sak-frontend. Sakdetaljsida henter saken og gjør så sju kall parallelt, slik `SakDetaljSide.loader.server.ts` gjør. Deretter søker den etter andre saker på personen. Som i frontend regnes 403 på hendelser, journalposter, filer, mapper, tillatte handlinger og søk som gyldig svar, fordi testbrukeren sjelden er knyttet til en tilfeldig sak.

Skriveflyten oppretter en sak og tildeler den til testbrukeren. Dokumenter og mapper krever at brukeren er ansvarlig eller har fått saken delt. Deretter lager den et dokument med låsing og tre autolagringer, en mappe og en manuell hendelse som redigeres og slettes. Til slutt endres merkingen på saken.

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

### Feilede kall

Rapporten viser hvilke kall og sjekker som feilet, men ikke statuskode eller feilmelding. Derfor skriver k6 en advarsel i terminalen første gang hver VU får en uventet status på et kall:

```
level=warning msg="opprett mappe: HTTP 403 POST https://.../mapper (Ingen tilgang til sak 123)"
```

Tall med 11 siffer maskeres, og meldingen kuttes etter 200 tegn. Bruk tidspunktet og URL-en til å finne samme feil i Loki.

## Hva testen ikke gjør

Testen skriver ikke til andre teams systemer i delte testmiljøer:

- journalføring (dokarkiv)
- oppretting av oppgaver (Oppgave)
- filopplasting (ClamAV og GCS)

Hvis vi trenger tall for disse, avtaler vi en egen kjøring med lav frekvens med eierteamene.

Saker fra testen får enheten Lasttest og merkingen `LASTTEST`. API-et har ikke noe endepunkt for å slette saker. Sakene blir derfor liggende i dev og kommer med i statistikken i BigQuery.

## Rate limits

Grensene står på under testen.

- **Ingress**: `limit-rps: "20"` per klient-IP. Når grensen er nådd, svarer ingress-nginx med 503, som telles i `avvist_rate_limit_ingress`. 100 brukere med 3–10 sekunders tenketid gir omtrent 15–30 req/s fra én maskin, mens ekte brukere har hver sin IP. Hvis vi ser 503 i `last` eller `stress`, kjører vi k6 fra flere maskiner eller ber om en midlertidig høyere grense i dev.
- **Søk**: `SokRateLimitFilter` tillater 30 kall i burst og 120 per time per Nav-ident. Svar med 429 telles i `avvist_rate_limit_app`. På sakdetaljsida regnes ikke 429 som feil, fordi søket der skyldes at flere VU-er deler én ident.

## Overvåking under kjøring

`scripts/lasttest.sh` starter k6 sitt web-dashboard på <http://127.0.0.1:5665>. Der ser du responstid, antall kall og feil fra testens side mens den går.

Følg med i Grafana for å se hva som skjer i backend:

- `http_server_requests_seconds` per URI: p95, p99 og feilrate
- `hikaricp_connections_active`, `_pending` og `_timeout`: om tilkoblingspoolen tar slutt
- `http_client_requests_seconds` per ekstern tjeneste
- JVM-heap, GC-pauser, CPU-throttling og minne i poden
- Cloud SQL: CPU, antall tilkoblinger og Query Insights. `db-custom-1-3840` tillater 100 tilkoblinger, og 4 pods med standard Hikari-pool bruker opptil 40.
- Tempo for de tregeste kallene og Loki for feil

Hvis `K6_PROMETHEUS_RW_SERVER_URL` er satt, sender `scripts/lasttest.sh` k6-metrikkene til Prometheus. Hver kjøring merkes med `testid`.

## Resultater

`scripts/lasttest.sh` lagrer tre filer per kjøring i `loadtest/resultater/` (git-ignorert):

| Fil | Innhold | For hvem |
|---|---|---|
| `<tid>-<scenario>-<profil>.md` | Konklusjon i klartekst, krav med ✅/❌, responstid per kall og en ordliste | Alle. Kan limes inn i en PR, i Slack eller i holmes-brain |
| `<tid>-<scenario>-<profil>.html` | Grafer over responstid, kall per sekund, feil og antall brukere gjennom kjøringen | Utviklere. Åpnes i nettleseren |
| `<tid>-<scenario>-<profil>.json` | Rådata fra k6 | Sammenligning mellom kjøringer |

k6 lager bare grafer når kjøringen varer lenge nok, så smoke får ingen HTML-fil. Rapporten lages av `lib/rapport.js`. Den henter terminaloppsummeringen fra `jslib.k6.io`, så maskinen må ha internettilgang.

Responstid per kall krever at kallnavnet står i `KALLNAVN` i `lib/klient.js`. Testen advarer i terminalen om navn som mangler.

Skriv funn og tiltak i holmes-brain. Typiske tiltak er større Cloud SQL-tier, større Hikari-pool, høyere CPU-request, flere replikaer, nye indekser, færre N+1-spørringer og caching av NOM og kodeverk.

## Miljøvariabler

| Variabel | Standard | Brukes til |
|---|---|---|
| `BASE_URL` | `https://watson-admin-api.intern.dev.nav.no` | Backend-adressen. Testen stopper hvis adressen ikke er HTTPS mot en host som slutter på `.dev.nav.no` |
| `TILLAT_BASE_URL` | (tom) | Sett til `true` for å kjøre mot en godkjent lokal stub |
| `TESTPERSONER` | (tom) | Kommaseparerte fødselsnumre for syntetiske testpersoner |
| `ENHET` | `lasttest` | Enhet for nye saker og filtre |
| `SOK_IDENT` | (tom) | Identen til `sok-ratelimit` |
| `TENKETID_MIN` / `TENKETID_MAKS` | `3` / `10` | Pause mellom sidevisninger, i sekunder |
| `K6_PROMETHEUS_RW_SERVER_URL` | (tom) | Sender metrikker til Prometheus |
| `MIN_GYLDIG` | `30` | `lasttest-tokens.sh` ber om nytt token når det gjenstår færre minutter enn dette |
| `WATSON_ADMIN_API_DIR` | `repos/watson-admin-api` | Klonen `lasttest-tokens.sh` leser saksbehandlerne fra |
