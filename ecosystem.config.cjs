const { readFileSync } = require("fs");
const { resolve } = require("path");

// Load .env.local into env vars for pm2-managed processes.
// Next.js loads .env.local itself; the worker needs it injected.
function loadEnvFile(filePath) {
  try {
    const content = readFileSync(resolve(__dirname, filePath), "utf-8");
    const env = {};
    for (const line of content.split("\n")) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) continue;
      const eqIdx = trimmed.indexOf("=");
      if (eqIdx === -1) continue;
      const key = trimmed.slice(0, eqIdx).trim();
      let val = trimmed.slice(eqIdx + 1).trim();
      if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
        val = val.slice(1, -1);
      }
      env[key] = val;
    }
    return env;
  } catch {
    return {};
  }
}

const dotenv = loadEnvFile(".env.local");

module.exports = {
  apps: [
    {
      name: "web",
      script: "node_modules/.bin/next",
      args: "dev --turbopack",
      interpreter: "none",
      watch: false,
      env: {
        NODE_ENV: "development",
        ...dotenv,
      },
    },
    {
      name: "worker",
      script: "node_modules/.bin/tsx",
      args: "watch lib/jobs/worker.ts",
      interpreter: "none",
      watch: false,
      env: {
        NODE_ENV: "development",
        ...dotenv,
      },
    },
  ],
};
