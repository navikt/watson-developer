# Migreringsveileder (SAK-67): import av kandidater

Importen leser uttrekk fra Access fra en privat GCS-bucket og fyller tabellen `migreringskandidat` i
`watson-admin-api`. Den kjører inne i selve appen (`ImportOppstart`) rett etter oppstart, når
`MIGRERING_IMPORT_AKTIV=true`. Det er ingen separat Naisjob og ingen egen databasebruker. En Naisjob kan ikke
dele Cloud SQL-instansen med appen (Nais nekter å overta `SQLInstance`-ressursen).

Aha: <https://nav1.aha.io/features/SAK-67>

## Hvordan den virker

1. Importen finner nyeste fil per kategori i bucketen. Filnavnet avgjør kategorien (se under).
2. Hver rad valideres. Utfallet er importert, `mangler_ident`, `ugyldig` eller utelatt.
3. Avviksfiler skrives til bucketen under avviksprefikset (`avvik/` som standard, `migrering/avvik/` i dev).
4. Alt lagres i én databasetransaksjon. Feiler noe, rulles alt tilbake.
5. Importen logger bare tellere, aldri radinnhold, og lagrer tellerne i `migrering_import_batch`.

Sluttsummen skal gå opp: `rader i filen = importert + mangler_ident + ugyldig + utelatt`. Forventet totalt er
2406 (586 + 612 + 434 + 637 + 77 + 60). Avvik fra forventet antall gir en advarsel i loggen, ikke feil.

### Filer

| Filnavn begynner med | Kategori | Kilde | Datokolonne | PID-kolonne |
| --- | --- | --- | --- | --- |
| `M_tipsrestanser` | `TIPS_RESTANSE` | `UTREDNING` | `TIPSINNDATO` | `PID` |
| `M_Tips_venter_resultat` | `TIPS_VENTER_RESULTAT` | `UTREDNING` | `TIPSINNDATO` | `PID` |
| `M_SV_RESTANSER` | `SV_RESTANSE` | `SV` | `SVMOTTATT` | `PID` |
| `M_SV_VENTER_POL_DOM` | `SV_VENTER_RESULTAT` | `SV` | `SVDATO` | `PID` |
| `M_register_dagpenger` | `REGISTER_DAGPENGER` | `NKA_DAGPENGER` | `PABEGYNTDATO` | `ID` |
| `M_register_AAP` | `REGISTER_AAP` | `NKA_AAP` | `PABEGYNTDATO` | `ID` |

Filene har `;` som skilletegn og en headerlinje. Kolonnene finnes via navn, så rekkefølgen er likegyldig. Alle
filer må ha kolonnene `FNR`, `ENHET`, datokolonnen og PID-kolonnen over, pluss minst én av `NAVIDENT` og `Ident`
(NAV-ident for ansvarlig saksbehandler). SV- og tipsfilene har `NAVIDENT`; dagpenger og AAP har `Ident`.
Datoformat er `d.M.yyyy HH.mm.ss`. `PROSJEKTIDENT` er valgfri og brukes bare til ansvarlig (se under). Andre kolonner, blant annet `PAABEGYNT`, ignoreres. Mangler en filen både `NAVIDENT` og `Ident`, stopper importen i stedet for å flagge alle rader.

### Utfall per rad

| Utfall | Når | Hva skjer |
| --- | --- | --- |
| Importert | PID, fnr og ident er gyldige | Rad settes inn med `migrering_status = IKKE_PABEGYNT` |
| `mangler_ident` | Ingen ident i filen, ingen treff i prosjektlisten og `MIGRERING_IMPORT_STANDARDIDENT` er ikke satt (bare dry-run) | Raden telles som `mangler_ident`. Det skrives ingen avviksfil, siden dry-run ikke skriver til bucketen |
| `ugyldig` | Ugyldig PID, fnr, dato eller ident, feil antall felt, eller duplikat | Rad skrives til `<avviksprefiks>ugyldig/<batch>/<kategori>.csv` med kolonnen `AARSAK` |
| Utelatt | `(kilde, pid)` finnes allerede og er under arbeid | Røres ikke |

### Ansvarlig for en rad

Rekkefølgen er:

1. `NAVIDENT`
2. `Ident`
3. ansvarlig for `ENHET` i `MIGRERING_IMPORT_ENHETMAPPING`
4. ansvarlig for `PROSJEKTIDENT` i `MIGRERING_IMPORT_PROSJEKTANSVARLIGE`
5. `MIGRERING_IMPORT_STANDARDIDENT`
6. ellers `mangler_ident` (bare dry-run)

Variablene ligger i Nais-configen `watson-migrering-import` (`envFrom`). `MIGRERING_IMPORT_STANDARDIDENT` er påkrevd
ved ekte kjøring. `MIGRERING_IMPORT_ENHETMAPPING` er valgfri og har formen `su685d=D101803,he965h=B101057`. `MIGRERING_IMPORT_PROSJEKTANSVARLIGE` er valgfri og har formen `vest=Z190190,ost=Z190191`. Nøklene
sammenlignes med `ENHET` og `PROSJEKTIDENT` uten hensyn til store og små bokstaver. Ugyldig format, ugyldig ident eller samme prosjekt
to ganger stopper importen. Feilmeldingen nevner elementnummer, aldri verdiene. Config leses ved oppstart, så poden må
restartes etter endring.

Sett verdien i [Nais Console](https://console.nav.cloud.nais.io/team/holmes/configs) per miljø (dev og prod). Identer
normaliseres til store bokstaver. Både gamle (tre bokstaver og fire siffer) og nye formater godtas.
Avviksfilene har fnr. De ligger bare i den private bucketen og skal ikke kopieres ut. Teamet som eier
masterdata får tilgang til avviksmappen, ikke til hele bucketen.

### Gjentatte kjøringer

En ny kjøring sletter bare rader som fortsatt er `IKKE_PABEGYNT` og uten sak, og setter inn rader på nytt. Det
gjelder rader i kategoriene som lastes, og rader med samme nøkkel (kilde og PID) som en rad i filene, også hvis raden
lå i en annen kategori sist. Dermed ender en rad som har flyttet kategori i riktig kategori, også ved delimport.
Rader som saksbehandlere har tatt i bruk (`UNDER_MIGRERING` eller `FULLSTENDIG`) slettes
aldri. En databasetrigger (`V17`) hindrer det også hvis koden skulle ha en feil. Kjør importen utenfor
arbeidstid: en saksbehandler som oppretter sak midt i en kjøring kan få en feilmelding.

### Status når saken avsluttes

En kandidat går fra `IKKE_PABEGYNT` til `UNDER_MIGRERING` når saksbehandleren knytter den til en sak, og til `FULLSTENDIG`
når saksbehandleren trykker «ferdig». Avsluttes saken mens kandidaten er `UNDER_MIGRERING`, settes kandidaten automatisk til
`FULLSTENDIG` i samme transaksjon. Den som avslutter saken står som fullført av. Det gir en `MIGRERING_FULLFORT`-hendelse
og en auditlogg. Andre statuser og saker uten kandidat røres ikke. Gamle rader som står som «Under flytting» med en avsluttet sak
ryddes ikke. Risiko: avsluttes saken før filene er flyttet, vises kandidaten likevel som ferdig flyttet.

## Slik styres den

Importen er **av** som standard, også ved vanlige deploys. Workflowen «Deploy to dev» har to valg ved
«Run workflow»:

| Valg | Standard | Betydning |
| --- | --- | --- |
| Kjør import av migreringskandidater | av | Appen starter importen når den er oppe |
| Importen kjører som dry-run | på | Leser og avstemmer, skriver ikke til database eller bucket |

Workflowen sender disse som `MIGRERING_IMPORT_AKTIV`, `MIGRERING_IMPORT_DRYRUN` og `MIGRERING_IMPORT_KJORINGID`
(`github.run_id`). Samme kjørings-id gir samme batch, så en restart av poden kjører ikke en ekte import på
nytt. En batch som endte som `FEILET` kan kjøres på nytt med samme kjørings-id (for eksempel «Re-run jobs» etter en
forbigående feil). En fullført batch hoppes over. En ny «Run workflow» gir ny kjørings-id og dermed en ny kjøring. Ved push til `main` er importen alltid av.

Én kjøring om gangen: en advisory lock i Postgres hindrer at to pods importerer samtidig.

## Dev

Testbrukerne i dev er `Z993376` og `Z994531` (ansvarlig i testfilene). Importen viser bare kandidater der innlogget bruker er
ansvarlig, så logg inn som en av dem for å se listen.

1. **Lag testfiler.** Fnr må komme fra Dolly. Tilfeldige fnr finnes ikke i PDL og tilgangsmaskinen i dev, så
   alle rader ville blitt filtrert bort. Legg Dolly-fnr i en fil, ett per linje, utenfor Git:
   ```bash
   cd repos/watson-admin-api
   rm -rf build/import-testfiler
   ./gradlew genererTestfiler -PdollyFil=<fil med Dolly-fnr> -Pident=Z993376,Z994531 -Pantall=40
   ```
   Filene havner i `build/import-testfiler`. `-Pident` er en kommaseparert liste med NAV-identer som får radene
   (rundgang). Uten `-Pident` brukes oppdiktede identer, og ingen kandidater vises for noen. `-Pantall=40` gir 240 rader
   totalt, ca. 110 per bruker (flere sider å bla i). Standard er 2406 rader, og da får én bruker alle radene: listen
   kaller tilgangsmaskinen per rad og blir veldig treg. Generatoren lager noen rader uten ident og med ugyldig fnr,
   så avviksfilene kan testes. Slett `build/import-testfiler` først, ellers får du to filer per kategori.
2. **Deploy appen** fra GitHub: Actions, «Deploy to dev», «Run workflow». Velg branchen. Importen står av.
   I dev brukes den eksisterende bucketen `watson-sak-filer-dev-gcp`, som appen allerede har tilgang til. Importfilene
   ligger i mappen `migrering/` og avviksfilene i `migrering/avvik/`, adskilt fra sakfilene (`<sakId>/<filId>`).
   Retention-jobben i appen sletter bare filer den har registrert i databasen, så den rører ikke `migrering/`.
   Filene har fnr: sett en livssyklusregel på mappen `migrering/` (slett etter 90 dager) i Google Cloud-konsollen.
3. **Last opp filene** til bucketen (`gcloud auth login` først hvis du ikke er innlogget). Filnavnene har dagens dato,
   så nye filer med samme dato overskriver de gamle:
   ```bash
   gcloud storage cp build/import-testfiler/*.txt \
     gs://watson-sak-filer-dev-gcp/migrering/ --project holmes-dev-575c
   gcloud storage ls -l gs://watson-sak-filer-dev-gcp/migrering/ --project holmes-dev-575c   # kontroller størrelse og tid
   ```
   Med `-Pantall=40` er hver fil 3–4 KB. Er de 40–60 KB, er det de gamle filene.
4. **Dry-run:** kjør «Deploy to dev» på nytt og huk av «Kjør import», med «dry-run» avhuket. Les loggen til appen
   (se «Hvor finner du loggen»). Den skal vise `dryRun=true` og at tallene går opp (240 med `-Pantall=40`, 2406 uten).
5. **Ekte kjøring:** kjør «Deploy to dev» på nytt, huk av «Kjør import» og **fjern** avhukingen på dry-run. Bruk
   «Run workflow», ikke «Re-run jobs»: «Re-run» gjenbruker kjørings-id og blir hoppet over (`hoppetOver=true`) hvis forrige kjøring ble fullført.
6. **Kontroller** at importen kjørte (loggen) og at kandidatene finnes (se «Kontroller resultatet»).

Avkrysningsboksene i «Run workflow»: *kryss av* «Kjør import» for å starte importen, og *kryss av* «dry-run» for å bare
lese og avstemme. For ekte import skal «Kjør import» være avkrysset og «dry-run» ikke avkrysset.

### Hvor finner du loggen

Importen og kandidatlisten logger til `watson-admin-api`. Åpne Nais-konsollen, team **holmes**, miljø **dev-gcp**,
applikasjonen **watson-admin-api**, og fanen for logger. Søk på `Importen` eller `Migreringsliste`. Alternativt i
Grafana/Loki: `{service_name="watson-admin-api"} |= "Importen"`. Fra terminalen:
```bash
kubectl -n holmes logs deploy/watson-admin-api --since=2h | grep -E 'Importen|Migreringsliste|Sum:|Fil '
```
Linjer å se etter etter en ekte import:
```
Importen starter (dryRun=false, …)
Fil TIPS_RESTANSE (M_tipsrestanser_<dato>.txt): totalt=40, importert=…, slettet=…
Sum: totalt=240, importert=…, mangler_ident=…, ugyldig=…, utelatt=0
Importen er ferdig (batch …, hoppetOver=false)
```
`slettet=` større enn 0 betyr at gamle `IKKE_PABEGYNT`-rader er byttet ut.

### Kontroller resultatet

- **API (Swagger eller Postman):** `https://watson-admin-api.intern.dev.nav.no/swagger-ui/index.html`. Trykk
  «Authorize» og lim inn et rått OBO-token (uten `Bearer`) for testbrukeren. Token hentes på
  `https://azure-token-generator.intern.dev.nav.no/api/obo?aud=dev-gcp:holmes:watson-admin-api`. Kjør
  `GET /api/v1/migrering/kandidater` med `visning=MINE`. Bruk `size=5` for rask test. Svaret har `totalItems`,
  `utilgjengelig` og `antallPerKategori`. Samme kall finnes i Postman-collectionen «Watson Admin API (dev)».
- **Frontend:** migreringen er åpen i dev (`migreringErÅpen`). Logg inn som testbrukeren og åpne «Migrering». Listen har
  paginering (20 per side, `?side=2`). Ledere ser også «Ansatte» (`?ansatteSide=2`).
- **Database** (bare lesing, ikke velg `person_ident`). Første gang trengs tilgang til skjemaet:
  ```bash
  nais postgres prepare watson-admin-api --team holmes --environment dev-gcp --reason "SAK-67 import"
  nais postgres psql    watson-admin-api --team holmes --environment dev-gcp --reason "SAK-67 import"
  ```
  `psql` må være installert (`brew install libpq`). Tabellene ligger i `public`:
  ```sql
  SELECT id, startet, ferdig, status, tellinger FROM public.migrering_import_batch ORDER BY startet DESC;
  SELECT kategori, migrering_status, count(*) FROM public.migreringskandidat GROUP BY 1, 2 ORDER BY 1;
  SELECT ansvarlig_nav_ident, count(*) FROM public.migreringskandidat GROUP BY 1 ORDER BY 2 DESC;
  ```
  Lim inn én setning om gangen, uten Markdown-gjerder, og skriv `\r` hvis prompten er `->`.

### Tom liste i frontend

Backend logger én linje hver gang listen hentes:
```
Migreringsliste MINE for Z993376: radeIKilde=110, medPersoninnsyn=110, utilgjengelig=false
```

| Logglinje | Betydning | Tiltak |
| --- | --- | --- |
| `radeIKilde=0` | Ingen rader med denne identen i databasen | Importen er ikke kjørt med filer for denne identen. Lag og last opp filer med riktig `-Pident`, og kjør importen |
| `radeIKilde>0`, `medPersoninnsyn=0` | Tilgangskontrollen avviser alle | Kontroller tilgangsmaskinens innsyn i Dolly-personene (fnr finnes i PDL og tilgangsmaskinen i dev). Basic og Utvidet gjelder `watson-sok`, ikke Watson Sak |
| `utilgjengelig=true` | NOM eller tilgangsmaskinen svarte ikke | Gul melding i UI. Prøv igjen senere |
| Ingen linje | Kallet nådde ikke backend | Sjekk frontend (404 betyr at miljøet er stengt) |

## Prod

- **Variabler:** `IMPORT_BUCKET_NAME=access_oracle_migration`, `OPPRETT_IMPORT_BUCKET=false` (ingen ny bucket),
  `MIGRERING_IMPORT_PREFIKS=""` (filene ligger i roten av bucketen), `MIGRERING_IMPORT_AVVIKPREFIKS="avvik/"` og
  startverdiene `MIGRERING_IMPORT_AKTIV=false`, `MIGRERING_IMPORT_DRYRUN=true` og `MIGRERING_IMPORT_KJORINGID=""`,
  på samme måte som i `.nais/dev.json`. Prod-deployen må sende de tre `MIGRERING_IMPORT_*`-variablene på samme måte
  som workflowen gjør i dev.
- **IAM på bucketen** (du må ha administratortilgang på `access_oracle_migration`). Gi **appens** service
  account tilgang. Den finnes allerede, siden appen kjører:
  ```bash
  kubectl --context prod-gcp -n holmes get serviceaccount watson-admin-api \
    -o jsonpath='{.metadata.annotations.iam\.gke\.io/gcp-service-account}'
  ```
  Kontroller at adressen tilhører prod-prosjektet (`holmes-prod-60aa`) før du fortsetter. Står du i dev-context, får
  dev-appen lesetilgang til prod-bucketen med fnr.
  ```bash
  for ROLLE in roles/storage.objectViewer roles/storage.objectCreator; do
    gcloud storage buckets add-iam-policy-binding gs://access_oracle_migration \
      --project holmes-prod-60aa --member="serviceAccount:<adressen>" --role="$ROLLE"
  done
  ```
  `objectCreator` kan ikke overskrive objekter. Avviksfilene har batch-id i navnet. Appen kan altså lese kildefilene
  og lage avviksfiler, men aldri overskrive eller slette. Livssyklusregel på bucketen (for eksempel slett etter
  90 dager) må settes av eieren.
- **Kjør først som dry-run.** Kontroller at totalt er 2406 og at fordelingen stemmer. Kjør deretter ekte.
- Frontend er åpen i `local-backend` og `dev`, men stengt (404) i `prod` og `demo` (`migreringErÅpen` i
  `watson-sak-frontend`). Kandidatene blir ikke synlige for saksbehandlerne i prod før den åpnes.

## Feil og oppfølging

- Importen stopper aldri appen. Feil logges (`Importen feilet: …`). Meldinger i loggen inneholder aldri radverdier.
  Databasefeil logges bare som klassenavn og SQLState, siden PostgreSQL kan skrive radverdier (inkludert fnr)
  i meldingen.
- Ved feil rulles databasen tilbake, og kjøringen registreres som `FEILET` i `migrering_import_batch`.
- Sett opp en alert på loggmeldingen «Importen feilet» i Nais-konsollen (Loki).
- Kontroller en kjøring: `SELECT id, startet, ferdig, status, tellinger FROM migrering_import_batch ORDER BY startet DESC;`

## Lokal kjøring uten Spring

Den frittstående inngangen `ImportJobbMain` kjører samme logikk fra en katalog, for lokal testing:
```bash
DRY_RUN=true IMPORT_KATALOG=build/import-testfiler \
  java -Dloader.main=no.nav.watson.admin.migrering.importjobb.ImportJobbMainKt \
  -cp build/libs/app.jar org.springframework.boot.loader.launch.PropertiesLauncher
```

## Vest-migrering (SAK-67-2)

To Access-filer fra Vest (`M_SV_RESTANSER_VEST2.txt` og `M_SV_VENTER_POL_DOM_VEST2.txt`) oppretter ferdige
kontrollsaker, ikke kandidater. Kjøringen følger samme mønster som importen: filene ligger i importbucketen, og en
flagg-styrt kjøring i `watson-admin-api` (`VestOppstart`) leser dem. Det finnes ikke lenger noe HTTP-endepunkt, så ingen
fnr sendes over nettet eller ligger på en laptop. Filnavn med `_vest2` plukkes ikke opp av den ordinære importen.

| Fil | Steg | Ansvarlig | Ytelse fra | Dato fra |
| --- | --- | --- | --- | --- |
| `SV_RESTANSER` | Strafferettslig vurdering | `NAVIDENT`, ellers ufordelt | `Ytelse` | `SVMOTTAT` |
| `SV_VENTER_POL_DOM` | Politi (anmeldt) | `NAVIDENT`, ellers `MIGRERING_VEST_POLITI_IDENT` | `SAK` | `SVMOTTATT` |

Felles: kategori Arbeid, misbrukstype Hvit inntekt, kilde Access migrering, enhet Vest, `legacyKilde=SV` og `legacyPid=PID`.
Politisaker får anmeldt beløp fra `STRBELOP` (komma som desimaltegn, tom blir 0), politidistrikt fra `POLITIDISTRIKT2`
(`?` først blir `Ø`, tom gir avvik) og saksreferanse fra `POLSAKNR`.

### Ansvarlig for saker uten NAVIDENT

Restanser (steget Strafferettslig vurdering) uten NAVIDENT blir ufordelte, for det er tillatt i det steget. Politisaker
kan ikke være ufordelte, fordi Watson Sak ikke tillater det i Politi-steget. Raden får derfor `MIGRERING_VEST_POLITI_IDENT`, og
uten den blir den et avvik (`MANGLER_IDENT`). Identen er `E176098` (Tord) i prod og testbrukeren hans, `Z993368`, i dev. Det er
personen som skal ha sakene i prod (Aha SAK-67-2).

Variabelen settes i Nais-configen `watson-migrering-import` i Nais Console, per miljø, ikke i repoet. Den configen kommer allerede inn
som `envFrom`, så `nais.yaml` trenger ingen endring. Poden må restartes etter at verdien er satt. Identen må finnes i NOM i miljøet,
ellers gir radene `UKJENT_SAKSBEHANDLER`.

### Slik kjører du den

1. **Last opp filene** til importbucketen (roten, samme bucket og prefiks som importen). Dev: `watson-migrering-import-dev-gcp`,
   prod: `watson-migrering-import-prod-gcp`. Fnr i dev-filene må være Dolly-fnr.
2. **Dry-run.** Kjør «Deploy to dev» (eller «Deploy release til prod») med «Kjør Vest-migrering» avhuket og «dry-run» avhuket.
   Loggen viser filnavn, oppdateringstid, størrelse og **SHA-256** for hver fil, og tellerne (`opprettet`, `alleredeOpprettet`,
   `avvik`, `feil`, `tomtBelop`, `skjermet`, `gjenstaar`). Dry-run oppretter ingenting og skriver ingenting til bucketen.
3. **Ekte kjøring.** Kjør workflowen på nytt med «dry-run» avhuket **av**, og fyll inn `vest_restanser_fil` og `vest_restanser_sha256`
   (og tilsvarende for politi) med verdiene fra dry-run-loggen. Jobben kjører bare de filene du har oppgitt, og avbryter hele
   kjøringen hvis en SHA-256 ikke stemmer. I prod venter en ekte kjøring på godkjenning i environmentet `prod-migreringsimport`.
4. **Kontroller** loggen (`Vest-migreringen avsluttes …`) og avviksfilene. Send ikke filer med fnr andre steder.

### Sikkerhet og oppførsel

- **Persondata:** Jobben har ingen innlogget bruker. Den henter navn, adressebeskyttelse og historiske identer fra
  `nav-persondata-api` med M2M-token (`persondataSystemClient`, samme klient som `KontrollobjektOppdateringScheduler`).
  Skjerming tolkes fail closed: manglende `adressebeskyttelse` regnes som skjermet, og blankt navn gir `PERSON_IKKE_FUNNET`.
  Antall opprettede saker med skjerming står som `skjermet` i loggen.
- **Én kjøring om gangen:** en advisory lock i Postgres (egen nøkkel) hindrer at flere pods kjører samtidig. Prod og dev har to replikaer.
- **Pinnet fil:** ekte kjøring bruker filnavn og SHA-256 du har oppgitt, aldri «nyeste fil». Dry-run velger nyeste fil per type.
- **Radtak:** `MIGRERING_VEST_MAKSRADER` (standard 1000) stopper en fil som har flere rader enn forventet.
- **Revisjon:** loggen har kjørings-id, hvem som startet (`github.actor`), filnavn, SHA-256, dry-run og tellere. Aldri fnr eller navn.
  Hvem som godkjente prod-kjøringen står i GitHub Actions.
- **Avvik:** rader med feil i filen skrives ved ekte kjøring til `avvik/vest/<kjørings-id>/<FIL>.csv` i bucketen (har fnr, ligger bare i den
  private bucketen). Rader som feiler under opprettelse (`feil`) prøves på nytt neste gang. Samme fil kan kjøres flere ganger:
  rader med kilde `SV` og samme PID hoppes over.
- **Retensjon:** importbucketen i prod slettes etter 90 dager (`lifecycleCondition` i `nais.yaml`).
- **Transaksjoner:** hver sak opprettes i egen transaksjon. En feil på én rad stopper ikke de andre.

### Variabler

Alle er av eller tomme som standard, og settes av workflowen. Bucket og prefiks deles med importen (`MIGRERING_IMPORT_BUCKET`, `_PREFIKS`, `_AVVIKPREFIKS`).

| Variabel | Betydning |
| --- | --- |
| `MIGRERING_VEST_AKTIV` | `true` starter kjøringen etter oppstart |
| `MIGRERING_VEST_DRYRUN` | `false` gir ekte kjøring. Alt annet gir dry-run |
| `MIGRERING_VEST_KJORINGID` | `github.run_id`. Påkrevd ved ekte kjøring |
| `MIGRERING_VEST_STARTETAV` | `github.actor`, bare til revisjonslogg |
| `MIGRERING_VEST_RESTANSER_FIL`, `MIGRERING_VEST_POLITI_FIL` | Filnavn som skal kjøres (påkrevd ved ekte kjøring) |
| `MIGRERING_VEST_RESTANSER_SHA256`, `MIGRERING_VEST_POLITI_SHA256` | Forventet SHA-256 (påkrevd ved ekte kjøring) |
| `MIGRERING_VEST_MAKSRADER` | Maks rader per fil, standard 1000 |
| `MIGRERING_VEST_POLITI_IDENT` | Ansvarlig for politisaker uten NAVIDENT (i Nais-configen `watson-migrering-import`) |

Lokal test: enhetstestene (`VestMigreringServiceTest`, `VestOppstartTest`) dekker logikken. Ende-til-ende test skjer i dev.

## Viktig om migrasjonene

V13–V17 er anvendt i dev (og senere prod). **Ikke endre dem**, heller ikke kommentarer: Flyway sjekker innholdet, og en
endret sjekksum stopper appen ved oppstart (`Migration checksum mismatch`). Nye endringer legges i en ny versjon.
Deployer noen eldre kode til dev mens V13–V17 er anvendt, får de `Detected applied migration not resolved locally`.

## Fjerning

Tabellen `migrering_import_batch` og kolonnen `migreringskandidat.import_batch_id` slettes sammen med
`migreringskandidat`. Se `migrering-fjerning.md`. Slett også pakken `migrering/importjobb`, variablene
`MIGRERING_IMPORT_*` i `nais.yaml` og `dev.json`, og valgene i `deploy-to-dev.yaml`.
