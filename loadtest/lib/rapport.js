import { textSummary } from "https://jslib.k6.io/k6-summary/0.1.0/index.js";
import { KALLNAVN } from "./klient.js";

/**
 * Lager en markdown-rapport etter kjøringen, skrevet for både utviklere og andre.
 * lasttest.sh setter RAPPORT til filnavnet uten endelse. Uten RAPPORT skrives bare terminaloppsummeringen.
 */

/**
 * Terskler som alltid holder. De finnes bare for at k6 skal lage tidsserier per kall,
 * så rapporten kan vise responstid og antall for hvert kall.
 */
export function kallTerskler() {
  const terskler = {};
  for (const navn of KALLNAVN) {
    terskler[`http_req_duration{name:${navn}}`] = ["max>=0"];
    terskler[`http_reqs{name:${navn}}`] = ["count>=0"];
  }
  return terskler;
}

const desimal = (n, d) => n.toFixed(d).replace(/\.0+$/, "").replace(".", ",");
const tid = (ms) => {
  if (ms >= 1000) return `${desimal(ms / 1000, 2)} s`;
  return ms >= 10 ? `${Math.round(ms)} ms` : `${desimal(ms, 1)} ms`;
};
const prosent = (r) => `${desimal(r * 100, 1)} %`;
const heltall = (n) => String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, " ");

function varighet(ms) {
  const s = Math.round(ms / 1000);
  if (s < 1) return "under 1 sekund";
  if (s < 60) return `${s} sekunder`;
  const min = Math.floor(s / 60);
  return s % 60 === 0 ? `${min} minutter` : `${min} min ${s % 60} s`;
}

function tidspunkt() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
}

const OPERATOR = { "<": "under", "<=": "høyst", ">": "over", ">=": "minst", "==": "nøyaktig" };
const TYPE = { les: "lesekallene", skriv: "skrivekallene" };

/** Gjør en k6-terskel som `http_req_duration{type:les}: p(95)<500` om til en rad folk forstår. */
function beskrivTerskel(nokkel, uttrykk, metrikk) {
  const m = uttrykk.match(/^\s*([a-z]+(?:\(\d+(?:\.\d+)?\))?)\s*(<=|>=|==|<|>)\s*([\d.]+)\s*$/);
  if (!m) return { hva: `${nokkel}: ${uttrykk}`, krav: "", malt: "" };
  const [, stat, op, grenseTekst] = m;
  const grense = Number(grenseTekst);
  const verdi = metrikk.values[stat];
  const base = nokkel.split("{")[0];
  const type = (nokkel.match(/\{type:(\w+)\}/) || [])[1];

  if (base === "http_req_duration") {
    const pst = (stat.match(/p\((\d+(?:\.\d+)?)\)/) || [])[1];
    const hvem = TYPE[type] || "kallene";
    return {
      hva: pst ? `${pst} % av ${hvem} svarte innen` : `Responstid (${stat}) for ${hvem}`,
      krav: `${OPERATOR[op]} ${tid(grense)}`,
      malt: tid(verdi),
    };
  }
  if (metrikk.type === "rate") {
    const hva = { http_req_failed: "Kall som feilet", checks: "Godkjente sjekker" }[base] || nokkel;
    return { hva, krav: `${OPERATOR[op]} ${prosent(grense)}`, malt: prosent(verdi) };
  }
  if (metrikk.type === "counter") {
    const hva =
      {
        avvist_rate_limit_app: "Svar 429 fra søkegrensen i appen",
        avvist_rate_limit_ingress: "Svar 503 fra rate limit i ingress",
      }[base] || nokkel;
    return { hva, krav: `${OPERATOR[op]} ${heltall(grense)}`, malt: heltall(verdi || 0) };
  }
  return { hva: nokkel, krav: `${op} ${grense}`, malt: String(verdi) };
}

function samleSjekker(gruppe, sjekker = {}) {
  for (const c of gruppe.checks || []) {
    const s = sjekker[c.name] || { ok: 0, feil: 0 };
    s.ok += c.passes;
    s.feil += c.fails;
    sjekker[c.name] = s;
  }
  for (const g of gruppe.groups || []) samleSjekker(g, sjekker);
  return sjekker;
}

export function lagRapport(data) {
  const m = data.metrics;
  const verdi = (navn, stat) => (m[navn] ? m[navn].values[stat] : undefined);

  const terskler = [];
  for (const [nokkel, metrikk] of Object.entries(m)) {
    if (!metrikk.thresholds || nokkel.includes("{name:")) continue;
    for (const [uttrykk, resultat] of Object.entries(metrikk.thresholds)) {
      terskler.push({ ok: resultat.ok, ...beskrivTerskel(nokkel, uttrykk, metrikk) });
    }
  }
  const brutt = terskler.filter((t) => !t.ok).length;

  const antallKall = verdi("http_reqs", "count") || 0;
  const feilrate = verdi("http_req_failed", "rate") || 0;
  const median = verdi("http_req_duration", "med") || 0;
  const p95 = verdi("http_req_duration", "p(95)") || 0;
  // k6 måler brukere hvert sekund, så kjøringer under ett sekund har ingen måling.
  const brukere = verdi("vus", "max") || verdi("vus_max", "max") || 0;
  const hvem =
    brukere === 0 ? "Testen" : brukere === 1 ? "Én bruker" : `Opptil ${heltall(brukere)} samtidige brukere`;
  const kjoretid = data.state.testRunDurationMs;
  const sjekker = samleSjekker(data.root_group);

  const scenario = __ENV.SCENARIO || "ukjent scenario";
  // Bare watson-sak bruker lastprofilene.
  const profil = scenario === "watson-sak" && __ENV.PROFIL ? ` (${__ENV.PROFIL})` : "";
  const linjer = [];
  const ut = (s = "") => linjer.push(s);

  ut(`# Lasttest av Watson Sak: ${scenario}${profil}`);
  ut();
  if (brutt === 0) {
    ut(`**✅ Bestått.** ${terskler.length} av ${terskler.length} krav ble oppfylt.`);
  } else {
    ut(`**❌ Ikke bestått.** ${brutt} av ${terskler.length} krav ble ikke oppfylt. Se «Krav» under.`);
  }
  ut();
  ut(
    `${hvem} gjorde ${heltall(antallKall)} kall på ${varighet(kjoretid)}. ` +
      `${prosent(1 - feilrate)} av kallene lyktes. Halvparten av kallene svarte innen ${tid(median)}, ` +
      `og 95 % svarte innen ${tid(p95)}.`,
  );
  ut();
  ut("| | |");
  ut("|---|---|");
  ut(`| Tidspunkt | ${tidspunkt()} |`);
  ut(`| Mål | \`${__ENV.BASE_URL || "https://watson-admin-api.intern.dev.nav.no"}\` |`);
  ut(`| Varighet | ${varighet(kjoretid)} |`);
  ut(`| Samtidige brukere (maks) | ${brukere ? heltall(brukere) : "ikke målt"} |`);
  ut(`| Kall totalt | ${heltall(antallKall)} (${(antallKall / (kjoretid / 1000)).toFixed(1).replace(".", ",")} per sekund) |`);
  ut(`| Kall som lyktes | ${prosent(1 - feilrate)} |`);
  ut(`| Responstid, median | ${tid(median)} |`);
  ut(`| Responstid, 95 % innen | ${tid(p95)} |`);
  ut(`| Tregeste kall | ${tid(verdi("http_req_duration", "max") || 0)} |`);
  ut();

  ut("## Krav");
  ut();
  ut("| | Hva vi måler | Krav | Målt |");
  ut("|---|---|---|---|");
  for (const t of terskler) ut(`| ${t.ok ? "✅" : "❌"} | ${t.hva} | ${t.krav} | ${t.malt} |`);
  ut();

  const kall = KALLNAVN.map((navn) => {
    const d = m[`http_req_duration{name:${navn}}`];
    const n = m[`http_reqs{name:${navn}}`];
    if (!d || !n || !n.values.count) return null;
    const s = sjekker[`${navn} ok`] || { feil: 0 };
    return { navn, antall: n.values.count, med: d.values.med, p95: d.values["p(95)"], maks: d.values.max, feil: s.feil };
  })
    .filter(Boolean)
    .sort((a, b) => b.p95 - a.p95);

  if (kall.length > 0) {
    ut("## Responstid per kall");
    ut();
    ut("Tregeste først. Kall som feilet minst én gang, er merket med ❌.");
    ut();
    ut("| Kall | Antall | Median | 95 % innen | Tregeste | Feilet |");
    ut("|---|--:|--:|--:|--:|--:|");
    for (const k of kall) {
      const feil = k.feil > 0 ? `❌ ${heltall(k.feil)}` : "0";
      ut(`| ${k.navn} | ${heltall(k.antall)} | ${tid(k.med)} | ${tid(k.p95)} | ${tid(k.maks)} | ${feil} |`);
    }
    ut();
  }

  const feilede = Object.entries(sjekker).filter(([, s]) => s.feil > 0);
  if (feilede.length > 0) {
    ut("## Sjekker som feilet");
    ut();
    ut("Statuskode og feilmelding står i terminalen fra kjøringen. Søk etter samme tidspunkt i Loki for å se feilen i backend.");
    ut();
    ut("| Sjekk | Feilet | Av |");
    ut("|---|--:|--:|");
    for (const [navn, s] of feilede) ut(`| ${navn} | ${heltall(s.feil)} | ${heltall(s.ok + s.feil)} |`);
    ut();
  }

  const app = verdi("avvist_rate_limit_app", "count") || 0;
  const ingress = verdi("avvist_rate_limit_ingress", "count") || 0;
  if (app > 0 || ingress > 0) {
    ut("## Avvist av rate limit");
    ut();
    ut(`- ${heltall(app)} kall fikk 429 fra søkegrensen i appen (per Nav-ident).`);
    ut(`- ${heltall(ingress)} kall fikk 503 fra ingress (per IP-adresse).`);
    ut();
  }

  ut("## Ordliste");
  ut();
  ut("- **Kall**: én forespørsel fra Watson Sak til backend, for eksempel «hent sak» eller «opprett mappe».");
  ut("- **Samtidige brukere**: simulerte saksbehandlere som klikker seg gjennom Watson Sak med pauser, som ekte brukere.");
  ut("- **Median**: halvparten av kallene var raskere enn dette.");
  ut("- **95 % innen** (p95): 95 av 100 kall var raskere enn dette. Tallet viser hva de som venter lengst, opplever.");
  ut("- **ms**: millisekunder. 1 000 ms er ett sekund.");
  ut("- **Sjekk**: testen kontrollerer at hvert svar har riktig status. Et kall som feiler, gir en feilet sjekk.");
  ut();

  return linjer.join("\n");
}

export function handleSummary(data) {
  // Tidsseriene per kall hører hjemme i rapporten, ikke i terminalen.
  const metrics = {};
  for (const [nokkel, metrikk] of Object.entries(data.metrics)) {
    if (!nokkel.includes("{name:")) metrics[nokkel] = metrikk;
  }
  const resultat = { stdout: textSummary({ ...data, metrics }, { indent: " ", enableColors: true }) };
  if (__ENV.RAPPORT) resultat[`${__ENV.RAPPORT}.md`] = lagRapport(data);
  return resultat;
}
