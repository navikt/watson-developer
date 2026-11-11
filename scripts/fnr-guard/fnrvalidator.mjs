// 🔴 Rød sone: avgjør om et 11-sifret tall er et gyldig identnummer.
//
// Kopiert fra @navikt/fnrvalidator v2.2.1 (dist/validator.js), kun idnr().
// Kilde: https://github.com/navikt/fnrvalidator
// Kopiert inn for at hooken skal virke uten npm-installasjon.
// Ved oppdatering: sammenlign med ny versjon av validator.ts og kjør testene.
//
// The MIT License
// Copyright 2008 NAV (Arbeids- og velferdsdirektoratet) - The Norwegian Labour
// and Welfare Administration
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

const ELLEVE_SIFFER = /^\d{11}$/;

export function getType(digits) {
  const nrs = digits.split("").map(Number);
  if (nrs[0] >= 4 && nrs[2] >= 8) return "dnr-and-tnr";
  if (nrs[0] >= 4 && nrs[2] >= 4) return "dnr-and-hnr";
  if (nrs[0] >= 4) return "dnr";
  if (nrs[2] >= 8) return "tnr";
  if (nrs[2] >= 4) return "hnr";
  return "fnr";
}

export function idnr(digits) {
  if (!ELLEVE_SIFFER.test(digits)) {
    return { status: "invalid", reasons: ["fnr, dnr or hnr must consist of 11 digits"] };
  }
  const type = getType(digits);
  const feil = [...checksums(digits), ...birthdate(digits, type)];
  return feil.length === 0 ? { status: "valid", type } : { status: "invalid", reasons: feil };
}

function checksums(digits) {
  const nrs = digits.split("").map(Number);
  const k1Sum =
    3 * nrs[0] + 7 * nrs[1] + 6 * nrs[2] + 1 * nrs[3] + 8 * nrs[4] +
    9 * nrs[5] + 4 * nrs[6] + 5 * nrs[7] + 2 * nrs[8];

  // Ny standard fra 2032: k1 kan beregnes med rest 0, 1, 2 eller 3.
  // https://skatteetaten.github.io/folkeregisteret-api-dokumentasjon/nytt-fodselsnummer-fra-2032/
  const gyldigeK1 = [];
  for (let rest = 0; rest <= 3; rest++) {
    let k1 = 11 + rest - (k1Sum % 11);
    if (k1 > 10) k1 -= 11;
    if (k1 !== 10) gyldigeK1.push(k1);
  }
  const k1 = nrs[9];
  if (!gyldigeK1.includes(k1)) return ["checksums don't match"];

  let k2 =
    11 -
    ((5 * nrs[0] + 4 * nrs[1] + 3 * nrs[2] + 2 * nrs[3] + 7 * nrs[4] +
      6 * nrs[5] + 5 * nrs[6] + 4 * nrs[7] + 3 * nrs[8] + 2 * k1) % 11);
  if (k2 === 11) k2 = 0;
  return k2 < 10 && k2 === nrs[10] ? [] : ["checksums don't match"];
}

function birthdate(digits, type) {
  const forste = () => Number(digits.substring(0, 1)) - 4;
  const tredje = (minus) => Number(digits.substring(2, 3)) - minus;
  if (type === "dnr") digits = forste() + digits.substring(1);
  else if (type === "hnr") digits = digits.substring(0, 2) + tredje(4) + digits.substring(3);
  else if (type === "tnr") digits = digits.substring(0, 2) + tredje(8) + digits.substring(3);
  else if (type === "dnr-and-hnr") digits = forste() + digits.substring(1, 2) + tredje(4) + digits.substring(3);
  else if (type === "dnr-and-tnr") digits = forste() + digits.substring(1, 2) + tredje(8) + digits.substring(3);

  const day = Number(digits.substring(0, 2));
  const month = Number(digits.substring(2, 4));
  const yearString = digits.substring(4, 6);
  const year = yearString === "00" ? 2000 : Number(yearString);
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCMonth() + 1 === month && date.getUTCDate() === day ? [] : ["invalid date"];
}
