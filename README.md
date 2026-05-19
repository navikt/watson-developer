# watson-developer

Utviklermiljø for Team Holmes sine Watson-applikasjoner.

## Kom i gang

Klon alle Watson-repoer som søsken-kataloger:

```bash
./scripts/clone-repos.sh
```

Skriptet er idempotent — kjør det igjen for å oppdatere eksisterende repoer med `git pull`.

## Repoer

| Repo | Beskrivelse |
|------|-------------|
| [nav-persondata-api](https://github.com/navikt/nav-persondata-api) | Persondata-API |
| [watson-admin-api](https://github.com/navikt/watson-admin-api) | Admin-API |
| [watson-sak-frontend](https://github.com/navikt/watson-sak-frontend) | Sak-frontend |
| [watson-sok](https://github.com/navikt/watson-sok) | Søk |

## Katalogstruktur etter kloning

```
parent/
├── watson-developer/          ← dette repoet
├── nav-persondata-api/
├── watson-admin-api/
├── watson-sak-frontend/
└── watson-sok/
```