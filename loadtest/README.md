# Lasttest av Watson Sak

k6-skript som sender kall mot `watson-admin-api` i dev-gcp og simulerer saksbehandlere og ledere. Vi bruker dem til å finne ut hvor appen, databasen og avhengighetene trenger justering før prod.

Skriptene er JavaScript. Det er et bevisst unntak fra regelen om at watson-developer ikke skal ha applikasjonskode: lasttesten gjelder hele porteføljen og har ikke noe naturlig hjem i ett app-repo.

## Kom i gang

Gjør dette én gang per maskin. Kjør alle kommandoene i en vanlig terminal fra rotmappa i watson-developer, ikke i cplt-sandboxen.

1. Installer k6 og jq: `brew install k6 jq`.
2. Klon watson-admin-api til `repos/` med `./scripts/clone-repos.sh`. Tokenskriptet leser testbrukerne derfra.
3. Skaff passordene til testbrukerne og fødselsnumrene til testpersonene (se [Forutsetninger](#forutsetninger)).

### Testbrukere

Saksbehandlerne er testbrukerne med `enhetId: lasttest` i `nom.ekstra-saksbehandlere` i `application-dev.yml` i watson-admin-api. Tokenskriptet leser fila på `origin/main`, siden det er den som er deployet. Nye saksbehandlere legger du altså inn i watson-admin-api, ikke her.

Ledere står i `loadtest/ledere`, én navIdent per linje. Fila er tom nå, og da hopper testen over lederflyten. Begge stedene skal bare ha fiktive testidenter.

### Tokens

```bash
./scripts/lasttest-tokens.sh
```

Skriptet ber bare om token for identer som mangler et token, eller har et som utløper innen 30 minutter. For hver ident:

1. Logg inn som identen i et privat nettleservindu, og åpne lenken skriptet viser.
2. Kopier tokenet.
3. Trykk Enter i terminalen for å bruke utklippstavla, eller lim inn tokenet. Trykk `h` for å hoppe over identen. Du trenger ikke Enter.

Skriptet avviser et token som tilhører en annen ident. Tokenet vises ikke på skjermen. Det lagres i `loadtest/.tokens/tokens.json`, som er git-ignorert og bare lesbar for deg. Når en ident forsvinner fra `application-dev.yml` eller `loadtest/ledere`, sletter skriptet tokenet.

- `--status` viser hvor lenge tokenene varer. De varer omtrent én time.
- `--alle` henter nye tokens for alle identene.
- `lasttest.sh` stopper før k6 starter hvis et token er utløpt eller ugyldig.

## Gjennomføring

### Rekkefølge

Kjør testene i denne rekkefølgen, og gå videre bare når forrige test er forstått:

1. `smoke` rett før hver kjøring: sjekker at tokens, tilganger og endepunkter virker
2. `watson-sak baseline`: normaltall å sammenligne med
3. `watson-sak last`: forventet bruk i prod
4. `watson-sak stress`: hvor systemet knekker
5. `watson-sak utholdenhet`: feil som først viser seg etter en stund

Kjør bare én test om gangen. Vent til grafene i Grafana er tilbake på normalnivå før neste kjøring.

### Før testdagen

| Gjøres | Gjelder |
|---|---|
| Sjekk at dev kjører med prodlikt oppsett (navikt/watson-admin-api#332) | alle |
| Sjekk at dev har saker testbrukerne kan se, helst i et realistisk antall | alle |
| Varsle teamene bak tilgangsmaskin, NOM og nav-persondata-api om tidspunktet | `last`, `stress`, `utholdenhet` |
| Hev grensen `limit-rps` i ingress for watson-admin-api i dev midlertidig, for eksempel til 300, og sett den tilbake etterpå | `last`, `stress`, `utholdenhet` |
| Åpne Grafana med metrikkene under [Overvåking under kjøring](#overvåking-under-kjøring) | alle |

Grensen i ingress er 20 kall i sekundet per IP. `baseline` holder seg under, men de tre største profilene går langt over. Uten hevet grense får vi mange 503-svar og måler ingress, ikke appen. Kjøring fra flere maskiner er ikke et alternativ: `lasttest.sh` deler ikke lasten, så hver maskin kjører hele profilen. Maskinene kan dessuten dele IP gjennom naisdevice.

### Slik kjører du en test

```bash
./scripts/lasttest-tokens.sh                                   # 1. tokens
TESTPERSONER=<fnr1>,<fnr2> ./scripts/lasttest.sh smoke          # 2. sjekk
TESTPERSONER=<fnr1>,<fnr2> ./scripts/lasttest.sh watson-sak last  # 3. testen
```

Hent tokens for alle testbrukerne før `watson-sak`. Lasten fordeles på brukerne, og med få brukere treffer de søkegrensen oftere.

Smoke skal bli grønn før du går videre. Uten `TESTPERSONER` leser smoke bare. Med `TESTPERSONER` oppretter den én sak. Den første gangen bør du åpne saken i Watson Sak i dev og sjekke at enheten er Lasttest.

Følg kjøringen på <http://127.0.0.1:5665> og i Grafana. Avbryt med Ctrl+C hvis appen ser ut til å påvirke andre i dev, for eksempel med restarter eller feil hos andre team.

### Profilene

Tallene under gjelder uten leder: 85 % av brukerne leser og 15 % skriver. Kall per sekund og antall saker er anslag. En leser sender omtrent 0,7 kall i sekundet og en skriver omtrent 0,6. Hver skriver oppretter rundt 2,4 saker i minuttet.

#### `baseline`

| Tid | Brukere | Kall per sekund |
|---|---|---|
| 0–1 min | 0 → 10 | 0 → 7 |
| 1–11 min | 10 | rundt 7 |
| 11–12 min | 10 → 0 | ned til 0 |

Gir normaltall for responstid per kall når systemet har lite å gjøre. Rundt 4 500 kall og 25 saker. Går fint fra én maskin uten hevet grense.

#### `last`

| Tid | Brukere | Kall per sekund |
|---|---|---|
| 0–5 min | 0 → 100 | 0 → 70 |
| 5–25 min | 100 | rundt 70 |
| 25–27 min | 100 → 0 | ned til 0 |

Simulerer en vanlig arbeidsdag med 100 saksbehandlere. Hver testbruker har rundt ti samtidige økter. Rundt 100 000 kall og 850 saker.

Testen er grønn når kravene under [Terskler](#terskler) holder hele perioden med 100 brukere. Sammenlign responstiden per kall med `baseline` for å se hvilke kall som tåler last dårligst.

#### `stress`

| Tid | Brukere | Kall per sekund |
|---|---|---|
| 0–5 min | 0 → 100 | 0 → 70 |
| 5–10 min | 100 → 200 | 70 → 140 |
| 10–15 min | 200 → 300 | 140 → 210 |
| 15–20 min | 300 | rundt 210 |
| 20–22 min | 300 → 0 | ned til 0 |

Presser systemet forbi forventet bruk. Rundt 170 000 kall og 1 500 saker. Tersklene brytes sannsynligvis, og k6 avslutter med feilkode. Det er forventet.

Se ikke på snittet for hele kjøringen. Finn tidspunktet der responstid eller feilrate begynner å stige, og les av hvor mange brukere som var aktive. Det er knekkpunktet. Se etter:

- hva som gir seg først: tilkoblingspoolen, CPU i databasen, CPU-throttling i podene eller kall til andre tjenester
- om HPA skalerer fra 2 til 4 pods, og hvor raskt
- om appen henter seg inn igjen når lasten går ned
- om en pod restarter

Med 30 økter per testbruker treffer personsøket søkegrensen oftere. 429 på søk regnes ikke som feil.

#### `utholdenhet`

| Tid | Brukere | Kall per sekund |
|---|---|---|
| 0–5 min | 0 → 100 | 0 → 70 |
| 5–50 min | 100 | rundt 70 |
| 50–52 min | 100 → 0 | ned til 0 |

Samme last som `last`, men i 45 minutter. Rundt 200 000 kall og 1 750 saker. Vi ser etter utviklingen over tid, ikke toppen. Er responstiden i minutt 45 høyere enn i minutt 10, har vi et problem. Se etter:

- heap etter GC som stiger jevnt, lengre GC-pauser eller restart fordi minnet tar slutt
- `hikaricp_connections_active` eller tilkoblinger i Cloud SQL som øker uten at lasten øker
- tråder som blir flere over tid
- saklister og søk som blir tregere etter hvert som tabellene vokser
- topper når de planlagte jobbene kjører, og at ShedLock bare lar én pod kjøre hver jobb

En test med grønne terskler, men med en graf som stiger jevnt, er også et funn.

52 minutter er nær levetiden til tokenene. Hent alle på nytt rett før med `./scripts/lasttest-tokens.sh --alle`. Uten `--alle` godtar skriptet tokens med 30 minutter igjen, og de går ut midt i testen.

### Etter kjøringen

1. Sett `limit-rps` tilbake til 20 hvis du hevet den.
2. Les rapporten i `loadtest/resultater/` (se [Resultater](#resultater)).
3. Skriv funn og tiltak i holmes-brain. Legg ved rapporten i markdown og skjermbilder fra Grafana.
4. Ved feil: bruk tidspunktet og URL-en fra advarslene i terminalen til å finne feilen i Loki.

## Forutsetninger

- **Prodlikt oppsett i dev**: navikt/watson-admin-api#332 må være deployet. Uten den måler vi `db-f1-micro` og én replika, ikke det prod skal kjøre på.
- **Testbrukere** i `trygdeetaten.no`, medlem av `0000-CA-kontroll-Watson`. Uten medlemskap i en av Watson-gruppene får de ikke token, fordi watson-admin-api har `allowAllUsers: false`. Utvidet tilgang trengs ikke, siden testpersonene ikke er skjermet. Bruk 10–20 testbrukere. Søkegrensen gjelder per ident, og med få identer treffer flere VU-er den samme kvoten. Lederflyten trenger en ident i en ledergruppe.
- **Enheten Lasttest**: Saksbehandlerne skal ikke finnes i NOM. De må stå i `nom.ekstra-saksbehandlere` i `application-dev.yml` i watson-admin-api med `enhetId: lasttest` (navikt/watson-admin-api#335). Uten dem stopper `lasttest-tokens.sh`. Da får sakene fra testen enheten Lasttest når de tildeles, og ingen ledervarsler går til ekte ledere. En saksbehandler som finnes i NOM, flytter saken til sin egen enhet. Lederen kan finnes i NOM, siden lederflyten bare leser.
- **Testpersoner** (syntetiske fra Dolly) som testbrukerne har tilgang til i tilgangsmaskin. De settes i `TESTPERSONER` og brukes når skriveflyten oppretter saker. Uten dem hopper testen over skriveflyten.
- **Saker i dev** som testbrukerne ser. `setup()` henter opptil 500 sak-ID-er fra saklista og avbryter hvis den ikke finner noen. Seed dev med en realistisk datamengde: lister og statistikk oppfører seg annerledes med 50 saker enn med 50 000.
- **Varsling**: Gi beskjed til teamene bak tilgangsmaskin, NOM og nav-persondata-api før `last`, `stress` og `utholdenhet`. Lesekallene går mot deres dev-tjenester.

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

Se [Profilene](#profilene) under Gjennomføring.

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

- **Ingress**: `limit-rps: "20"` per klient-IP. Når grensen er nådd, svarer ingress-nginx med 503, som telles i `avvist_rate_limit_ingress`. `baseline` gir rundt 7 req/s, mens `last` og `utholdenhet` gir rundt 70 og `stress` opptil 210. Hev grensen midlertidig i dev før de store profilene (se [Før testdagen](#før-testdagen)).
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
