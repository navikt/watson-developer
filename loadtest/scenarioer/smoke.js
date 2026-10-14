import { brukerMedRolle, harRolle, testpersoner, tilfeldig } from "../lib/config.js";
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
import { handleSummary, kallTerskler } from "../lib/rapport.js";

// Én bruker, én runde gjennom alle flytene. Verifiserer tokens, tilganger og skript før lasttest.
// Holder med én saksbehandler. Uten leder-token eller TESTPERSONER hoppes de flytene over.
export const options = {
  vus: 1,
  iterations: 1,
  thresholds: {
    checks: ["rate==1"],
    ...kallTerskler(),
  },
};

export { handleSummary };

// Setup henter saker med samme saksbehandler som åpner dem, så tilgangen er lik.
export function setup() {
  return { sakIder: hentSakIder(brukerMedRolle("saksbehandler"), 1) };
}

export default function (data) {
  const saksbehandler = brukerMedRolle("saksbehandler");
  forside(saksbehandler);
  mineSaker(saksbehandler);
  alleSaker(saksbehandler);
  if (data.sakIder.length > 0) {
    const sak = sakDetalj(saksbehandler, tilfeldig(data.sakIder));
    dokumentVisning(saksbehandler, sak);
  }
  if (testpersoner.length > 0) {
    registrerOgBehandleSak(saksbehandler);
  } else {
    console.warn("TESTPERSONER er ikke satt. Hopper over skriveflyten.");
  }
  if (harRolle("leder")) {
    lederVisning(brukerMedRolle("leder"));
  } else {
    console.warn("Ingen leder i tokenfila. Hopper over lederflyten.");
  }
}
