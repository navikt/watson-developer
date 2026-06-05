---
name: analytics-taxonomy
description: Nav analytics-taksonomi med Umami-eventnavn, attributter og personvernregler for frontend-applikasjoner
license: MIT
compatibility: React/Next.js frontend på Nais
metadata:
  domain: frontend
  tags: analytics umami sporing taksonomi events personvern
---

# Analytics for Watson-frontend

Tre ting denne skillen hjelper deg med:

1. [Spore en hendelse i koden](#slik-sporer-du-en-hendelse)
2. [Velge navn på et nytt event](#navngi-et-nytt-event)
3. [Avgjøre om noe er et eget event eller en parameter](#nytt-event-eller-ny-parameter)

Referanseimplementasjon: [`app/analytics/analytics.tsx`](../watson-sak-frontend/app/analytics/analytics.tsx)

---

## Slik sporer du en hendelse

Kall `sporHendelse` fra `~/analytics/analytics`:

```typescript
import { sporHendelse } from "~/analytics/analytics";

sporHendelse("sak opprettet", { saktype: "EØS-sak" });
```

Det er det. `sporHendelse` logger til konsoll i development og sender til `umami.nav.no` i produksjon.

### Wrap i typesikre hjelpefunksjoner

Ikke kall `sporHendelse` direkte fra komponenter — samle dem i en `analytics`-modul:

```typescript
// app/analytics/events.ts
import { sporHendelse } from "~/analytics/analytics";

export const analytics = {
  sakOpprettet: (saktype: string) =>
    sporHendelse("sak opprettet", { saktype }),

  filterBrukt: (kategori: string, verdi: string) =>
    sporHendelse("filter brukt", { kategori, verdi }),

  sokUtfort: (kilde: string) =>
    sporHendelse("søk utført", { kilde }),
};
```

```typescript
// I en komponent
import { analytics } from "~/analytics/events";

analytics.sakOpprettet("EØS-sak");
```

### Sett opp sporingsskriptet (én gang per app)

`AnalyticsTags` legges i rotruten (`root.tsx`). `SPORING_ID` er Umami-nøkkelen for appen:

```tsx
import { AnalyticsTags } from "~/analytics/analytics";

export default function Root() {
  return (
    <html>
      <head>
        <AnalyticsTags sporingId={ENV.SPORING_ID} />
      </head>
      ...
    </html>
  );
}
```

---

## Navngi et nytt event

### Formel

```
[substantiv] [verb i fortid]
```

Eventnavn beskriver hva brukeren **gjorde**, på norsk bokmål, med mellomrom som separator. Maks 50 tegn.

| ✅ Riktig | ❌ Feil | Feil fordi |
|-----------|---------|------------|
| `sak opprettet` | `createCase` | Engelsk |
| `filter brukt` | `filterBrukt` | camelCase |
| `søk utført` | `søk` | For vagt, ikke fortidsform |
| `dokument lastet ned` | `download` | Engelsk |
| `notat lagret` | `noteSaved` | Engelsk, camelCase |
| `varsler åpnet` | `openNotifications` | Engelsk |

### Vanlige verb å bruke

`opprettet` · `lukket` · `åpnet` · `brukt` · `utført` · `valgt` · `endret` · `lastet ned` · `sendt` · `avbrutt` · `fullført` · `feilet`

### Watson-spesifikke eksempler

```
sak opprettet          sak lukket             sak status endret
sak satt på vent       sak gjenopptatt        sak redigert
søk utført             søk resultat valgt     person oppslag
filter brukt           fordeling utført       notat lagret
journalpost opprettet  oppgave opprettet      fil lastet opp
```

---

## Nytt event eller ny parameter?

Dette er det vanligste designspørsmålet. Tommelfingerregel:

> **Stiller du deg spørsmålet «hva skjedde?» → eventnavn. «Mer om hva som skjedde?» → parameter.**

### Lag et nytt event når

Brukerens **intensjon eller handling** er fundamentalt annerledes:

```
sak opprettet  ≠  sak lukket       → to events (ulik handling)
søk utført     ≠  filter brukt     → to events (ulik mekanisme)
modal åpnet    ≠  modal lukket     → to events (ulik retning)
```

### Bruk parameter (data) når

Det er **samme handling**, men i ulik kontekst, med ulik metadata, eller ulike varianter:

| Situasjon | Gjør dette |
|-----------|-----------|
| Samme knapp finnes flere steder i appen | `sporHendelse("søk utført", { kilde: "saksliste" })` |
| Handlingen gjelder ulike typer objekter | `sporHendelse("dokument lastet ned", { type: "PDF" })` |
| Du vil skille på hvilken variant/flyt brukeren var i | `sporHendelse("sak opprettet", { saktype: "EØS-sak" })` |
| Du vil måle et steg i en sekvens | `sporHendelse("skjema steg fullført", { steg: "Personopplysninger" })` |

### Eksempel: sak-handlinger i Watson

```typescript
// ✅ Riktig: fire ulike hendelser
sporHendelse("sak opprettet",    { saktype: "EØS-sak" });
sporHendelse("sak lukket",       { aarsak: "Henlagt" });
sporHendelse("sak satt på vent", { antallDager: 7 });
sporHendelse("sak redigert",     { felt: "tittel" });

// ❌ Feil: én hendelse med type-parameter
sporHendelse("sak handling", { handling: "opprettet", saktype: "EØS-sak" });
// → "hva skjedde?" er uklart, umulig å filtrere direkte på handling
```

```typescript
// ✅ Riktig: ett event med kilde-parameter
sporHendelse("søk utført", { kilde: "hurtigsøk" });
sporHendelse("søk utført", { kilde: "avansert-søk" });

// ❌ Feil: to separate events
sporHendelse("hurtigsøk utført");
sporHendelse("avansert søk utført");
// → samme brukerintensjon, unødvendig splitting
```

---

## Standardeventer fra Nav-taksonomien

Bruk disse før du lager egne. Kilde: [navikt/analytics-taxonomy](https://github.com/navikt/analytics-taxonomy)

| Event | Påkrevde attributter | Automatisk? |
|-------|---------------------|-------------|
| `besøk` | — | ✅ Nav-dekoratøren |
| `navigere` | `lenketekst`, `destinasjon` | ✅ Nav-dekoratøren (kan suppleres) |
| `søk` | `destinasjon`, `søkeord` | Nei |
| `filtervalg` | `kategori`, `filternavn` | Nei |
| `last ned` | `type`, `tema`, `tittel` | Nei |
| `accordion åpnet/lukket` | `tekst` | Nei |
| `modal åpnet/lukket` | `tekst` | Nei |
| `alert vist` | `variant`, `tekst` | Nei |
| `skjema åpnet` | `skjemanavn`, `skjemaId` | Nei |
| `skjema startet` | `skjemanavn`, `skjemaId` | Nei |
| `skjema fullført` | `skjemanavn`, `skjemaId` | Nei |
| `skjema validering feilet` | `skjemanavn`, `skjemaId` | Nei |

> `skjema åpnet` = siden lastet. `skjema startet` = brukeren trykket «Start». Ikke forveksle disse.

---

## Personvern

| ❌ Send aldri | ✅ Send heller |
|--------------|--------------|
| Fødselsnummer, d-nummer, aktørId | Sakstype, status, kategori |
| Fritekst brukeren har skrevet | Forhåndsdefinerte svaralternativer |
| Navn, adresse, kontaktinfo | Generiske labels: «utfylt», «tomt» |
| Token-verdier eller interne ID-er | Anonyme teller: antall, indeks |

---

## Boundaries

### ✅ Always

- Bruk `sporHendelse` fra `~/analytics/analytics` — ikke kall `window.umami` direkte
- Norsk bokmål, mellomrom, fortidsform i eventnavn
- Wrap i typesikre hjelpefunksjoner — ikke strenger spredt i komponenter
- Sjekk personverntabellen før du sender attributter

### ⚠️ Ask First

- Event du trenger finnes ikke i Nav-taksonomien → lag PR til [analytics-taxonomy](https://github.com/navikt/analytics-taxonomy)
- Usikker på om et attributt er sensitivt → spør personvernombud

### 🚫 Never

- Send fnr, aktørId, navn eller annen PII som attributtverdi
- Bruk fritekst fra bruker som attributtverdi
- Hard-code eventnavn som strenger direkte i komponenter
