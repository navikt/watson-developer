# watson-developer

Utviklermiljø for Team Holmes sine Watson-applikasjoner.

## Krav

| Verktøy | Installasjon |
|---------|-------------|
| [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) | `brew install kind` |
| [tilt](https://docs.tilt.dev/install.html) | `brew install tilt` |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | `brew install kubectl` |

## Kom i gang

### 1. Klon alle Watson-repoer

```bash
./scripts/clone-repos.sh
```

Skriptet er idempotent — kjør det igjen for å oppdatere eksisterende repoer med `git pull`.

### 2. Opprett kind-kluster

```bash
./scripts/setup-kind.sh
```

Idempotent — trygt å kjøre flere ganger. Oppretter kind-kluster `watson` og setter kubectl-kontekst.

### 3. Start lokalmiljøet

```bash
tilt up
```

Åpne Tilt UI på [http://localhost:10350](http://localhost:10350) for status og logger.

## Kjøremodus: Hybrid

Infrastruktur kjører i kind (Kubernetes), applikasjoner kjører som lokale prosesser:

| Tjeneste | Kjøres i | Port |
|----------|----------|------|
| PostgreSQL | kind | 5432 |
| mock-oauth2-server | kind | 8090 |
| watson-admin-api | lokal (`bootRun`) | 8080 |

watson-admin-api restartes **manuelt** via Tilt UI eller `tilt trigger watson-admin-api`.

## Nyttige lenker (når Tilt er oppe)

- [Swagger UI](http://localhost:8080/swagger-ui/index.html)
- [Health](http://localhost:8080/actuator/health)
- [mock-oauth2-server](http://localhost:8090)
- [Tilt UI](http://localhost:10350)

## Hent token for lokal testing

```bash
curl -s -X POST http://localhost:8090/azuread/token \
  -d "grant_type=client_credentials&client_id=watson-admin-api&client_secret=mock" \
  | python3 -m json.tool
```

## Repoer

| Repo | Beskrivelse |
|------|-------------|
| [nav-persondata-api](https://github.com/navikt/nav-persondata-api) | Persondata-API |
| [watson-admin-api](https://github.com/navikt/watson-admin-api) | Admin-API |
| [watson-sak-frontend](https://github.com/navikt/watson-sak-frontend) | Sak-frontend |
| [watson-sok](https://github.com/navikt/watson-sok) | Søk |

## Katalogstruktur

```
parent/
├── watson-developer/          ← dette repoet
│   ├── Tiltfile
│   ├── kind/cluster.yaml
│   ├── k8s/watson-admin-api/
│   └── scripts/
├── nav-persondata-api/
├── watson-admin-api/
├── watson-sak-frontend/
└── watson-sok/
```

## Fallback: docker-compose

`watson-admin-api` har en `docker-compose.yml` som kan brukes som alternativ til Tilt:

```bash
cd ../watson-admin-api
docker-compose up
```

> **Merk:** `docker-compose` bruker `host.docker.internal` for interne URL-er og er ikke lenger primær kjøremetode.