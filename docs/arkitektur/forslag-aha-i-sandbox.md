# Forslag: lesetilgang til Aha! fra cplt-sandboxen

Status: forslag. Ingenting er endret i `setup-copilot.sh` eller i noens cplt-config.

## Problemet

Skillen `aha-watson` leser `AHA_API_KEY` og `AHA_DOMAIN` fra `~/kildekode/.env.personal`. cplt-sandboxen blokkerer
lesing av den filen (`Operation not permitted`), så agenten kan ikke hente features, releaser og beskrivelser. Det
gjelder oppgaver som «hva kan vi starte på i TH-R-7?». Utvikleren må da lime inn listen for hånd.

Blokkeringen er riktig for `.env.personal`: filen kan inneholde andre nøkler enn Aha. Vi bør ikke åpne den.

## Forslag

Gi sandboxen lesetilgang til én smal fil som bare har Aha-verdiene.

1. Utvikleren lager `~/.config/watson/aha.env` utenfor sandboxen, med modus `600`:
   ```bash
   AHA_DOMAIN=nav1
   AHA_API_KEY=<personlig nøkkel fra Aha: Settings, Personal, Developer, API keys>
   ```
2. `setup-copilot.sh` legger stien til `allow.read` i `~/.config/cplt/config.toml`, men bare når filen finnes. Det
   følger samme mønster som `~/.gradle/gradle.properties`.
3. `aha-watson` leser `~/.config/watson/aha.env` først, med `.env.personal` som reserve for kjøring utenfor sandbox.
4. Nettverk: cplt tillater allerede port 443. Med `--with-proxy` og `--allowed-domains` bør `nav1.aha.io` stå på listen.

## Risiko

| Risiko | Vurdering | Tiltak |
| --- | --- | --- |
| Agenten kan lese nøkkelen | Reell. En Aha-nøkkel har samme rettigheter som brukeren, ikke bare lesing | Bruk en egen nøkkel som kan tilbakekalles. Aha-innholdet er produktbeskrivelser, ikke personopplysninger |
| Nøkkelen sendes ut av sandboxen | Lav med domenelisten, ellers moderat | `--allowed-domains` med `nav1.aha.io` |
| Skriving til Aha | Aha-nøkkelen kan skrive | Skillen bruker bare `GET`. Legg det inn som regel i `SKILL.md` |
| Nøkkelen havner i Git | Lav | Filen ligger utenfor alle repoer, og `.gitignore` er uendret |

## Alternativer

- **Ingen åpning, lim inn manuelt:** tryggest, men bryter flyten.
- **Kjør Aha-oppslag utenfor sandboxen** og la agenten lese en eksportert fil i repoet (`.aha-cache/`, git-ignorert).
  Ingen nøkkel i sandboxen, men oppslaget må kjøres for hånd og kan bli utdatert.
- **Åpne `.env.personal`:** avvist. For bred.

## Beslutning som trengs

Er teamet komfortabelt med at agenten kan lese en personlig Aha-nøkkel? Hvis ikke, velg alternativet med eksportert fil.
