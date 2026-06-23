---
name: unleash-feature-toggle
description: Feature toggle-standarder for Holmes-porteføljen med Unleash — livssyklus, navnekonvensjoner, Kotlin-integrasjon og Nais-konfigurasjon
license: MIT
compatibility: Spring Boot Kotlin on Nais, Holmes namespace
metadata:
  domain: backend
  tags: unleash feature-toggle feature-flag kotlin spring-boot nais holmes
---

# Unleash Feature Toggle Skill

Standarder og mønstre for feature toggles i Holmes-porteføljen (`nav-persondata-api`, `watson-søk`, `watson-sak`).

Unleash-dashboardet: [holmes-unleash-web.iap.nav.cloud.nais.io](https://holmes-unleash-web.iap.nav.cloud.nais.io/projects/default?limit=25&favoritesFirst=true&sortBy=createdAt&sortOrder=desc)

## When to Use

- Ny funksjonalitet med risiko for å gå skeis skal skjules bak en toggle
- Rulle ut en feature uten ny deployment (deploy → aktiver i dashboardet)
- Koordinere release mellom `nav-persondata-api` (backend) og `watson-søk` (frontend)
- Rydde opp døde toggles etter verifisert produksjonssetting

## Livssyklus

```
1. Opprett toggle i Unleash-dashboardet
        ↓
2. Implementer i koden (backend + frontend om nødvendig)
        ↓
3. Deploy til dev og prod (toggle er av)
        ↓
4. Aktiver i development — verifiser
        ↓
5. Aktiver i production — verifiser
        ↓
6. Slett toggle fra kode og Unleash-dashboardet
```

**Regel:** Alltid verifiser i `development` før du aktiverer i `production`.
**Ansvar:** Utvikleren som implementerte featuren aktiverer og verifiserer i prod.

## Navnekonvensjoner

Format: `<prefix>-v<major>-<minor>`

| Kontekst | Prefix | Eksempel |
|----------|--------|---------|
| Funksjonalitet i watson-søk | `watson-sok` | `watson-sok-v-1-2` |
| Funksjonalitet i watson-sak | `watson-sak` | `watson-sak-v-2-0` |
| Generell / tverrgående | _(fritt valg med begrunnelse)_ | `ny-tilgangspolicy` |

Versjonsnummeret speiler hvilken release funksjonaliteten tilhører. Avvik krever begrunnelse.

## Kotlin-integrasjon (nav-persondata-api)

### 1. Legg til toggle i enumen

```kotlin
// src/main/kotlin/no/nav/persondataapi/unleash/Toggle.kt
enum class Toggle(val toggleName: String) {
    WATSON_SOK_V_1_2("watson-sok-v-1-2"),
    // Legg til nye toggles her
}
```

### 2. Bruk FeatureToggleService

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

NAVident-konteksten settes automatisk per request via `NavCallIdServletFilter` — ingen manuell
håndtering av kontekst er nødvendig.

### 3. Lokal utvikling

Lokalt (uten `UNLEASH_SERVER_API_URL` satt) returnerer alle toggles `false` automatisk via `FakeUnleash`.

```kotlin
// I tester: aktiver toggles eksplisitt
val fakeUnleash = FakeUnleash()
fakeUnleash.enable("watson-sok-v-1-2")
```

## Nais-konfigurasjon

### unleash-api-token.yaml

```yaml
apiVersion: unleash.nais.io/v1
kind: ApiToken
metadata:
  name: <app-name>
  namespace: holmes
  labels:
    team: holmes
spec:
  unleashInstance:
    apiVersion: unleash.nais.io/v1
    kind: RemoteUnleash
    name: holmes
  secretName: <app-name>-unleash-api-token
  environment: {{UNLEASH_ENVIRONMENT}}
```

### nais.yaml — accessPolicy og envFrom

```yaml
spec:
  accessPolicy:
    outbound:
      external:
        - host: holmes-unleash-api.nav.cloud.nais.io
  envFrom:
    - secret: <app-name>-unleash-api-token
```

### dev.json / prod.json

```json
{
  "UNLEASH_ENVIRONMENT": "development"   // dev
  "UNLEASH_ENVIRONMENT": "production"    // prod
}
```

Secretet som injiseres inneholder:
- `UNLEASH_SERVER_API_URL` — API-adressen til Holmes sin Unleash-instans
- `UNLEASH_SERVER_API_TOKEN` — API-nøkkel for applikasjonen
- `UNLEASH_SERVER_API_ENV` — miljø (development/production)

## Opprydding

Når featuren er verifisert i prod:

1. Fjern enum-verdien fra `Toggle`
2. Fjern alle `isEnabled`-sjekker — behold kun den nye kodeveien
3. Slett togglen i Unleash-dashboardet

Ikke la døde toggles bli liggende — de er teknisk gjeld.

## Boundaries

### ✅ Always

- Opprett alltid toggle i dashboardet **før** du merger kode
- Verifiser alltid i `development` før `production`
- Rydd opp toggles etter verifisert produksjonssetting
- Bruk `Toggle`-enum — aldri hardkodede strenger i `isEnabled`-kall

### ⚠️ Ask First

- Avvik fra navnekonvensjonen `<prefix>-v<major>-<minor>`
- Toggles som gjelder tvers av flere applikasjoner

### 🚫 Never

- Aktiver direkte i `production` uten å ha verifisert i `development` først
- La en toggle leve lenger enn nødvendig etter produksjonssetting
- Opprett API-tokens manuelt i Unleash (bruk `ApiToken`-ressursen i Nais)
