import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";
import {
  buildProviderPayload,
  parseProviderSendResponse
} from "../src/services/newagent.js";
import { prepareAppStartup } from "../src/start.js";

test("production startup applies database migrations before serving requests", async () => {
  const calls = [];

  await prepareAppStartup({
    environment: "production",
    databaseUrl: "postgres://configured",
    migrate: async () => {
      calls.push("migrate");
    }
  });
  calls.push("listen");

  assert.deepEqual(calls, ["migrate", "listen"]);
});

test("production startup refuses to serve without a database", async () => {
  await assert.rejects(
    prepareAppStartup({
      environment: "production",
      databaseUrl: "",
      migrate: async () => {
        assert.fail("migration must not run without a configured database");
      }
    }),
    /database_not_configured/
  );
});

test("Docker starts through the migration-aware entrypoint", async () => {
  const dockerfile = await readFile(new URL("../Dockerfile", import.meta.url), "utf8");

  assert.match(dockerfile, /CMD \["node", "src\/start\.js"\]/);
});

test("Meta WhatsApp Cloud requests use the provider contract", () => {
  const payload = buildProviderPayload(
    "https://graph.facebook.com/v21.0/123456/messages",
    {
      to: "+22670123456",
      message: "Test Viim",
      kind: "alert_test",
      metadata: { contactName: "Contact" }
    }
  );

  assert.deepEqual(payload, {
    messaging_product: "whatsapp",
    recipient_type: "individual",
    to: "22670123456",
    type: "text",
    text: {
      preview_url: false,
      body: "Test Viim"
    }
  });
});

test("Meta WhatsApp Cloud responses expose their message proof", async () => {
  const result = await parseProviderSendResponse(
    new Response(JSON.stringify({
      messaging_product: "whatsapp",
      contacts: [{ input: "22670123456", wa_id: "22670123456" }],
      messages: [{ id: "wamid.meta-test" }]
    }), {
      status: 200,
      headers: { "Content-Type": "application/json" }
    })
  );

  assert.equal(result.providerMessageId, "wamid.meta-test");
});
