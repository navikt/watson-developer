---
name: analytics-taxonomy
description: Nav analytics-taksonomi med Umami-eventnavn, attributter og personvernregler for frontend-applikasjoner
license: MIT
compatibility: React/Next.js frontend på Nais
metadata:
  domain: frontend
  tags: analytics umami sporing taksonomi events personvern
---

# Analytics-taksonomi for Nav

Nav bruker en felles taksonomi for analytics-events. Taksonomien sikrer konsistente navn, sammenlignbare data på tvers av team, og at ingen personopplysninger sendes til analyseplattformen.

Kilde: [navikt/analytics-taxonomy](https://github.com/navikt/analytics-taxonomy)

## Grunnprinsipper

- **Naturlig språk, fortid**: eventnavn beskriver noe brukeren *gjorde* — «skjema åpnet», ikke «openForm»
- **camelCase i attributter**: `skjemaId`, `lenketekst`, `pagePath`
- **Allowlist-validering**: kun definerte attributter sendes — forhindrer at PII lekker

## Implementering

Nav bruker sitt eget sporingsskript (`sporing.js`) som sender events til `umami.nav.no`. Se referanseimplementasjon i [`app/analytics/analytics.tsx`](../watson-sak-frontend/app/analytics/analytics.tsx).

### 1. Last inn sporingsskriptet

Legg `AnalyticsTags` i rotruten din (f.eks. `root.tsx`):

```typescript
// app/analytics/analytics.tsx
type AnalyticsTagProps = {
  sporingId: string;
};

export function AnalyticsTags({ sporingId }: AnalyticsTagProps) {
  return (
    <script
      defer
      src="https://cdn.nav.no/team-researchops/sporing/sporing.js"
      data-host-url="https://umami.nav.no"
      data-website-id={sporingId}
    />
  );
}
```

```tsx
// app/root.tsx
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

### 2. Definer og spor hendelser

```typescript
// app/analytics/analytics.tsx
import { logger } from "~/logging/logging";

/** Spor en hendelse til analyseformål */
export function sporHendelse(hendelse: Hendelse, data: Record<string, unknown> = {}) {
  if (process.env.NODE_ENV === "development") {
    if (hendelse.length > 50) {
      logger.warn(`📊 [Analytics] Hendelse "${hendelse}" er for lang (maks 50 tegn)`);
    }
    logger.info(`📊 [Analytics] ${hendelse}`, data);
    return;
  }
  if (typeof window !== "undefined" && window.umami) {
    window.umami.track(hendelse.substring(0, 50), data);
  }
}

type Hendelse =
  | "navigere"
  | "søk utført"
  | "filter brukt"
  // legg til applikasjonsspesifikke hendelser her
  | string;
```

## Alle standardeventer

### `besøk`

Loggføres automatisk av **nav-dekoratøren** — ikke implementer i egen app.

Attributter beriket av nav-dekoratøren:
- `url` — siden brukeren besøkte
- `sidetittel` — tittelen på siden

---

### `navigere`

Loggføres automatisk av **nav-dekoratøren** for klikk i dekoratøren. Team legger til sporing i sin egen app der det er ønskelig.

| Attributt | Påkrevd | Type | Beskrivelse |
|-----------|---------|------|-------------|
| `lenketekst` | nei | string | Teksten på lenken brukeren trykket på |
| `destinasjon` | nei | string | URL brukeren sendes til |

```typescript
sporHendelse("navigere", {
  lenketekst: "Les mer om dagpenger",
  destinasjon: "https://www.nav.no/dagpenger",
});
```

---

### `søk`

| Attributt | Påkrevd | Type | Beskrivelse |
|-----------|---------|------|-------------|
| `destinasjon` | ja | string | Tjeneste-URL søket sendes til |
| `søkeord` | ja | string | Strengen brukeren søkte på |
| `komponent` | nei | string | Navn på komponenten søket utføres fra |

```typescript
sporHendelse("søk", {
  destinasjon: "https://www.nav.no/sok",
  søkeord: "dagpenger",
  komponent: "global-søkeboks",
});
```

---

### `filtervalg`

| Attributt | Påkrevd | Type | Beskrivelse |
|-----------|---------|------|-------------|
| `kategori` | ja | string | Tekst på filteret som brukes |
| `filternavn` | ja | string | Tekst på filteralternativet som velges |

```typescript
sporHendelse("filtervalg", {
  kategori: "Status",
  filternavn: "Under behandling",
});
```

---

### `last ned`

| Attributt | Påkrevd | Type | Beskrivelse |
|-----------|---------|------|-------------|
| `type` | ja | string | Filtype eller dokumenttype (f.eks. «Saksdokument», «Statistikk») |
| `tema` | ja | string | Hva handler filen om? (f.eks. «Dagpenger», «Foreldrepenger») |
| `tittel` | ja | string | Tittel på dokumentet som lastes ned |

```typescript
sporHendelse("last ned", {
  type: "Saksdokument",
  tema: "Dagpenger",
  tittel: "Vedtak om dagpenger 2024",
});
```

---

### `accordion åpnet` / `accordion lukket`

| Attributt | Påkrevd | Type | Beskrivelse |
|-----------|---------|------|-------------|
| `tekst` | ja | string | Teksten på accordion-headingen |

```typescript
sporHendelse("accordion åpnet", { tekst: "Hvem kan søke om dagpenger?" });
sporHendelse("accordion lukket", { tekst: "Hvem kan søke om dagpenger?" });
```

---

### `modal åpnet` / `modal lukket`

| Attributt | Påkrevd | Type | Beskrivelse |
|-----------|---------|------|-------------|
| `tekst` | ja | string | Teksten på modalen (tittel eller kort beskrivelse) |

```typescript
sporHendelse("modal åpnet", { tekst: "Bekreft innsending" });
sporHendelse("modal lukket", { tekst: "Bekreft innsending" });
```

---

### `alert vist`

| Attributt | Påkrevd | Type | Beskrivelse |
|-----------|---------|------|-------------|
| `variant` | ja | string | Hvilken variant: `info`, `success`, `warning`, `error` |
| `tekst` | ja | string | Teksten i alerten |

```typescript
sporHendelse("alert vist", {
  variant: "warning",
  tekst: "Du har ikke sendt inn skjemaet ennå",
});
```

---

### `guidepanel vist`

| Attributt | Påkrevd | Type | Beskrivelse |
|-----------|---------|------|-------------|
| `komponent` | ja | string | Statisk beskrivelse av hvilken komponent dette er |
| `tekst` | nei | string | Tekst i guidepanelet — utelat hvis sensitivt |

```typescript
sporHendelse("guidepanel vist", {
  komponent: "dagpenger-veileder-intro",
  tekst: "Vi trenger litt informasjon om din situasjon",
});
```

---

### `chat startet` / `chat avsluttet`

| Attributt | Påkrevd | Type | Beskrivelse |
|-----------|---------|------|-------------|
| `komponent` | ja | string | Navn på chat-komponenten |

```typescript
sporHendelse("chat startet", { komponent: "boost-chatbot" });
sporHendelse("chat avsluttet", { komponent: "boost-chatbot" });
```

---

## Skjema-events

Skjema-events brukes i sekvens for å følge brukerens reise gjennom et skjema. `skjemaId` og `skjemanavn` er påkrevd i alle skjema-events.

### Sekvens

```
skjema åpnet → skjema startet → skjema spørsmål besvart (×n)
             → skjema steg fullført (×n)
             → skjema validering feilet? (×n)
             → skjema innsending feilet? (×n)
             → skjema fullført
```

---

### `skjema åpnet`

En bruker åpnet skjema-siden.

| Attributt | Påkrevd | Type | Beskrivelse |
|-----------|---------|------|-------------|
| `skjemanavn` | ja | string | Navn på skjemaet |
| `skjemaId` | ja | string | ID på skjemaet |

```typescript
sporHendelse("skjema åpnet", {
  skjemanavn: "Søknad om dagpenger",
  skjemaId: "NAV 04-01.03",
});
```

---

### `skjema startet`

En bruker startet utfyllingen (f.eks. trykket «Start søknad»).

| Attributt | Påkrevd | Type | Beskrivelse |
|-----------|---------|------|-------------|
| `skjemanavn` | ja | string | Navn på skjemaet |
| `skjemaId` | ja | string | ID på skjemaet |

```typescript
sporHendelse("skjema startet", {
  skjemanavn: "Søknad om dagpenger",
  skjemaId: "NAV 04-01.03",
});
```

---

### `skjema spørsmål besvart`

En bruker besvarte ett spørsmål i skjemaet.

| Attributt | Påkrevd | Type | Beskrivelse |
|-----------|---------|------|-------------|
| `skjemanavn` | ja | string | Navn på skjemaet |
| `skjemaId` | ja | string | ID på skjemaet |
| `spørsmål` | ja | string | Teksten på spørsmålet |
| `svar` | ja | string | Svaret brukeren ga — **aldri fritekst fra bruker** |

> ⚠️ **Personvern**: `svar` skal kun inneholde forhåndsdefinerte svaralternativer (f.eks. «Ja» / «Nei»), aldri fritekst brukeren har skrevet.

```typescript
sporHendelse("skjema spørsmål besvart", {
  skjemanavn: "Søknad om dagpenger",
  skjemaId: "NAV 04-01.03",
  spørsmål: "Er du registrert som arbeidssøker hos NAV?",
  svar: "Ja",
});
```

---

### `skjema steg fullført`

Et steg i et flersides skjema er fullført.

| Attributt | Påkrevd | Type | Beskrivelse |
|-----------|---------|------|-------------|
| `skjemanavn` | ja | string | Navn på skjemaet |
| `skjemaId` | ja | string | ID på skjemaet |
| `steg` | ja | string | Navn på steget som ble fullført |

```typescript
sporHendelse("skjema steg fullført", {
  skjemanavn: "Søknad om dagpenger",
  skjemaId: "NAV 04-01.03",
  steg: "Arbeidssituasjon",
});
```

---

### `skjema validering feilet`

Skjemavalidering feilet (f.eks. manglende påkrevde felt).

| Attributt | Påkrevd | Type | Beskrivelse |
|-----------|---------|------|-------------|
| `skjemanavn` | ja | string | Navn på skjemaet |
| `skjemaId` | ja | string | ID på skjemaet |

```typescript
sporHendelse("skjema validering feilet", {
  skjemanavn: "Søknad om dagpenger",
  skjemaId: "NAV 04-01.03",
});
```

---

### `skjema innsending feilet`

Innsendingen til API feilet.

| Attributt | Påkrevd | Type | Beskrivelse |
|-----------|---------|------|-------------|
| `skjemanavn` | ja | string | Navn på skjemaet |
| `skjemaId` | ja | string | ID på skjemaet |

```typescript
sporHendelse("skjema innsending feilet", {
  skjemanavn: "Søknad om dagpenger",
  skjemaId: "NAV 04-01.03",
});
```

---

### `skjema fullført`

Brukeren har sendt inn skjemaet.

| Attributt | Påkrevd | Type | Beskrivelse |
|-----------|---------|------|-------------|
| `skjemanavn` | ja | string | Navn på skjemaet |
| `skjemaId` | ja | string | ID på skjemaet |

```typescript
sporHendelse("skjema fullført", {
  skjemanavn: "Søknad om dagpenger",
  skjemaId: "NAV 04-01.03",
});
```

---

## TypeScript-hjelpefunksjoner

Wrap standardeventer i typesikre funksjoner for å unngå skrivefeil:

```typescript
// analytics/events.ts
import { sporHendelse } from "~/analytics/analytics";

const SKJEMA_NAVN = "Søknad om dagpenger";
const SKJEMA_ID = "NAV 04-01.03";

export const analytics = {
  skjemaÅpnet: () =>
    sporHendelse("skjema åpnet", { skjemanavn: SKJEMA_NAVN, skjemaId: SKJEMA_ID }),

  skjemaStartet: () =>
    sporHendelse("skjema startet", { skjemanavn: SKJEMA_NAVN, skjemaId: SKJEMA_ID }),

  spørsmålBesvart: (spørsmål: string, svar: string) =>
    sporHendelse("skjema spørsmål besvart", {
      skjemanavn: SKJEMA_NAVN,
      skjemaId: SKJEMA_ID,
      spørsmål,
      svar,
    }),

  stegFullført: (steg: string) =>
    sporHendelse("skjema steg fullført", {
      skjemanavn: SKJEMA_NAVN,
      skjemaId: SKJEMA_ID,
      steg,
    }),

  valideringFeilet: () =>
    sporHendelse("skjema validering feilet", {
      skjemanavn: SKJEMA_NAVN,
      skjemaId: SKJEMA_ID,
    }),

  innsendingFeilet: () =>
    sporHendelse("skjema innsending feilet", {
      skjemanavn: SKJEMA_NAVN,
      skjemaId: SKJEMA_ID,
    }),

  skjemaFullført: () =>
    sporHendelse("skjema fullført", { skjemanavn: SKJEMA_NAVN, skjemaId: SKJEMA_ID }),

  navigere: (lenketekst: string, destinasjon: string) =>
    sporHendelse("navigere", { lenketekst, destinasjon }),

  accordionÅpnet: (tekst: string) =>
    sporHendelse("accordion åpnet", { tekst }),

  accordionLukket: (tekst: string) =>
    sporHendelse("accordion lukket", { tekst }),
};
```

---

## Personvernregler

| Regel | Forklaring |
|-------|-----------|
| **Ikke log fnr eller aktørId** | Send aldri personnummer, d-nummer eller aktørId som attributtverdi |
| **Ikke log fritekst fra bruker** | Fritekstfelter kan inneholde PII — send aldri råverdi fra input-felt |
| **`svar` kun forhåndsdefinerte verdier** | I `skjema spørsmål besvart` skal `svar` kun inneholde faste alternativer |
| **Utelat sensitiv tekst i `guidepanel vist`** | Hvis `tekst`-attributtet kan inneholde sensitive opplysninger, utelat det |
| **Allowlist håndheves av taksonomien** | Attributter utenfor allowlist avvises — ikke forsøk å legge til egne |

---

## Gotchas

- `besøk` og `navigere` (i dekoratøren) trenger du ikke implementere selv — men du kan logge `navigere` i tillegg for lenker inni appen
- Umami begrenser eventnavn til **50 tegn** — `sporHendelse` kutter automatisk, men hold navnene korte
- `skjema åpnet` ≠ `skjema startet`: åpnet = siden lastet, startet = brukeren trykket «Start»
- Bruk konstanter for `skjemanavn` og `skjemaId` — ikke hard-code strenger flere steder

## Boundaries

### ✅ Always

- Bruk eksakt eventnavn fra taksonomien (norsk, mellomrom, ikke camelCase)
- Inkluder alle påkrevde attributter
- Wrap events i typesikre hjelpefunksjoner per applikasjon
- Sjekk personvernreglene for `svar`-attributtet og fritekst

### ⚠️ Ask First

- Behov for et event som ikke finnes i taksonomien → lag PR til [analytics-taxonomy](https://github.com/navikt/analytics-taxonomy)
- Usikker på om et attributt er sensitivt — spør personvernombud

### 🚫 Never

- Log fnr, aktørId, navn, adresse eller andre personopplysninger som attributtverdi
- Bruk fritekst fra bruker som `svar` i `skjema spørsmål besvart`
- Oppfinn egne eventnavn uten å bidra til taksonomien
- Sett CPU-limits i Nais (ikke relevant her, men universelt)
