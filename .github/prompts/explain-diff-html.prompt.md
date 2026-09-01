---
name: explain-diff-html
description: Bruk når brukeren ber om en rik forklaring av en kodeendring, diff, branch eller PR. Produserer HTML-utdata.
model: GPT-5.3-Codex
---

# Explain Diff

Lag en kort, men rik og interaktiv forklaring av den angitte kodeendringen.

Skriv alt på norsk. Bruk en rolig, engasjerende stil med flyt og presisjon, som Martin Kleppmann: tydelig, undervisende og uten unødvendig jargon. Overganger mellom seksjoner skal være naturlige, og teksten skal være lærerik for både nybegynnere og erfarne lesere.

## Generell målsetning

Forklaringen skal være en hel side, oppbygget som et enkelt, responsivt dokument i HTML. Den skal inneholde en tabell of innhold, seksjoner og interaktive quiz-spørsmål. Dokumentet skal være selvstendig og kunne åpnes direkte i en nettleser uten ekstra bygg, rammeverk eller server.

## Viktige krav

- Start med tre quiz-spørsmål som er viktige for å forstå endringen. Ikke vis svarene i denne delen.
- Deretter kommer seksjonen `Bakgrunn`:
  - forklar det eksisterende systemet som er relevant for endringen
  - gi en dyp bakgrunn for nybegynnere, men ikke overbelast leseren
  - inkluder også en mer smal og konkret bakgrunn direkte knyttet til endringen
- Deretter kommer seksjonen `Intuisjon`:
  - forklar kjernen i endringen uten å gå i detalj i hver linje
  - bruk konkrete eksempler med toy data
  - bruk figurer/diagrammer i stor grad
- Deretter kommer seksjonen `Kode`:
  - gå gjennom endringen på høyt nivå
  - grupper endringene logisk og forklar dem i en forståelig rekkefølge
- Til slutt kommer `Quiz`:
  - fem spørsmål som tester forståelse av PR/en endring
  - spørsmålene skal ha medium vanskelighetsgrad
  - riktig svar er ikke nødvendigvis det lengste svaret
  - spørsmålene skal være innenfor substansen, ikke gotcha-spørsmål
  - presentér som interaktive flervalgsspørsmål
  - når brukeren klikker, skal den vise om svaret var korrekt og gi kort feedback

## Krav til HTML-format

- Output én enkelt, selvstendig HTML-fil.
- Inkluder CSS og JavaScript i samme fil.
- Bruk én lang side med seksjonshodere og innholdsfortegnelse.
- Ikke bruk tabulatorer for toppnivåstruktur.
- Sørg for responsiv styling slik at den også fungerer på mobil.
- Bruk Aksel-designsystemet så langt det er mulig. Hvis det ikke er praktisk å laste biblioteket i en helt selvstendig fil, bruk Aksel-tokens i CSS direkte (for eksempel `--a-bg-default`, `--a-surface-default`, `--a-text-default`, `--a-border-subtle`, `--a-spacing-*`, `--a-font-size-*`, `--a-font-weight-*`).
- Bruk semantisk HTML med elementer som `header`, `nav`, `main`, `section`, `article`, `aside`, `footer`, `button`, `details` og `summary` der det passer.
- Bruk enkel, moderne og ryddig styling som er lett å lese.
- Bruk callouts for nøkkelkonsepter, viktige definisjoner eller kritiske edge cases.
- Unngå ASCII-diagrammer. Bruk bare HTML-elementer, lister og blokker som ser profesjonelle ut.
- For kodeblokker, bruk alltid `<pre>`-tags. Hvis du bruker en egen stylingsklasse i stedet, må den ha `white-space: pre-wrap` i CSS.
- Bruk faktisk interaktivitet i quiz-delen med JavaScript som oppdaterer visning av resultat ved klikk.

## Visuell stil

- Velg noen få diagramfamilier og bruk dem konsekvent gjennom hele dokumentet.
- Gode eksempler:
  - forenklet brukergrensesnitt som viser hva brukeren ser i appen
  - systemdiagram som viser flyten av data mellom komponenter
  - liten konseptuell figur som viser før/etter-tilstand
- Diagrammer skal være og føles like datadrevne og tydelige som teksten.
- Bruk farger og rammer som er i tråd med Aksel, uten å gjøre det kunstig eller overdesignet.

## Delvis struktur du skal følge

Dokumentet skal ha disse seksjonene, i denne rekkefølgen:

1. `Innhold` (table of contents)
2. `Tre viktige spørsmål` (quiz uten svar)
3. `Bakgrunn`
   - bred bakgrunn for kontekst
   - smal bakgrunn relevant for endringen
4. `Intuisjon`
   - det sentrale konseptet
   - toy-data eksempel
   - diagrammer
5. `Kode`
   - høyt nivå gjennomgang av endringer
   - grupperet logisk
6. `Quiz`
   - fem spørsmål med flervalg
   - etter klikk: korrekt/feil + kort feedback
7. `Oppsummering`
   - kort konklusjon som knytter sammen poengene

## Krav til innhold

- Vær presis og tydelig.
- Vær konkret når du forklarer det sentrale: snakk om reelle felter, komponenter, flyter, edge cases og datamodeller hvis de er relevante.
- Hvis endringen er teknisk, forklar hva som blir enklere, tryggere eller mer forståelig sammenlignet med tidligere løsning.
- Hvis det finnes kontroverser eller valg i endringen, merk dem gjerne med en liten callout.
- Ikke bruk tom innledning eller generiske oppsummeringer uten substans.

## Filplassering og navngiving

Lagre filen utenfor kode-repositoriet i:

`../explanations/<repository-name>/YYYY-MM-DD-<beskrivende-slug>.html`

Merk:

- `repository-name` skal være navnet på repoet, hentet fra repo-roten eller git-navnet
- `YYYY-MM-DD` skal være dagens dato
- `beskrivende-slug` skal være kort, konsist og i kebab-case
- Katalogen skal opprettes om den ikke finnes
- Ikke overskriv en eksisterende fil
- Hvis målet allerede finnes, legg til `-2`, `-3`, osv. før `.html`
- Filen skal være persistente, søkbare og sortert etter dato i katalogen utenfor versjonskontrollen

## Utfør først denne logikken før du skriver HTML

1. Finn repo-navn og repo-root.
2. Koble dagens dato til formatet `YYYY-MM-DD`.
3. Generer et kort, beskrivende slug i kebab-case som reflekterer endringen.
4. Sjekk om den målrettede filen allerede finnes.
5. Hvis den finnes, inkrementér suffikset: `-2`, `-3`, etc.
6. Opprett katalogen `../explanations/<repository-name>/` om nødvendig.
7. Skriv kun en enkelt HTML-fil til den endelige banen.

## Viktige retningslinjer for kvalitet

- Fokuser på forståelse, ikke bare tekniske detaljer.
- Gi leseren klare mentale modeller, ikke bare en liste med endringer.
- Bruk små, lesbare eksempeldata for å gjøre abstrakte konsepter konkrete.
- Vis hvor endringen er mest kritisk, hva den løser, og hvorfor den var nødvendig.
- Dokumentet skal være engasjerende nok til at en leser vil fortsette helt til quizet.

## Viktig: bruk norsk tekst i hele dokumentet

- Alle tekstlige ledetekster, section-titler, feedback, vare oppsummeringer og quiz-tekster skal være på norsk.
- Bruk norsk språkbruk med flyt og tydelighet.
- Unngå engelsk tekst i knapper, avsnitt, labels eller hjelpetekster dersom norsk er naturlig.

## Sluttinstruksjon

Generer en komplett, self-contained HTML-fil som oppfyller alle krav over. Følg struktur, stil og filplassering nøyaktig. Sørg for at resultatet er både faglig solid og lett å lese.

Still gjerne spørsmål om valgene over hvis noe i endringen er uklart.
