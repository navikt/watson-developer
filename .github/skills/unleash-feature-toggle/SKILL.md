---
name: unleash-feature-toggle
description: Hjelp til å opprette og rydde opp feature toggles i Holmes-porteføljen — navngivning, type, plassering og tverrrepo-opprydding
license: MIT
compatibility: Spring Boot Kotlin + React, Holmes-porteføljen
metadata:
  domain: backend
  tags: unleash feature-toggle feature-flag kotlin react holmes
---

# Unleash Feature Toggle Skill

Hjelper deg med å **opprette** og **rydde opp** feature toggles i Holmes-porteføljen
(`nav-persondata-api`, `watson-søk`, `watson-sak`).

Unleash-dashboardet: [holmes-unleash-web.iap.nav.cloud.nais.io](https://holmes-unleash-web.iap.nav.cloud.nais.io/projects/default?limit=25&favoritesFirst=true&sortBy=createdAt&sortOrder=desc)

## When to Use

- Du skal innføre en ny feature toggle og trenger hjelp med navn, type og plassering
- Du skal rydde opp etter en toggle som ikke lenger trengs

## Opprette en ny toggle

### Steg 1 — Velg navn

Format: `<prefix>-v<major>-<minor>`

| Kontekst | Prefix | Eksempel |
|----------|--------|---------|
| Funksjonalitet i watson-søk | `watson-sok` | `watson-sok-v-1-2` |
| Funksjonalitet i watson-sak | `watson-sak` | `watson-sak-v-2-0` |
| Generell / tverrgående | _(fritt valg med begrunnelse)_ | `ny-tilgangspolicy` |

Versjonsnummeret speiler hvilken release funksjonaliteten tilhører.

### Steg 2 — Velg type i Unleash-dashboardet

| Type | Bruk når |
|------|---------|
| **Release** | Ny funksjonalitet som skal rulles ut og deretter fjernes — vanligste valg |
| **Experiment** | A/B-testing eller gradvis utrulling til en andel brukere |
| **Operational** | Driftsbryter som kan leve lenger (f.eks. nødstopp for en integrasjon) |
| **Permission** | Tilgangskontroll per brukergruppe |

### Steg 3 — Legg til i backend

```kotlin
// src/main/kotlin/no/nav/persondataapi/unleash/Toggle.kt  (nav-persondata-api)
enum class Toggle(
    val toggleName: String,
) {
    WATSON_SOK_V_1_2("watson-sok-v-1-2"),
    // Legg til ny toggle her
}
```

Bruk via `FeatureToggleService`:

```kotlin
@Service
class MinService(private val toggles: FeatureToggleService) {
    fun gjørNoe() {
        if (toggles.isEnabled(Toggle.WATSON_SOK_V_1_2)) {
            // ny kode
        } else {
            // eksisterende kode / fallback
        }
    }
}
```

NAVident-konteksten settes automatisk per request — ingen manuell håndtering nødvendig.

### Steg 4 — Legg til i frontend (om relevant)

```typescript
// Bruk unleash-klienten som allerede er satt opp i frontend-appen
const isEnabled = useFlag("watson-sok-v-1-2");
```

### Steg 5 — Aktiver i riktig rekkefølge

1. Opprett toggle i dashboardet **før** du merger kode
2. Deploy til dev og prod (toggle er av)
3. Aktiver i `development` — verifiser
4. Aktiver i `production` — verifiser

Verifiser alltid i `development` før `production`. Utvikleren som implementerte featuren
har ansvar for å aktivere og verifisere i prod.

---

## Rydde opp etter en toggle

Bruk denne sjekklisten når en toggle er verifisert i prod og skal fjernes.

### Sjekkliste

#### Unleash-dashboardet
- [ ] Arkiver eller slett togglen i dashboardet

#### Backend
- [ ] Fjern enum-verdien fra `Toggle.kt`
- [ ] Fjern alle `toggles.isEnabled(Toggle.X)`-sjekker
- [ ] Behold kun den nye kodeveien — slett `else`-grenen og fallback-kode
- [ ] Fjern eventuelle kommentarer som refererer til togglen
- [ ] Kjør testene og verifiser at ingenting brekker

#### Frontend (om togglen var i bruk der)
- [ ] Fjern `useFlag("toggle-navn")`-kallet
- [ ] Behold kun den nye kodeveien — slett betinget rendering/logikk
- [ ] Fjern eventuelle kommentarer som refererer til togglen

#### Tverrrepo-søk (unngå å glemme noe)
Søk etter toggle-navnet i alle repoer:
```bash
grep -r "watson-sok-v-1-2" ../watson-søk ../nav-persondata-api ../watson-sak
```

---

## Boundaries

### ✅ Always

- Opprett toggle i dashboardet **før** kode merges
- Verifiser i `development` før `production`
- Bruk `Toggle`-enum i backend — aldri hardkodede strenger
- Rydd opp tverrrepo ved sletting — sjekk alle berørte repoer

### ⚠️ Ask First

- Avvik fra navnekonvensjonen `<prefix>-v<major>-<minor>`
- Toggles med lang levetid (operational) — vurder om det faktisk er en config-verdi

### 🚫 Never

- Aktiver i `production` uten å ha verifisert i `development` først
- La en avviklet toggle bli liggende i koden
- Fjern kun dashboardet-togglen uten å rydde opp koden (eller omvendt)
