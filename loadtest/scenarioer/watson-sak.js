import { brukerForVu, brukerMedRolle, harRolle, tilfeldig } from "../lib/config.js";
import {
  alleSaker,
  dokumentVisning,
  forside,
  hentSakIder,
  lederVisning,
  mineSaker,
  registrerOgBehandleSak,
  sakDetalj,
} from "../lib/flyter.js";
import { stages, terskler } from "../lib/profiler.js";
import { handleSummary, kallTerskler } from "../lib/rapport.js";

const PROFIL = __ENV.PROFIL || "baseline";
const MED_LEDER = harRolle("leder");

function scenario(rolle, exec) {
  return {
    executor: "ramping-vus",
    startVUs: 0,
    stages: stages(PROFIL, rolle, MED_LEDER),
    gracefulRampDown: "30s",
    exec,
    tags: { rolle },
  };
}

export const options = {
  scenarios: {
    saksbehandler_les: scenario("les", "saksbehandlerLes"),
    saksbehandler_skriv: scenario("skriv", "saksbehandlerSkriv"),
    ...(MED_LEDER ? { leder: scenario("leder", "leder") } : {}),
  },
  thresholds: { ...terskler, ...kallTerskler() },
  // Unngå at hver unike URL blir en egen tidsserie.
  systemTags: ["status", "method", "name", "group", "scenario", "check", "error_code", "expected_response"],
};

export { handleSummary };

export function setup() {
  if (!MED_LEDER) console.warn("Ingen leder i tokenfila. Hopper over lederflyten, og lederandelen går til lesing.");
  const sakIder = hentSakIder(brukerMedRolle("saksbehandler"));
  if (sakIder.length === 0) {
    throw new Error("Fant ingen saker. Seed dev med saker testidentene har tilgang til før kjøring.");
  }
  return { sakIder };
}

/** Én økt: innom forsiden av og til, mine saker, én sak med dokument, av og til alle saker. */
export function saksbehandlerLes(data) {
  const bruker = brukerForVu("saksbehandler");
  if (Math.random() < 0.3) forside(bruker);
  mineSaker(bruker);
  const sak = sakDetalj(bruker, tilfeldig(data.sakIder));
  if (Math.random() < 0.5) dokumentVisning(bruker, sak);
  if (Math.random() < 0.3) alleSaker(bruker);
}

export function saksbehandlerSkriv() {
  const bruker = brukerForVu("saksbehandler");
  registrerOgBehandleSak(bruker);
  mineSaker(bruker);
}

export function leder() {
  lederVisning(brukerForVu("leder"));
}
