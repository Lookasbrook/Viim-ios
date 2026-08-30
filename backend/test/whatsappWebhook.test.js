import assert from "node:assert/strict";
import crypto from "node:crypto";
import { once } from "node:events";
import { test } from "node:test";
import express from "express";
import {
  captureRawBody,
  createWhatsappWebhookRouter
} from "../src/routes/whatsappWebhook.js";

const APP_SECRET = "test-app-secret";
const VERIFY_TOKEN = "test-verify-token";

function createFakeStore() {
  const claimed = new Set();
  const calls = { optOut: [], status: [] };
  return {
    calls,
    async claimEvent(eventId) {
      if (claimed.has(eventId)) {
        return false;
      }
      claimed.add(eventId);
      return true;
    },
    async optOutDailySummary(from) {
      calls.optOut.push(from);
      return 1;
    },
    async recordDeliveryStatus(id, state) {
      calls.status.push({ id, state });
      return 1;
    }
  };
}

async function startServer(options = {}) {
  const processed = [];
  let resolveNext;
  const store = options.store ?? createFakeStore();
  const router = createWhatsappWebhookRouter({
    verifyToken: VERIFY_TOKEN,
    appSecret: options.appSecret === undefined ? APP_SECRET : options.appSecret,
    sharedToken: options.sharedToken,
    store,
    logger: { info() {}, warn() {} },
    onProcessed() {
      processed.push(Date.now());
      resolveNext?.();
    }
  });

  const app = express();
  app.use(express.json({ verify: captureRawBody }));
  app.use("/v1/webhooks/whatsapp", router);
  const server = app.listen(0);
  await once(server, "listening");
  const { port } = server.address();

  return {
    store,
    baseUrl: `http://127.0.0.1:${port}/v1/webhooks/whatsapp`,
    async close() {
      server.close();
      await once(server, "close");
    },
    waitForProcessing() {
      return new Promise((resolve) => {
        resolveNext = resolve;
      });
    }
  };
}

function sign(raw) {
  return "sha256=" + crypto.createHmac("sha256", APP_SECRET).update(raw).digest("hex");
}

async function postEnvelope(context, body, { signature } = {}) {
  const raw = JSON.stringify(body);
  return fetch(context.baseUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-hub-signature-256": signature ?? sign(raw)
    },
    body: raw
  });
}

function textMessage(text, { id = "wamid.in.1", from = "22670000000" } = {}) {
  return {
    entry: [
      {
        changes: [
          { value: { messages: [{ id, from, type: "text", text: { body: text } }] } }
        ]
      }
    ]
  };
}

function statusEnvelope(status, { id = "wamid.out.1" } = {}) {
  return {
    entry: [{ changes: [{ value: { statuses: [{ id, status }] } }] }]
  };
}

test("GET echoes the challenge when the verify token matches", async () => {
  const context = await startServer();
  try {
    const response = await fetch(
      `${context.baseUrl}?hub.mode=subscribe&hub.verify_token=${VERIFY_TOKEN}&hub.challenge=abc123`
    );
    assert.equal(response.status, 200);
    assert.equal(await response.text(), "abc123");
  } finally {
    await context.close();
  }
});

test("GET rejects a wrong verify token", async () => {
  const context = await startServer();
  try {
    const response = await fetch(
      `${context.baseUrl}?hub.mode=subscribe&hub.verify_token=wrong&hub.challenge=abc123`
    );
    assert.equal(response.status, 403);
  } finally {
    await context.close();
  }
});

test("POST rejects an invalid signature and does not process", async () => {
  const context = await startServer();
  try {
    const response = await postEnvelope(context, textMessage("STOP"), {
      signature: "sha256=deadbeef"
    });
    assert.equal(response.status, 403);
    assert.deepEqual(context.store.calls.optOut, []);
  } finally {
    await context.close();
  }
});

test("POST returns 503 when no signature nor shared token is configured", async () => {
  const context = await startServer({ appSecret: "", sharedToken: "" });
  try {
    const response = await fetch(context.baseUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(textMessage("STOP"))
    });
    assert.equal(response.status, 503);
  } finally {
    await context.close();
  }
});

test("POST STOP opts the sender out of the daily summary", async () => {
  const context = await startServer();
  try {
    const done = context.waitForProcessing();
    const response = await postEnvelope(context, textMessage("STOP"));
    assert.equal(response.status, 200);
    await done;
    assert.deepEqual(context.store.calls.optOut, ["22670000000"]);
  } finally {
    await context.close();
  }
});

test("POST STOP tolerates case, accents and surrounding spaces", async () => {
  const context = await startServer();
  try {
    const done = context.waitForProcessing();
    await postEnvelope(context, textMessage("  StÔp \n"));
    await done;
    assert.deepEqual(context.store.calls.optOut, ["22670000000"]);
  } finally {
    await context.close();
  }
});

test("POST ignores a non-STOP inbound message", async () => {
  const context = await startServer();
  try {
    const done = context.waitForProcessing();
    await postEnvelope(context, textMessage("Bonjour, tout va bien ?"));
    await done;
    assert.deepEqual(context.store.calls.optOut, []);
  } finally {
    await context.close();
  }
});

test("POST records a delivery status update", async () => {
  const context = await startServer();
  try {
    const done = context.waitForProcessing();
    await postEnvelope(context, statusEnvelope("delivered", { id: "wamid.out.42" }));
    await done;
    assert.deepEqual(context.store.calls.status, [{ id: "wamid.out.42", state: "delivered" }]);
  } finally {
    await context.close();
  }
});

test("POST is idempotent on a replayed message id", async () => {
  const context = await startServer();
  try {
    const first = context.waitForProcessing();
    await postEnvelope(context, textMessage("STOP", { id: "wamid.dup" }));
    await first;

    const second = context.waitForProcessing();
    await postEnvelope(context, textMessage("STOP", { id: "wamid.dup" }));
    await second;

    assert.deepEqual(context.store.calls.optOut, ["22670000000"]);
  } finally {
    await context.close();
  }
});
