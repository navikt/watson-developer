---
name: repo-activity-research
description: Oppsummer endringer i alle Watson-repoer for en tidsperiode, med siste arbeidsdag som standard
license: MIT
compatibility: macOS med Git og GitHub CLI
metadata:
  domain: development
  tags: repo aktivitet commits pull requests arbeidsdag oppsummering
---

# Repoaktivitet

Lag en kort oppsummering av hva som har skjedd i Watson-repoene i en valgt
tidsperiode. Standardperioden er siste arbeidsdag, altså forrige mandag til
fredag som ikke er i dag. Hvis brukeren oppgir en periode, bruker du den i
stedet.

Skillen skal kjøres fra roten av `watson-developer`.

## Tolk tidsperioden

- Uten periode: bruk siste arbeidsdag i lokal tid.
- «I dag»: bruk fra midnatt i dag til nå.
- «Denne uka»: bruk mandag i inneværende uke til nå.
- «Siste uke»: bruk mandag til fredag i forrige uke.
- Eksplisitte datoer: godta `YYYY-MM-DD`, for eksempel `2026-09-21 til
  2026-09-23`.
- Bruk et halvåpent intervall når du kjører Git: `since` er starten på perioden,
  mens `until` er starten på dagen etter sluttdatoen. Da blir hele sluttdagen
  med.

Avklar ikke perioden med brukeren når formuleringen er entydig. Vis alltid
perioden øverst i rapporten.

## Finn repoene

Bruk repo-lista i `scripts/clone-repos.sh` som fasit for sibling-repoene.
Rapporter `watson-developer` og hvert repo i lista. Bruk repoets katalognavn
som navn. For hvert forventet repo:

1. Finn katalogen direkte under `repos/`.
2. Rapporter katalogen som manglende hvis den ikke finnes.
3. Rapporter katalogen som ugyldig hvis den finnes, men mangler `.git`.
4. Hopp over repoet i aktivitetsinnhentingen når katalogen mangler eller er
   ugyldig.

Ta også med andre Git-repoer som faktisk finnes direkte under `repos/`, men
marker dem som uventede.

Kjør først:

```bash
git status --short --branch
command -v gh
gh auth status
```

`git status` er bare en kontroll og skal ikke føre til checkout, reset eller
andre endringer. Hvis `gh` mangler eller ikke er innlogget, fortsett med lokal
Git-data og si tydelig at GitHub-data ikke kunne hentes.

## Hent aktivitet

Kjør kommandoene for hvert repo. Bruk `--no-merges` for commit-lista, og ikke
vis commit-meldinger som bare er automatiske merge- eller dependabot-oppdateringer
som hovedpunkter.

```bash
git -C "$repo" log --since="$since" --until="$until" --no-merges \
  --date=iso --pretty=format:'%H%x09%ad%x09%an%x09%s'
```

For hvert repo med aktivitet:

1. Gruppér commits som hører sammen i én endring når commit-meldingene og
   filene viser at de er samme arbeid.
2. Hent berørte filer for de relevante commitene med
   `git -C "$repo" show --stat --oneline --summary <sha>`.
3. Bruk `git -C "$repo" remote get-url origin` for å lage GitHub-lenker. Ikke
   vis credentials fra remote-URL-er.

Når `gh` er tilgjengelig og origin peker til GitHub, hent PR-er som ble åpnet
eller merged i perioden:

```bash
gh pr list --repo OWNER/REPO --state all \
  --search "created:YYYY-MM-DD..YYYY-MM-DD OR merged:YYYY-MM-DD..YYYY-MM-DD" \
  --limit 100 \
  --json number,title,state,author,createdAt,mergedAt,url
```

Hvis søket med `OR` ikke fungerer i den installerte `gh`-versjonen, kjør to
separate søk, ett for `created:` og ett for `merged:`, og dedupliser på
PR-nummer. Hvis et søk returnerer 100 treff, marker PR-resultatet som mulig
avkortet i rapporten. Ikke dikt opp PR-data når kommandoen feiler.

## Skriv rapporten

Skriv rapporten direkte i svaret, ikke til en fil. Bruk denne strukturen:

```markdown
# Repoaktivitet: YYYY-MM-DD til YYYY-MM-DD

## Kort oppsummert

Én til tre setninger om de viktigste endringene på tvers av repoene.

## Per repo

### repo-navn

- **Endringer:** Hva som ble gjort, med lenke til commit eller PR.
- **PR-er:** Åpnet eller merged PR-er i perioden, hvis GitHub-data er tilgjengelig.
- **Omfang:** Kort beskrivelse av berørte områder eller filer når det gir verdi.

### repo uten aktivitet

Ingen commits i perioden.

## Oppfølging

Bare ta med denne delen når rapporten viser feil, manglende repoer, usikre
resultater eller aktivitet som trenger oppfølging.
```

Regler for innholdet:

- Start med det viktigste. Ikke list alle commits ukritisk.
- Skill mellom «ingen aktivitet» og «kunne ikke hente data».
- Ta med antall commits og PR-er når det gjør rapporten lettere å skanne.
- Bruk commit- og PR-lenker når de finnes.
- Ikke vis fødselsnummer, tokens, secrets eller andre sensitive verdier fra
  commit-meldinger, diff-er eller remote-URL-er.
- Ikke les eller rapporter innholdet i filer som ikke trengs for å beskrive
  aktiviteten.
- Behold usikkerhet: marker opplysninger som ikke kunne verifiseres lokalt
  eller via GitHub.

## Feilhåndtering

- Mangler et forventet repo eller `.git`: noter repoet under «Oppfølging».
- Finnes det et uventet repo direkte under `repos/`, noter det under
  «Oppfølging» og ta det med i rapporten.
- Git-kommando feiler i ett repo: fortsett med de andre repoene og noter
  feilen med repo-navn og kommandoens relevante feilmelding.
- GitHub API eller `gh` feiler: bruk lokal Git-data, og noter at PR-data kan
  mangle.
- Ikke bruk `git pull`, `git checkout`, `git reset`, `git clean` eller andre
  kommandoer som endrer arbeidskopien.
