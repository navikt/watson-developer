# Mal: bug

Bruk overskriftene under nøyaktig. Fjern hjelpeteksten i kursiv før du skriver
til Aha!. Ikke skriv personopplysninger eller konkrete kontrollsaker. Bruk
oppdiktede testdata i stegene.

```markdown
**Status:** ✅ Klar for agent | ⚠️ Ikke klar: <hva som mangler>

## Hva skjer
_Faktisk oppførsel. Ta med feilmelding hvis det finnes en._

## Forventet oppførsel
_Hva som skulle ha skjedd._

## Steg for å gjenskape
1. …
2. …
3. …

## Miljø og repo
- **Miljø:** <lokalt / dev / prod>
- **Repo:** <for eksempel watson-sok>

## Alvorlighet
_Hvem rammes, hvor ofte, og finnes det en omvei?_

## Akseptansekriterier
- **Gitt** <utgangspunkt>, **når** <handling>, **så** <riktig resultat>
- En test fanger feilen, slik at den ikke kommer tilbake.

## Utenfor scope
- _Hva vi bevisst ikke retter i denne oppgaven, for eksempel tilgrensende feil._

## Åpne spørsmål
- _Det vi ikke vet ennå. Skriv «Ingen» når alt er avklart._

## Brief til nav-pilot
**Mål:** <én setning>
**Ferdig når:** <henvisning til akseptansekriteriene>

**Verifiser før kjøring**
- Repoer nav-pilot kan endre: <liste>. Andre repoer krever at nav-pilot spør først.
```
