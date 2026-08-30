import crypto from "node:crypto";
import { Router } from "express";
import { config } from "../config.js";
import { createWhatsappInboundStore } from "../services/whatsappInboundStore.js";

const DELIVERY_STATUSES = new Set(["sent", "delivered", "read", "failed"]);

// À passer en option `verify` de express.json pour conserver le corps brut nécessaire au HMAC.
export function captureRawBody(request, _response, buffer) {
  request.rawBody = buffer;
}

export function createWhatsappWebhookRouter({
  verifyToken = config.whatsappVerifyToken,
  appSecret = config.whatsappAppSecret,
  sharedToken = config.whatsappWebhookSharedToken,
  store = createWhatsappInboundStore(),
  logger = console,
  // Appelé après traitement complet de l'enveloppe (utilisé par les tests).
  onProcessed = () => {}
} = {}) {
  const router = Router();

  // Vérification d'abonnement Meta : renvoyer hub.challenge si le token correspond.
  router.get("/", (request, response) => {
    const mode = request.query["hub.mode"];
    const token = request.query["hub.verify_token"];
    const challenge = request.query["hub.challenge"];

    if (mode === "subscribe" && verifyToken && token === verifyToken) {
      return response.status(200).type("text/plain").send(String(challenge ?? ""));
    }
    return response.sendStatus(403);
  });

  router.post("/", (request, response) => {
    const auth = authenticate(request, { appSecret, sharedToken });
    if (auth === "unconfigured") {
      return response.status(503).json({ error: "webhook_not_configured" });
    }
    if (auth !== "ok") {
      logger.warn("whatsapp.webhook.rejected", { reason: auth });
      return response.sendStatus(403);
    }

    // Meta réémet si la réponse tarde : acquitter tout de suite, traiter ensuite.
    response.status(200).json({ received: true });

    processEnvelope(request.body, { store, logger })
      .catch((error) => {
        logger.warn("whatsapp.webhook.process.failure", { message: error?.message ?? null });
      })
      .finally(() => onProcessed());
  });

  return router;
}

function authenticate(request, { appSecret, sharedToken }) {
  if (appSecret) {
    const provided = request.get("x-hub-signature-256") ?? "";
    const expected =
      "sha256=" +
      crypto.createHmac("sha256", appSecret).update(request.rawBody ?? Buffer.alloc(0)).digest("hex");
    return constantTimeEqual(provided, expected) ? "ok" : "bad_signature";
  }

  if (sharedToken) {
    const header = request.get("authorization") ?? "";
    const provided = header.startsWith("Bearer ") ? header.slice(7) : "";
    return constantTimeEqual(provided, sharedToken) ? "ok" : "bad_token";
  }

  return "unconfigured";
}

function constantTimeEqual(a, b) {
  const bufferA = Buffer.from(String(a));
  const bufferB = Buffer.from(String(b));
  if (bufferA.length !== bufferB.length) {
    return false;
  }
  return crypto.timingSafeEqual(bufferA, bufferB);
}

async function processEnvelope(body, context) {
  for (const entry of asArray(body?.entry)) {
    for (const change of asArray(entry?.changes)) {
      const value = change?.value ?? {};
      for (const message of asArray(value.messages)) {
        await runStep(() => handleInboundMessage(message, context), context.logger);
      }
      for (const status of asArray(value.statuses)) {
        await runStep(() => handleStatus(status, context), context.logger);
      }
    }
  }
}

async function runStep(step, logger) {
  try {
    await step();
  } catch (error) {
    logger.warn("whatsapp.webhook.step.failure", { message: error?.message ?? null });
  }
}

async function handleInboundMessage(message, { store, logger }) {
  if (message?.type !== "text") {
    return;
  }
  if (normalizeKeyword(message?.text?.body) !== "stop") {
    return;
  }
  const from = typeof message?.from === "string" ? message.from : "";
  const messageId = typeof message?.id === "string" ? message.id : "";
  if (!from || !messageId) {
    return;
  }
  if (!(await store.claimEvent(`msg:${messageId}`))) {
    return;
  }
  const affected = await store.optOutDailySummary(from);
  logger.info("whatsapp.webhook.optout", { affected });
}

async function handleStatus(status, { store, logger }) {
  const id = typeof status?.id === "string" ? status.id : "";
  const state = typeof status?.status === "string" ? status.status : "";
  if (!id || !DELIVERY_STATUSES.has(state)) {
    return;
  }
  if (!(await store.claimEvent(`status:${id}:${state}`))) {
    return;
  }
  const affected = await store.recordDeliveryStatus(id, state);
  logger.info("whatsapp.webhook.status", { state, affected });
}

// Normalise casse, accents et espaces : « Stop », «  STOP  », « Stôp » -> « stop ».
function normalizeKeyword(value) {
  return String(value ?? "")
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .replace(/\s+/g, " ")
    .trim()
    .toLowerCase();
}

function asArray(value) {
  return Array.isArray(value) ? value : [];
}
