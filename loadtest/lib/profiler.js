/**
 * Lastprofiler. Velg med PROFIL=baseline|last|stress|utholdenhet.
 * VU-ene fordeles på rollene etter ANDEL. Tallene gjelder totalt antall samtidige brukere.
 */
const ANDEL = { les: 0.8, skriv: 0.15, leder: 0.05 };

const PROFILER = {
  baseline: [
    { duration: "1m", target: 10 },
    { duration: "10m", target: 10 },
    { duration: "1m", target: 0 },
  ],
  last: [
    { duration: "5m", target: 100 },
    { duration: "20m", target: 100 },
    { duration: "2m", target: 0 },
  ],
  stress: [
    { duration: "5m", target: 100 },
    { duration: "5m", target: 200 },
    { duration: "5m", target: 300 },
    { duration: "5m", target: 300 },
    { duration: "2m", target: 0 },
  ],
  // Tokens fra azure-token-generator varer ca. 1 time. Hold kjøringen under det.
  utholdenhet: [
    { duration: "5m", target: 100 },
    { duration: "45m", target: 100 },
    { duration: "2m", target: 0 },
  ],
};

export function stages(profil, rolle) {
  const trinn = PROFILER[profil];
  if (!trinn) {
    throw new Error(`Ukjent PROFIL "${profil}". Gyldige: ${Object.keys(PROFILER).join(", ")}`);
  }
  return trinn.map((t) => ({
    duration: t.duration,
    target: t.target === 0 ? 0 : Math.max(1, Math.round(t.target * ANDEL[rolle])),
  }));
}

export const terskler = {
  http_req_failed: ["rate<0.01"],
  "http_req_duration{type:les}": ["p(95)<500"],
  "http_req_duration{type:skriv}": ["p(95)<1500"],
  checks: ["rate>0.99"],
};
