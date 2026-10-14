import { brukerMedRolle, tilfeldig } from "../lib/config.js";
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

// Én bruker, én runde gjennom alle flytene. Verifiserer tokens, tilganger og skript før lasttest.
export const options = {
  vus: 1,
  iterations: 1,
  thresholds: {
    checks: ["rate==1"],
  },
};

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
  registrerOgBehandleSak(saksbehandler);
  lederVisning(brukerMedRolle("leder"));
}
