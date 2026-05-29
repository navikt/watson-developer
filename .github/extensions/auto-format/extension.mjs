// Extension: auto-format
// Kjører pnpm format:fix i watson-sak-frontend etter filendringar

import { execFile } from "node:child_process";
import { resolve } from "node:path";
import { joinSession } from "@github/copilot-sdk/extension";

const frontendDir = resolve(process.cwd(), "..", "watson-sak-frontend");
let formatRunning = false;
let session;

function isInFrontend(filePath) {
    if (!filePath) return false;
    return resolve(filePath).startsWith(frontendDir);
}

function runFormat() {
    if (formatRunning) return;
    formatRunning = true;
    execFile("pnpm", ["format:fix"], { cwd: frontendDir }, (err, _stdout, stderr) => {
        formatRunning = false;
        if (err) {
            session?.log(`auto-format: feil — ${stderr || err.message}`, { level: "warning" });
        } else {
            session?.log("auto-format: ✓ formatert", { ephemeral: true });
        }
    });
}

session = await joinSession({
    hooks: {
        onPostToolUse: async (input) => {
            if (input.toolName === "edit" || input.toolName === "create") {
                if (isInFrontend(input.toolArgs?.path)) {
                    runFormat();
                }
            }
        },
    },
    tools: [],
});
