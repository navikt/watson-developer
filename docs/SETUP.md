# Oppsett av utviklermiljø

Detaljert guide for å sette opp Watson-porteføljens lokale utviklingsmiljø.

> 💡 **Automatisk oppsett:** Kjør `./scripts/bootstrap.sh` (se «Helt ny Mac»
> under) og be agenten kjøre skillen `watson-setup`.

---

## Helt ny Mac

Klon repoet og kjør bootstrap-skriptet i en vanlig terminal (ikke i cplt):

```bash
mkdir -p ~/code/nav/holmes/watson && cd ~/code/nav/holmes/watson
git clone https://github.com/navikt/watson-developer.git
cd watson-developer
./scripts/bootstrap.sh
```

Mangler Xcode Command Line Tools, åpner `git clone` en installasjonsdialog.
Fullfør den og kjør `git clone` på nytt. Skriptet installerer Homebrew, git,
gh og agenten du velger, logger deg inn på GitHub og starter agenten. Be
agenten kjøre skillen `watson-setup`. Bruk `./scripts/bootstrap.sh --no-start`
hvis du ikke vil starte agenten med en gang.

### Velg agent

| Agent | Valg | Installeres med |
| --- | --- | --- |
| [opencode](https://opencode.ai/v2/docs) 2 (standard) | `--agent opencode` | `curl -fsSL https://opencode.ai/v2/install \| bash` |
| [GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli) | `--agent copilot` | `brew install copilot-cli` |
| [pi](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) | `--agent pi` | `npm install -g @earendil-works/pi-coding-agent` |

Valget lagres i `~/.config/watson-developer/agent` og brukes av
`setup-harness.sh`, `doctor.sh` og `setup-mcp.sh`. Overstyr med `--agent` eller
miljøvariabelen `WATSON_AGENT`. Kjør `./scripts/setup-harness.sh --agent <navn>`
for å bytte agent senere. `nav-pilot mcp` støtter ikke pi, så med pi blir
MCP-serverne ikke satt opp.

---

## Verktøykrav

| Verktøy                                                              | Installasjon                        | Brukes til                                                    |
| -------------------------------------------------------------------- | ----------------------------------- | ------------------------------------------------------------- |
| Xcode Command Line Tools                                             | `xcode-select --install`            | git og kompilatorer på macOS                                  |
| [Homebrew](https://brew.sh)                                          | `./scripts/bootstrap.sh`            | Pakkebehandler for resten av verktøyene                       |
| git og [gh](https://cli.github.com)                                  | `brew install git gh`               | Kloning og GitHub-innlogging (`gh auth login`)                |
| KI-agent (opencode, Copilot CLI eller pi)                            | `./scripts/bootstrap.sh`            | Kjører skillen `watson-setup`                                 |
| [Docker Desktop](https://www.docker.com/products/docker-desktop/)    | `brew install --cask docker`        | Container-runtime for kind                                    |
| [cplt](https://github.com/navikt/cplt)                               | `brew install navikt/tap/cplt`      | Kernel-sandbox for AI-agenter                                 |
| [nav-pilot](https://ki-utvikling.nav.no/nav-pilot/docs)              | `brew install navikt/tap/nav-pilot` | Nav-kunnskap for agenten                                      |
| [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) | `brew install kind`                 | Lokal Kubernetes-kluster                                      |
| [tilt](https://docs.tilt.dev/install.html)                           | `brew install tilt`                 | Lokal utviklingsserver                                        |
| [kubectl](https://kubernetes.io/docs/tasks/tools/)                   | `brew install kubectl`              | Kubernetes-klient                                             |
| [gcloud](https://cloud.google.com/sdk/docs/install)                  | se lenke                            | GCP-autentisering og secrets                                  |
| [k9s](https://k9scli.io/topics/install/)                             | `brew install k9s`                  | Kubernetes dashboard (valgfritt)                              |
| Java 21                                                              | `brew install --cask temurin@21`    | watson-admin-api, nav-persondata-api                          |
| Node.js LTS                                                          | `brew install node`                 | watson-sak-frontend, watson-sok                               |
| [pnpm](https://pnpm.io/installation)                                 | `corepack enable`                   | Pakkebehandler for frontend                                   |
| Python 3.11+                                                         | `brew install python@3.12`          | `tomllib` — leser/oppdaterer cplt-config i setup-harness.sh   |

Kjør `./scripts/doctor.sh` for å se hva som mangler — skriptet installerer
manglende verktøy automatisk med Homebrew (`corepack enable` for pnpm) der det
er mulig, og faller tilbake til å vise installasjonskommandoen hvis Homebrew
ikke er tilgjengelig eller installasjonen feiler.

---

## Steg-for-steg oppsett

### 1. Sett opp AI-verktøy (cplt + nav-pilot)

```bash
./scripts/setup-harness.sh
```

Installerer [cplt](https://github.com/navikt/cplt) (kernel-sandbox for AI-agenter) og
[nav-pilot](https://ki-utvikling.nav.no/nav-pilot/docs) (Nav-kunnskap for agenten). Legger også inn et shell-alias slik at agenten du valgte kjører i cplt-sandboxen.
Genererer cplt-config tilpasset Watson-porteføljen. Idempotent — trygt å kjøre flere ganger.
Scriptet krever python3.11+ (for `tomllib`) og installerer det selv automatisk
med Homebrew hvis det mangler, siden dette steget kjøres før `doctor.sh`.
MCP-servere settes opp separat med `./scripts/setup-mcp.sh` i en vanlig
terminal. Listen over servere står i `mcp-servere.txt`.

Sandboxen får bevisst ikke lesetilgang til `~/.kube/config` — den inneholder
som regel cluster-admin-credentials, og det lokale kind-klusteret trenger
ikke den eksponeringen selv om det ikke inneholder ekte hemmeligheter. Kjør
`kubectl`/`tilt` direkte i terminalen (utenfor sandboxen), eller legg til
tilgangen selv i `~/.config/cplt/config.toml` hvis du ønsker at agenten skal
kunne bruke dem.

### 2. Sjekk at verktøyene er på plass

```bash
./scripts/doctor.sh
```

Skriptet verifiserer at alle nødvendige verktøy er installert med riktig
versjon, og installerer manglende verktøy automatisk via Homebrew (eller
`corepack enable` for pnpm) der det er mulig. Auto-installasjon er slått av
når skriptet kjører inni cplt-sandboxen (f.eks. via `watson-setup`-skillen) —
Homebrew skriver utenfor det sandboxen har skrivetilgang til. Kjør skriptet
i en vanlig terminal for å få tools auto-installert, eller installer manuelt.

### 3. Klon alle Watson-repoer

```bash
./scripts/clone-repos.sh
```

Kloner alle repoer i porteføljen til `repos/`.
Idempotent — kjør igjen for å oppdatere eksisterende repoer med `git pull`.

### 4. Opprett kind-kluster

```bash
./scripts/setup-kind.sh
```

Oppretter kind-klusteret `watson` og setter kubectl-kontekst.
Idempotent — trygt å kjøre flere ganger.

### 5. Start lokalmiljøet

```bash
./start
```

Åpne [Tilt UI](http://localhost:10350) for status og logger.

---

## Verifiser at alt fungerer

Når Tilt er oppe, sjekk følgende:

1. Tilt UI viser grønne ressurser → [localhost:10350](http://localhost:10350)
2. Health-endepunkt svarer → [localhost:8080/actuator/health](http://localhost:8080/actuator/health)
3. Swagger UI er tilgjengelig → [localhost:8080/swagger-ui/index.html](http://localhost:8080/swagger-ui/index.html)

---

## Feilsøking: `./gradlew` feiler i cplt-sandboxen

Symptom: `./gradlew` (i `watson-admin-api` e.l.) feiler med enten

```
/Users/<deg>/.jenv/shims/java: line 21: /opt/homebrew/Cellar/jenv/<versjon>/libexec/libexec/jenv: No such file or directory
```

eller

```
dyld[...]: Library not loaded: @rpath/libjli.dylib
... (file system sandbox blocked open())
```

**Årsak 1 — ødelagt jenv-shim:** `jenv`s shim for `java` peker på en hardkodet
Homebrew-Cellar-versjon. Når `brew upgrade jenv` fjerner den gamle mappen, blir
shimmet værende og peker på en sti som ikke lenger finnes. Fiks **utenfor**
sandboxen (cplt gjør `~/.jenv` skrivebeskyttet):

```bash
jenv rehash --force
```

**Årsak 2 — cplt-sandboxen blokkerer lesing av JDK-filer:** selv med et
korrekt shim kan sandboxen nekte lesing av `lib/libjli.dylib` inni JDK-er
under `~/Library/Java/JavaVirtualMachines/...`, fordi `~/Library` som helhet
ikke er i sandboxens `allow.read`. Symptomet er da `Operation not permitted`/
`file system sandbox blocked open()`.

Tiltak, i prioritert rekkefølge:

1. **Foretrukket:** Sett `org.gradle.java.home` til en Homebrew-installert JDK
   (f.eks. `/opt/homebrew/opt/openjdk@21`, eller kjør med `JAVA_HOME` satt til
   en `/opt/homebrew/Cellar/...`-JDK) i stedet for å gå via jenv/`~/Library`.
   Homebrew-installerte JDK-er ligger utenfor de vanlige sandbox-blokkerte
   stiene.
2. Legg de spesifikke JDK-stiene til i `allow.read` i cplt-konfigurasjonen
   (`cplt settings`, kjøres utenfor sandbox) hvis du må bruke en jenv-styrt
   JDK under `~/Library/Java/JavaVirtualMachines`.
3. Kjør `./scripts/doctor.sh` etter endringer — den fanger opp begge
   feilklassene og gir konkret handling.

---

## Feilsøking: Testcontainers finner ikke Docker (Rancher Desktop)

Symptom: integrasjonstester i `watson-admin-api` (alt som arver `PostgresIntegrationTestSupport`) feiler
med `ApplicationContext failure threshold (1) exceeded`. Rotårsaken står lenger ned i testrapporten
(`build/test-results/test/*.xml`), og er en av disse:

```
Could not find a valid Docker environment
UnixSocketClientProviderStrategy: NoSuchFileException (/var/run/docker.sock)
```

eller, etter at første feil er rettet:

```
Container startup failed for image testcontainers/ryuk
error while creating mount source path '/Users/<deg>/.rd/docker.sock': operation not supported
```

**Årsak:** Rancher Desktop legger Docker-socketen på `~/.rd/docker.sock`, ikke på `/var/run/docker.sock`
som Testcontainers leter etter. `docker context` brukes ikke av Testcontainers. Ryuk (Testcontainers sin
opprydder) monterer socketen inn i en container og trenger stien slik den ser ut inni Rancher-VM-en.

**Fiks, en gang per maskin (kjør utenfor cplt-sandboxen):**

1. Opprett `~/.testcontainers.properties` med:

   ```properties
   docker.host=unix:///Users/<deg>/.rd/docker.sock
   ```

   Bytt `<deg>` med brukernavnet ditt. `~` fungerer ikke i verdien.

2. Sett miljøvariabelen for Ryuk i `~/.zshrc`:

   ```bash
   export TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock
   ```

   Dette er bare en miljøvariabel. Nøkkelen finnes ikke i `.testcontainers.properties`.

3. Åpne et nytt skall. IntelliJ må startes på nytt fra et skall som har variabelen, ellers ser den
   den ikke. Verifiser med:

   ```bash
   cd repos/watson-admin-api
   ./gradlew test --tests '*DokumentKommentarServiceIntegrationTest'
   ```

> **Merk:** cplt-sandboxen blokkerer Docker-socketen. Testene som starter Postgres i container kan derfor
> ikke kjøres av agenten, bare av deg i en vanlig terminal.

---

## Fallback: docker-compose

`watson-admin-api` har en `docker-compose.yml` som alternativ til Tilt:

```bash
cd repos/watson-admin-api
docker-compose up
```

> **Merk:** `docker-compose` er ikke lenger primær kjøremetode og støtter ikke full portefølje.
> Bruk Tilt for å kjøre hele Watson-miljøet lokalt.

---

## Neste steg

- [docs/LOKALMILJO.md](LOKALMILJO.md) — teknisk info om lokalmiljøet (porter, token, hybrid-modus)
- [docs/onboarding/sjekkliste.md](onboarding/sjekkliste.md) — full sjekkliste for nye utviklere
