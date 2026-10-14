import { sleep } from "k6";
import { brukere, testpersoner } from "../lib/config.js";
import { sok } from "../lib/klient.js";
import { handleSummary, kallTerskler } from "../lib/rapport.js";

/**
 * Bekrefter at SokRateLimitFilter slår inn (30 burst, 120 per time per Nav-ident) og at appen
 * svarer 429 uten følgefeil. Bruker opp søkekvoten til identen i opptil en time,
 * så kjør med en egen ident: SOK_IDENT=<navIdent>.
 */
const ANTALL = Number(__ENV.ANTALL_SOK || 40);

export const options = {
  vus: 1,
  iterations: 1,
  thresholds: {
    avvist_rate_limit_app: ["count>0"],
    // 503 her betyr at ingress-grensen slo inn først, ikke appens grense.
    avvist_rate_limit_ingress: ["count==0"],
    // 429 regnes som forventet svar. Alt annet enn 2xx og 429, for eksempel 401 eller 5xx, feiler.
    http_req_failed: ["rate==0"],
    checks: ["rate==1"],
    ...kallTerskler(),
  },
};

export { handleSummary };

export default function () {
  let bruker = null;
  for (const b of brukere) {
    if (b.navIdent === __ENV.SOK_IDENT) bruker = b;
  }
  if (!bruker) throw new Error("Sett SOK_IDENT til en navIdent som finnes i tokenfila.");
  if (testpersoner.length === 0) throw new Error("TESTPERSONER mangler.");

  for (let i = 0; i < ANTALL; i++) {
    sok(bruker, "/api/v1/kontrollsaker/sok?page=1&size=20", "sok person", {
      personIdent: testpersoner[i % testpersoner.length],
    });
    // Holder oss godt under ingress-grensen på 20 req/s.
    sleep(0.2);
  }
}
