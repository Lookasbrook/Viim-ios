import express from "express";
import { config } from "./config.js";
import { logScrubber } from "./middleware/logScrubber.js";
import { createAdminRouter } from "./routes/admin.js";
import { createAlertsRouter } from "./routes/alerts.js";
import { appleAppSiteAssociation } from "./routes/appleAppSiteAssociation.js";
import { createCircleRouter, createJoinRouter } from "./routes/circle.js";
import { createFuelPricesRouter } from "./routes/fuelPrices.js";
import { healthRouter } from "./routes/health.js";
import { captureRawBody, createWhatsappWebhookRouter } from "./routes/whatsappWebhook.js";
import { createAlertStore } from "./services/alertStore.js";
import { createCollisionEscalationStore } from "./services/collisionEscalationStore.js";
import { runCollisionEscalationTick } from "./services/collisionEscalationWorker.js";
import { sendWhatsAppMessage } from "./services/newagent.js";

const ESCALATION_TICK_MS = 60_000;

const app = express();

app.disable("x-powered-by");
app.use(express.json({ limit: "256kb", verify: captureRawBody }));
app.use(logScrubber);

app.get(["/.well-known/apple-app-site-association", "/apple-app-site-association"], appleAppSiteAssociation);

app.use("/health", healthRouter);
app.use("/v1/health", healthRouter);
app.use("/v1/alerts", createAlertsRouter());
app.use("/v1/webhooks/whatsapp", createWhatsappWebhookRouter());
app.use("/v1/circle", createCircleRouter());
app.use("/v1/fuel-prices", createFuelPricesRouter());
app.use("/join", createJoinRouter());
app.use("/admin", createAdminRouter());

app.use((_request, response) => {
  response.status(404).json({ error: "not_found" });
});

const server = app.listen(config.port, config.host, () => {
  console.info(`viim-api listening on ${config.host}:${config.port}`);
});

server.on("error", (error) => {
  console.error(error);
  process.exitCode = 1;
});

// Cascade des alertes collision : relance le contact suivant si personne n'a lu sous 5 min.
// Nécessite une base ; une seule instance suffit (verrou par bail dans la table).
let escalationTimer = null;
if (config.databaseUrl) {
  const escalationStore = createCollisionEscalationStore();
  const alertStore = createAlertStore();
  escalationTimer = setInterval(() => {
    runCollisionEscalationTick({
      store: escalationStore,
      sendMessage: sendWhatsAppMessage,
      alertStore
    }).catch((error) => {
      console.warn("collision escalation tick failed", error?.message ?? error);
    });
  }, ESCALATION_TICK_MS);
  escalationTimer.unref?.();
}

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => {
    if (escalationTimer) {
      clearInterval(escalationTimer);
    }
    server.close(() => {
      process.exit(0);
    });
  });
}
