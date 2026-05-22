# Domeneordbok — Watson / Team Holmes

Forklarer Watson-spesifikke begreper og Nav Kontroll-domenet.
Bruk disse termene konsekvent i kode, kommentarer og dokumentasjon.

---

## Domene: Nav Kontroll

**Nav Kontroll** er den avdelingen i Nav som arbeider med å avdekke og forebygge
misbruk av Nav-ytelser (trygdesvindel). Watson er deres primærverktøy.

---

## Kjerneentiteter

### Kontrollsak
En sak opprettet av en saksbehandler i Nav Kontroll for å undersøke mulig
misbruk av Nav-ytelser hos en bruker. En kontrollsak er knyttet til ett
fødselsnummer og har en type, status og ansvarlig saksbehandler.

- **Kodeterm**: `kontrollsak` / `KontrollSak`
- **Engelsk**: _control case_

### Kontrollsakstype
Kategoriserer hva slags misbruk som undersøkes, f.eks. arbeid ved siden av ytelse,
feilaktige opplysninger om bosted, osv.

- **Kodeterm**: `kontrollsakstype` / `KontrollSaksType`

### Saksbehandler
Nav Kontroll-ansatt som bruker Watson. Identifiseres med NAVident (en bokstav + 6 sifre,
f.eks. `X123456`).

- **Kodeterm**: `saksbehandler` / `Saksbehandler`
- Lagres aldri som PII — bare NAVident refereres

### Bruker / Kontrollsubjekt
Personen som kontrolleres. Identifiseres med fødselsnummer (fnr) eller d-nummer.
Persondata hentes fra `nav-persondata-api` — lagres ikke i Watson-databasen.

- **Kodeterm**: `fnr` / `bruker`
- ⚠️ **PII** — aldri logge fnr

---

## Tekniske begreper

### NOM — Nasjonal organisasjonsmaster
Nav-internt system som er master for organisasjonsstruktur og ansattdata.
Watson bruker NOM for å hente informasjon om saksbehandlere.

- **Tjeneste**: `nom-api` (namespace: `nom`)
- **Kodeterm**: `nom` / `NomClient`

### Populasjonstilgangskontroll
Tjeneste som avgjør om en saksbehandler har tilgang til å se informasjon
om en spesifikk bruker, basert på saksbehandlerens AD-gruppe og brukerens
tilknytning.

- **Tjeneste**: `populasjonstilgangskontroll` (namespace: `tilgangsmaskin`)
- **Kodeterm**: `tilgangskontroll` / `TilgangskontrollClient`

### Oppgave
Nav-internt oppgavesystem. Watson oppretter og oppdaterer oppgaver i
tilknytning til kontrollsaker.

- **Tjeneste**: `oppgave` (namespace: `oppgavehandtering`)
- **Kodeterm**: `oppgave` / `OppgaveClient`

---

## Tilgangsgrupper (Azure AD)

| Gruppe | Kortform | Tilgang |
|--------|----------|---------|
| `0000-GA-kontroll-Oppslag-Bruker-Basic` | Basic | Les tilgang — søk og oppslag |
| `0000-GA-kontroll-Oppslag-Bruker-Utvidet` | Utvidet | Skrivetilgang — full saksbehandling |

Tilgangsgrupper sjekkes av `watson-admin-api` via token claims. Ingen bruker
skal ha tilgang uten å være i minst én av disse gruppene.

---

## Statuser

Kontrollsaker har en livssyklus med statuser. Se `watson-admin-api` for fullstendig
status-enum og overganger.

---

## Forkortelser

| Forkortelse | Betyr |
|-------------|-------|
| fnr | Fødselsnummer (11 siffer) |
| d-nr | D-nummer (identitetsnummer for utenlandske statsborgere) |
| NAVident | Ansatt-ID i Nav (f.eks. `X123456`) |
| NOM | Nasjonal organisasjonsmaster |
| PTK | Populasjonstilgangskontroll |
| OBO | On-Behalf-Of (token exchange-mønster i Azure AD) |

---

## Hva Watson ikke er

- Watson er **ikke** en ytelsesbehandlingstjeneste — den administrerer kontrollsaker,
  ikke selve vedtakene
- Watson er **ikke** offentlig tilgjengelig — systemet er intern (internal) på GitHub
  fordi det inneholder kontrolllogikk som ikke bør eksponeres
