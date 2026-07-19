import { fileURLToPath } from "node:url";
import { config } from "./config.js";
import { runMigrations } from "./db/migrate.js";

export async function prepareAppStartup({
  environment = config.env,
  databaseUrl = config.databaseUrl,
  migrate = runMigrations
} = {}) {
  if (environment !== "production") {
    return;
  }
  if (!databaseUrl) {
    throw new Error("database_not_configured");
  }

  await migrate();
}

export async function startApp() {
  await prepareAppStartup();
  await import("./server.js");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  startApp().catch((error) => {
    console.error("viim-api startup failed", error.message);
    process.exitCode = 1;
  });
}
