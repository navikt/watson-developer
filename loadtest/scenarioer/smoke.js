import { brukere, brukerForVu, tilfeldig } from "../lib/config.js";
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

export function setup() {
  return { sakIder: hentSakIder(brukere[0], 1) };
}

export default function (data) {
  const saksbehandler = brukerForVu("saksbehandler");
  forside(saksbehandler);
  mineSaker(saksbehandler);
  alleSaker(saksbehandler);
  if (data.sakIder.length > 0) {
    const sak = sakDetalj(saksbehandler, tilfeldig(data.sakIder));
    dokumentVisning(saksbehandler, sak);
  }
  registrerOgBehandleSak(saksbehandler);
  lederVisning(brukerForVu("leder"));
}
