# Lokalmiljø — Teknisk oversikt

Beskriver hvordan Watson-porteføljens lokale utviklingsmiljø fungerer.

---

## Hybrid-modus

Infrastruktur kjører i kind (Kubernetes), applikasjoner kjører som lokale prosesser:

| Tjeneste | Kjøres i | Port |
|----------|----------|------|
| PostgreSQL | kind | 5432 |
| mock-oauth2-server | kind | 8090 |
| watson-admin-api | lokal (`bootRun`) | 8080 |
| watson-sak-frontend | lokal (`pnpm run dev:local`) | 5174 |

> OAuth2 access token for watson-sak-frontend hentes automatisk fra mock-oauth2-server ved Tilt-oppstart.

---

## Start og restart

`watson-admin-api` og `watson-sak-frontend` restartes **manuelt** via Tilt UI eller:

```bash
tilt trigger <ressursnavn>
```

---

## Nyttige lenker (når Tilt er oppe)

| Tjeneste | URL |
|----------|-----|
| Tilt UI | http://localhost:10350 |
| Swagger UI | http://localhost:8080/swagger-ui/index.html |
| Health | http://localhost:8080/actuator/health |
| Watson Sak | http://localhost:5174 |
| mock-oauth2-server | http://localhost:8090 |

---

## Hent token for lokal testing

```bash
curl -s -X POST http://localhost:8090/azuread/token \
  -d "grant_type=client_credentials&client_id=watson-admin-api&client_secret=mock" \
  | python3 -m json.tool
```

Tokenet kan brukes i `Authorization: Bearer <token>` for å kalle watson-admin-api lokalt.

---

## Miljøer og deployment

| Miljø | Plattform | Deployment |
|-------|-----------|-----------|
| dev | Nais GCP (nav-dev-gcp) | Ved merge til `main` |
| prod | Nais GCP (nav-prod-gcp) | Ved ny GitHub Release |

Se GitHub Actions i hvert repo for detaljer. Dev-deployment kan trigges manuelt via Actions-fanen.

---

## Videre lesning

- [docs/arkitektur/](arkitektur/README.md) — systemkart, autentisering og dataflyt
- [docs/domene/ordbok.md](domene/ordbok.md) — domenebegreper
