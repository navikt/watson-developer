# Risikovurdering: Aha! MCP-server

**Dato:** 2026-06-19
**Status:** Krever avklaring før godkjenning med skrivetilgang
**Anbefalt beslutning:** Godkjenn eventuelt som Kategori 2 kun med lesetilgang. Skrivetilgang må behandles som Kategori 3 eller som eksplisitt, tidsavgrenset pilot.

## Konklusjon

Aha! MCP-server kan gi nytte for teamet ved å hente, spesifisere og oppdatere oppgaver direkte fra Copilot CLI. Risikoen er akseptabel for **read-only** bruk i teamets Aha!-workspace, gitt at den kjøres i `cplt` og at dataene begrenses til interne produktdata.

Den foreslåtte bruken er likevel **ikke en ren Kategori 2-godkjenning**, fordi dere ønsker skrivetilgang og Aha!-instansen inneholder personopplysninger om Nav-ansatte. Navs gjeldende MCP-policy beskriver Kategori 2 som lesetilgang til ikke-sensitive data. Skrivetilgang og personopplysninger trekker vurderingen mot Kategori 3, som foreløpig ikke er besluttet i rammeverket.

## Grunnleggende informasjon

| Felt | Verdi |
| ---- | ----- |
| Servernavn | Aha! software MCP server |
| Leverandør | Aha! Labs Inc. |
| Endpoint | `https://nav1.aha.io/api/v1/mcp` |
| Hosting | Aha!-driftet skytjeneste |
| Foreslått kategori | Kategori 2 |
| Vurdert kategori | Kategori 2 ved read-only, Kategori 3 ved skrivetilgang |
| Foreslått av | Kristofer Giltvedt Selbekk, seniorutvikler |
| ROS-eier / systemansvarlig | Espen Einn, produktleder |
| Brukere | Bare teamet |
| Kritikalitet | Middels |
| MCP-klient | GitHub Copilot CLI |
| Kjøremiljø | `cplt` sandbox med `nav1.aha.io` i CONNECT-proxy allowlist |
| Avtale | Enterprise-avtale med databehandleravtale er på plass |

## Dataklassifisering

| Data | Klassifisering | Begrunnelse |
| ---- | -------------- | ----------- |
| Roadmap, initiativer, strategi og oppgaver | Intern | Ikke offentlig produkt- og prioriteringsinformasjon |
| Navn, e-post og kommentarer fra Nav-ansatte | Fortrolig | Personopplysninger etter Navs dataklassifisering |
| Innbyggerdata, fnr, helsedata og ytelsesdata | Ikke tillatt | Skal ikke ligge i Aha! eller behandles via MCP-en |

Aha! sine vilkår forbyr lagring eller overføring av "protected health information" (PHI). Det må derfor være et eksplisitt bruksvilkår at Aha! ikke brukes til helsedata, innbyggerdata, skjermingsdata, fnr, D-nummer, ytelseshistorikk eller annen strengt fortrolig informasjon.

## Begrunnelse for behovet

Aha! er allerede teamets verktøy for produktplanlegging. MCP-serveren gjør at Copilot CLI kan hente relevant kontekst direkte fra Aha!, og ved skrivetilgang kan agenten oppdatere Aha! etter arbeid i kodebasen.

Aktuelle arbeidsflyter:

1. Finne riktig oppgave eller feature ut fra naturlig språk.
2. Oppsummere status, krav og strategi før utviklingsarbeid.
3. Spesifisere oppgaver med mer presise beskrivelser.
4. Endre status på oppgaver.
5. Måle oppgaver opp mot strategi og initiativer.

Eksisterende godkjente MCP-servere dekker ikke Aha!-spesifikk produktplanlegging.

## Teknisk vurdering

### Funksjonalitet

Aha! dokumenterer MCP-funksjonaliteten på kapabilitetsnivå, ikke som et komplett MCP tool-manifest.

| Operasjon | Tilgang | Kommentar |
| --------- | ------- | --------- |
| Søke etter records | Lese | Kan inkludere initiatives, features, requirements, ideas, epics og releases |
| Hente detaljer om records | Lese | Følger brukerens Aha!-tilganger |
| Lage rapportgrunnlag | Lese | Kan bruke Aha! AI for å snevre inn relevante felt |
| Opprette records | Skrive | Krever at write access er aktivert i Aha! AI controls |
| Oppdatere records | Skrive | Kan endre status, beskrivelser og feltverdier |
| Legge til kommentarer | Skrive | Kommentarer står på vegne av autentisert bruker |
| Slette records | Ikke støttet | Aha! oppgir at MCP-serveren ikke kan slette records |
| Tømme eller overskrive felt | Skrive | Viktig: selv uten sletting kan MCP-en fjerne viktig innhold ved å tømme felt |

### Autentisering og autorisasjon

Aha! MCP bruker Aha! sin API-autentisering. Aha! API støtter OAuth2 og API-nøkler. For Nav bør OAuth2 brukes, ikke API-nøkler, fordi API-nøkler er langlivede og knyttet til en bruker.

MCP-serveren handler med samme rettigheter som den autentiserte Aha!-brukeren. Hvis brukeren ikke kan redigere en record i Aha!-UI, skal brukeren heller ikke kunne redigere den via MCP.

### Administrativ styring

Aha! styrer MCP via **Settings -> Account -> AI controls**. Lese- og skrivetilgang er separate innstillinger. Det betyr at Nav kan velge read-only selv om MCP-serveren teknisk støtter skriving.

### Kommunikasjon og rate limits

| Tema | Vurdering |
| ---- | --------- |
| Protokoll | HTTPS til Aha!-endpoint |
| Transport | Remote MCP. Aha! dokumenterer ikke eksplisitt om transporten er Streamable HTTP eller SSE |
| Rate limit | 300 forespørsler per minutt eller 20 forespørsler per sekund, delt med Aha! REST API |
| cplt-nettverk | Tillat bare `nav1.aha.io` med mindre OAuth-flyten krever flere Aha!-domener |

### Logging og audit

Aha! oppgir at endringer via MCP vises under brukerens navn i audit logs og user activity, som om brukeren gjorde handlingen i Aha!-UI. Det er ikke dokumentert om auditloggen skiller mellom UI-handlinger og MCP-handlinger.

Dette bør avklares før skrivetilgang godkjennes.

## cplt-vurdering

`cplt` reduserer flere av de viktigste risikoene for lokale AI-agenter:

| Risiko | cplt-effekt |
| ------ | ----------- |
| Lekkasje av lokale hemmeligheter | Blokkerer tilgang til blant annet `.env`, `~/.ssh`, `~/.aws`, `~/.kube`, `~/.config/gcloud` og registry-credentials |
| Ukjent nettverkstrafikk | CONNECT-proxy kan begrense egress til godkjente domener |
| Destruktive GitHub/Git-handlinger | `gh guard` og `git guard` kan blokkere merge, release, delete og push |
| Lokal kodekjøring fra temp/cache | Blokkerer flere write-then-exec-mønstre |
| Agent-persistens | Begrenser skriving til agent-konfigurasjon utenfor prosjektet |

`cplt` løser ikke alt. Den hindrer ikke at en bruker med Aha!-rettigheter oppdaterer Aha!-records via MCP, og den hindrer ikke at Aha! selv sender data til sine AI-underleverandører når Aha! AI brukes internt.

## Leverandør, dataflyt og underleverandører

### Dataflyt

1. Utvikler kjører GitHub Copilot CLI i `cplt`.
2. Copilot CLI kobler til `https://nav1.aha.io/api/v1/mcp`.
3. Aha! autentiserer brukeren og gir tilgang til records brukeren allerede har tilgang til.
4. Data fra Aha! kan bli del av Copilot-konteksten.
5. Enkelte MCP-forespørsler kan bruke Aha! AI internt, for eksempel søk, analyse og rapportoppsett.
6. Aha! oppgir OpenAI LLC som underleverandør for språkmodelltjenester.

### Sikkerhet og compliance

| Tema | Funn |
| ---- | ---- |
| Primær sky | AWS, oppgitt som US-basert underleverandør |
| EU-dataresidens | Ikke dokumentert som tilgjengelig |
| Overføringsgrunnlag | Aha! oppgir sertifisering under EU-U.S. Data Privacy Framework |
| DPA | Oppgitt som på plass for Nav, men MCP- og AI-dekning bør verifiseres i avtalen |
| OpenAI | Oppgitt som underleverandør for språkmodelltjenester |
| HIPAA / helsedata | Aha! sine vilkår forbyr protected health information |
| Kjente CVE-er | Ingen relevante offentlige CVE-er funnet |
| Uavhengig analyse av Aha! MCP | Ikke funnet i offentlige kilder |

## Risikovurdering mot MCP-R01 til MCP-R10

| Risiko | Vurdering før tiltak | Vurdering etter tiltak | Tiltak |
| ------ | -------------------- | ---------------------- | ------ |
| MCP-R01: Ondsinnet MCP-server | Middels | Lav | Bruk kun offisiell Aha!-endpoint via Navs MCP Registry og cplt allowlist |
| MCP-R02: Prompt injection | Høy | Middels | Begrens data i Aha!, bruk read-only som standard, krev brukerbekreftelse for skriverelaterte handlinger |
| MCP-R03: Uautorisert kodekjøring | Middels | Lav | Kjør kun i `cplt`; ikke bruk `autoApprove` uten sandbox; bruk git/gh guard |
| MCP-R04: Lekkasje av hemmeligheter | Middels | Lav | cplt blokkerer lokale hemmeligheter; bruk OAuth, ikke API-nøkler; ikke legg secrets i Aha! |
| MCP-R05: Datalekkasje og manglende synlighet | Høy | Middels | Avklar DPA, OpenAI-bruk, auditlogg og dataresidens; begrens innhold i Aha! |
| MCP-R06: Overdrevne tillatelser | Høy | Middels ved skrivepilot, lav ved read-only | Slå av write access med mindre pilot er eksplisitt godkjent; begrens til team/workspace |
| MCP-R07: Usikker kommunikasjon | Lav | Lav | HTTPS; cplt CONNECT-proxy med domenebegrensning |
| MCP-R08: Oppdateringshåndtering | Middels | Middels | Remote server oppdateres av Aha!; Nav må ha kvartalsvis revisjon av godkjenningen |
| MCP-R09: MCP Sampling-misbruk | Ukjent | Middels | Aha! må bekrefte om serveren bruker Sampling. Ikke godkjenn før dette er avklart |
| MCP-R10: Agent-persistens og C2 | Middels | Lav til middels | cplt begrenser filsystem og egress; overvåk endringer i MCP- og agent-konfigurasjon |

### Samlet risiko

| Scenario | Risiko før tiltak | Risiko etter tiltak | Vurdering |
| -------- | ----------------- | ------------------- | --------- |
| Read-only, bare teamets workspace | Middels | Lav til middels | Kan vurderes som Kategori 2 |
| Lese og skrive, bare teamets workspace | Høy | Middels | Trekker mot Kategori 3 og krever eksplisitt beslutning |
| Lese og skrive for alle Nav med Aha!-tilgang | Høy | Høy | Ikke anbefalt nå |
| Tilgang til innbyggerdata, helsedata eller produksjonssystemer | Kritisk | Kritisk | Ikke tillatt |

## Anbefalt konfigurasjon

### Minimum for read-only-godkjenning

```json
{
  "servers": {
    "aha": {
      "url": "https://nav1.aha.io/api/v1/mcp",
      "type": "http"
    }
  }
}
```

Aha! AI controls må settes til **MCP read access: on** og **MCP write access: off**.

### Betingelser hvis skrivetilgang skal piloteres

Skrivetilgang bør bare godkjennes som en tidsavgrenset pilot med disse kravene:

1. Pilot begrenses til ett team og et avgrenset Aha!-workspace.
2. Aha! write access aktiveres bare for navngitte brukere.
3. GitHub Copilot CLI kjøres i `cplt` med `nav1.aha.io` i allowlist.
4. API-nøkler forbys. OAuth skal brukes.
5. `autoApprove` skal ikke brukes utenfor `cplt`.
6. Innbyggerdata, helsedata, fnr, D-nummer, skjermingsdata, secrets og produksjonscredentials er eksplisitt forbudt i Aha!.
7. Teamet må kunne rulle tilbake feilaktige Aha!-endringer gjennom Aha! audit/history eller manuell prosess.
8. Auditlogg gjennomgås etter pilotperioden.
9. Aha! må bekrefte at MCP-serveren ikke bruker MCP Sampling, eller beskrive nøyaktig hvordan Sampling er begrenset.
10. Avtalen/DPA må bekrefte at MCP og Aha! AI, inkludert OpenAI som underleverandør, er dekket.

## Avklaringer før endelig beslutning

| Spørsmål | Hvorfor det må avklares |
| -------- | ----------------------- |
| Bruker Aha! MCP-server MCP Sampling? | Sampling er en egen høy risiko i Navs risikoliste |
| Hva er komplett MCP tools-manifest? | Nav trenger å vite eksakt hvilke handlinger serveren kan utføre |
| Er transporten Streamable HTTP eller SSE? | Påvirker klient- og proxy-konfigurasjon |
| Hvor lenge lever OAuth-token for MCP? | Lang token-levetid øker konsekvens ved token-lekkasje |
| Skiller auditloggen MCP fra UI-handlinger? | Nødvendig for hendelseshåndtering og etterkontroll |
| Er OpenAI konfigurert uten trening på kundedata? | Viktig når Aha! AI behandler Nav-data |
| Dekker DPA MCP, Aha! AI og OpenAI-underleverandør? | Må være avklart for GDPR og leverandørstyring |
| Finnes SOC 2 Type II / ISO 27001 for Aha!-applikasjonen, ikke bare AWS? | Leverandørens sikkerhetsnivå må dokumenteres |
| Finnes EU-dataresidens eller bare EU-U.S. DPF? | Viktig for offentlig sektor og personopplysninger |

## Anbefalt beslutning

| Beslutning | Begrunnelse |
| ---------- | ----------- |
| Godkjenn read-only som Kategori 2 | Dataene er hovedsakelig interne produktdata, og cplt + OAuth + Aha!-RBAC gir tilstrekkelig kontroll |
| Ikke godkjenn skrivetilgang som ordinær Kategori 2 | Skrivetilgang og personopplysninger passer ikke med Kategori 2-definisjonen |
| Vurder skrivetilgang som Kategori 3-pilot | Bruksscenarioet er nyttig, men krever policyavklaring, sterkere logging og eksplisitt risikoeierskap |

## Implementeringsplan ved read-only

| Fase | Aktivitet | Ansvar |
| ---- | --------- | ------ |
| 1 | Bekreft DPA-dekning for MCP og Aha! AI | ROS-eier / innkjøp / juridisk |
| 2 | Bekreft at Aha! MCP ikke bruker Sampling | ROS-eier mot Aha! |
| 3 | Legg Aha! MCP inn i Navs MCP Registry som read-only | Plattform |
| 4 | Legg `nav1.aha.io` i cplt allowlist for teamet | Teamet / cplt-forvalter |
| 5 | Dokumenter tillatt og forbudt bruk | Teamet |
| 6 | Gjennomfør kort evaluering etter 4 uker | Teamet og ROS-eier |

## Referanser

- Aha! MCP-blogg: <https://www.aha.io/blog/introducing-the-aha-software-mcp-server>
- Aha! MCP support-artikkel: <https://support.aha.io/aha-roadmaps/integrations/mcp-server/remote-mcp-server-connection~7611343859688960297>
- Aha! API: <https://www.aha.io/api>
- Aha! OAuth2: <https://www.aha.io/api/oauth2>
- Aha! security: <https://www.aha.io/legal/security>
- Aha! privacy policy og underleverandører: <https://www.aha.io/legal/privacy_policy>
- Aha! terms of service: <https://www.aha.io/legal/terms_of_service>
- Nav cplt: <https://github.com/navikt/cplt>
- Nav intern MCP-risikovurdering: `navikt/copilot-intern/risikovurdering.md`
- Presedens: `navikt/copilot-intern/godkjenninger/figma-mcp-server.md`
- Presedens: `navikt/copilot-intern/godkjenninger/github-mcp-server-remote.md`
