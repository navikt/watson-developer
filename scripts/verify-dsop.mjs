import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const { chromium, expect } = createRequire(new URL('../repos/dsop-kontroll-frontend/package.json', import.meta.url))('@playwright/test');
const frontend = 'http://127.0.0.1:8000';
const bankFrontend = 'http://127.0.0.1:3000';
const wiremock = 'http://127.0.0.1:7165';
const dokarkivPath = '/dokarkiv/rest/journalpostapi/v1/journalpost';
const bank = { orgnr: '000000000', navn: 'Syntetisk Bank' };
const attachment = fileURLToPath(new URL('../mocks/dsop/__files/syntetisk.pdf', import.meta.url));
const dbPortFile = new URL('../.local/dsop-db-port', import.meta.url);
const assert = (condition, message) => { if (!condition) throw new Error(message); };
const body = (event) => JSON.parse(event.request.body);
const path = (event) => new URL(event.request.url, wiremock).pathname;
const dokarkiv = (event, type) => event.request.method === 'POST' && path(event) === dokarkivPath && body(event).journalpostType === type;
const bankRequest = (event) => body(event).avsenderMottaker?.id === bank.orgnr;
const pdfVariants = (event) => body(event).dokumenter.flatMap((doc) => doc.dokumentvarianter).filter((variant) => variant.filtype === 'PDF');
const startsWithPdf = (base64) => Buffer.from(base64 ?? '', 'base64').subarray(0, 5).toString('ascii') === '%PDF-';

async function localJson(url) {
    const response = await fetch(url, { signal: AbortSignal.timeout(10_000), redirect: 'error' });
    assert(response.ok, `Lokal tjeneste svarte med HTTP ${response.status}`);
    return response.json();
}

async function frontendFetch(page, path, init) {
    return page.evaluate(async ({ path, init }) => {
        const response = await fetch(path, { ...init, credentials: 'same-origin', redirect: 'error' });
        let payload = null;
        try { payload = await response.json(); } catch { /* Do not expose response bodies. */ }
        return { status: response.status, payload };
    }, { path, init });
}

function dbRow(skjemaId) {
    const port = readFileSync(dbPortFile, 'utf8').trim();
    assert(/^\d{1,5}$/.test(port) && Number(port) > 0 && Number(port) <= 65535, 'Ugyldig .local/dsop-db-port');
    const env = { ...process.env, PGCONNECT_TIMEOUT: '3' };
    for (const key of ['PGHOSTADDR', 'PGSERVICE', 'PGSERVICEFILE', 'PGOPTIONS', 'PGPASSWORD', 'PGPASSFILE']) delete env[key];
    const output = execFileSync('psql', [
        '-X', '--no-password', '-v', 'ON_ERROR_STOP=1', '-h', '127.0.0.1', '-p', port,
        '-U', 'postgres', '-d', 'postgres', '-A', '-t', '-F', '\t',
        '-c', 'SELECT id, status, archive_reference FROM altinnskjema',
    ], { encoding: 'utf8', env, stdio: ['ignore', 'pipe', 'pipe'] });
    const row = output.trim().split(/\r?\n/).map((line) => line.split('\t')).find(([id]) => id === skjemaId);
    assert(row, 'Fant ikke skjemaet i altinnskjema-tabellen');
    return { status: row[1], archiveReference: row[2] };
}

async function main() {
    const browser = await chromium.launch({ headless: true });
    const context = await browser.newContext();
    const errors = [];
    await context.route('**/*', async (route) => {
        const url = new URL(route.request().url());
        if (['http:', 'https:'].includes(url.protocol) && !['127.0.0.1', 'localhost'].includes(url.hostname)) {
            errors.push(`Blokkerte ekstern host: ${url.hostname}`);
            return route.abort('blockedbyclient');
        }
        return route.continue();
    });
    const trackErrors = (page) => {
        page.on('pageerror', () => errors.push('JavaScript-feil i nettleseren'));
        page.on('requestfailed', (request) => errors.push(`Nettverksfeil: ${new URL(request.url()).pathname}`));
        page.on('response', (response) => {
            if (response.status() >= 400) errors.push(`HTTP ${response.status()}: ${new URL(response.url()).pathname}`);
        });
    };

    try {
        const frontendPage = await context.newPage();
        trackErrors(frontendPage);
        await frontendPage.goto(frontend, { waitUntil: 'domcontentloaded' });

        const initialJournal = (await localJson(`${wiremock}/__admin/requests`)).requests;
        assert(Array.isArray(initialJournal), 'WireMock-journal mangler serve events');
        const initialRequestIds = new Set(initialJournal.map((event) => event.id));
        assert(!initialJournal.some((event) => (dokarkiv(event, 'UTGAAENDE') || dokarkiv(event, 'INNGAAENDE')) && bankRequest(event)),
            'WireMock-fixturene 900000001/900000002 er allerede brukt; journalen ble ikke nullstilt');

        const saksnummer = String(10_000 + Math.floor(Math.random() * 90_000));
        const sak = await frontendFetch(frontendPage, '/dsop-kontroll/api/v1/sak', {
            method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ saksnummer, kontrollobjektId: '00000000000', type: 'UTLAND' }),
        });
        assert(sak.status >= 200 && sak.status < 300 && typeof sak.payload?.data?.saksnummer === 'string',
            `Kunne ikke opprette syntetisk sak via frontend BFF (HTTP ${sak.status})`);

        const bankSokId = `dsop-e2e-${randomUUID()}`;
        const request = await frontendFetch(frontendPage, '/dsop-kontroll/api/v1/altinn/skjema/', {
            method: 'POST', headers: { 'Content-Type': 'application/json', sokId: bankSokId },
            body: JSON.stringify({
                kontrollobjektId: '00000000000', kontrollobjektNavn: 'Syntetisk kontrollobjekt',
                pid: saksnummer, saksnummer: sak.payload.data.saksnummer,
                fraDato: '2026-01-01', tilDato: '2026-11-27',
                bestillingskoder: [{ key: 'KONTOINFORMASJON', kortTekst: 'Kontoinformasjon', langTekst: 'Kontoinformasjon for den syntetiske kontrollen.' }],
                bestillingsbeskjed: 'Syntetisk lokal E2E-verifikasjon.', bankOrganizations: [bank],
                bankSokId, temaForJournalfoering: 'KTR', vedlegg: [],
            }),
        });
        assert(request.status >= 200 && request.status < 300, `Kunne ikke opprette forespørsel via frontend BFF (HTTP ${request.status})`);

        const afterRequest = (await localJson(`${wiremock}/__admin/requests`)).requests;
        const newEvents = () => afterRequest.filter((event) => !initialRequestIds.has(event.id));
        const outgoingMatches = newEvents().filter((event) => dokarkiv(event, 'UTGAAENDE') && bankRequest(event) &&
            body(event).avsenderMottaker.navn === bank.navn && /^[0-9A-HJKMNP-TV-Z]{26}$/i.test(body(event).eksternReferanseId));
        assert(outgoingMatches.length === 1, `Forventet én ny utgående Dokarkiv-request, fant ${outgoingMatches.length}`);
        const outgoing = outgoingMatches[0];
        const skjemaId = body(outgoing).eksternReferanseId;
        const outgoingJournalpostId = JSON.parse(outgoing.response.body).journalpostId;

        const bankLink = new URL('/samarbeidspartner/kontoopplysninger/skjema', bankFrontend);
        bankLink.searchParams.set('skjemaid', skjemaId);
        console.log(`Lokal banklenke: ${bankLink}`);
        const bankPage = await context.newPage();
        trackErrors(bankPage);
        await bankPage.goto(bankLink.toString(), { waitUntil: 'domcontentloaded' });
        await bankPage.getByLabel('Ditt navn').fill('Syntetisk banksaksbehandler');
        await bankPage.getByLabel('Din e-postadresse').fill('e2e@example.invalid');
        await bankPage.locator('input[type="file"]').setInputFiles(attachment);
        await bankPage.getByRole('button', { name: 'Send inn' }).click();
        await expect(bankPage.getByText('Takk, ditt svar er registrert', { exact: false })).toBeVisible({ timeout: 60_000 });

        const finalJournal = (await localJson(`${wiremock}/__admin/requests`)).requests;
        const newJournalEvents = finalJournal.filter((event) => !initialRequestIds.has(event.id));
        assert(newJournalEvents.length > 0, 'Ingen nye WireMock-journalposter for normalflyten');
        for (const event of newJournalEvents) {
            assert(Number.isInteger(event.response.status) && event.wasMatched === true,
                'WireMock serve event mangler treff eller response.status');
            assert(event.response.status !== 502,
                `Ny WireMock-request traff catchall eller svarte 502: ${path(event)}`);
        }

        const outgoingRecords = newJournalEvents.filter((event) => dokarkiv(event, 'UTGAAENDE') && body(event).eksternReferanseId === skjemaId);
        const incomingRecords = newJournalEvents.filter((event) => dokarkiv(event, 'INNGAAENDE') && bankRequest(event) &&
            (body(event).tilleggsopplysninger.some((item) => item.verdi === outgoingJournalpostId) || body(event).tittel.includes(outgoingJournalpostId)));
        assert(outgoingRecords.length >= 1, 'Fant ikke utgående Dokarkiv-request for skjemaet');
        assert(incomingRecords.length >= 1, 'Fant ikke inngående Dokarkiv-request knyttet til forespørselen');
        assert(outgoingRecords.flatMap(pdfVariants).some((variant) => startsWithPdf(variant.fysiskDokument)),
            'Utgående Dokarkiv-request mangler base64-PDF med PDF-bytes');
        const incomingPdfs = incomingRecords.flatMap(pdfVariants);
        const uploadedPdf = readFileSync(attachment);
        assert(incomingPdfs.some((variant) => {
            const pdf = Buffer.from(variant.fysiskDokument, 'base64');
            return startsWithPdf(variant.fysiskDokument) && !pdf.equals(uploadedPdf);
        }), 'Inngående journalføring mangler et eget svarbrev i PDF-format');
        assert(incomingPdfs.some((variant) => Buffer.from(variant.fysiskDokument, 'base64').equals(uploadedPdf)),
            'Inngående Dokarkiv-request mangler opplastet syntetisk PDF');

        const database = dbRow(skjemaId);
        assert(database.status === 'MOTTATT', `Forventet DB-status MOTTATT, fikk ${database.status}`);
        assert(Boolean(database.archiveReference) && database.archiveReference !== '\\N', 'Skjemaet mangler archive_reference');
        assert(errors.length === 0, `Nettleserfeil under normalflyten: ${errors.slice(0, 5).join('; ')}`);
        console.log(`Verifisert normalflyt for syntetisk sak ${sak.payload.data.saksnummer}: MOTTATT, archive_reference satt og Dokarkiv-PDF-er registrert.`);
    } finally {
        await context.close();
        await browser.close();
    }
}

main().catch((error) => {
    console.error(`DSOP E2E-verifikasjon feilet: ${error.message}`);
    process.exitCode = 1;
});
