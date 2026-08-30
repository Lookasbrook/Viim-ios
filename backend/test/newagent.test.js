import assert from "node:assert/strict";
import { test } from "node:test";
import { buildProviderPayload, parseProviderSendResponse } from "../src/services/newagent.js";

const GATEWAY_URL = "https://newagent.burktech-ia.com/send";
const META_URL = "https://graph.facebook.com/v21.0/123456789/messages";
const OUAGA = { latitude: 12.3718, longitude: -1.5196, accuracyMeters: 8 };

test("parseProviderSendResponse accepts a provider message id", async () => {
  const result = await parseProviderSendResponse(
    new Response(JSON.stringify({ providerMessageId: "wamid.123" }), {
      status: 202,
      headers: { "Content-Type": "application/json" }
    })
  );

  assert.deepEqual(result, {
    status: "ok",
    code: 202,
    providerMessageId: "wamid.123"
  });
});

test("parseProviderSendResponse accepts nested provider message ids", async () => {
  const result = await parseProviderSendResponse(
    new Response(JSON.stringify({ data: { messageId: "nested.123" } }), {
      status: 200,
      headers: { "Content-Type": "application/json" }
    })
  );

  assert.equal(result.providerMessageId, "nested.123");
});

test("parseProviderSendResponse rejects 2xx responses without message proof", async () => {
  await assert.rejects(
    () => parseProviderSendResponse(
      new Response(JSON.stringify({
        reply: "message accepted for +22670000000",
        tokenEcho: "Bearer secret-token"
      }), {
        status: 200,
        headers: { "Content-Type": "application/json" }
      })
    ),
    (error) => {
      assert.equal(error.message, "provider_no_message_id");
      assert.equal(error.providerStatus, 200);
      assert.equal(error.providerCode, "provider_no_message_id");
      assert.match(error.providerBodySnippet, /\[phone\]/);
      assert.match(error.providerBodySnippet, /Bearer \[redacted\]/);
      assert.doesNotMatch(error.providerBodySnippet, /\+22670000000/);
      assert.doesNotMatch(error.providerBodySnippet, /secret-token/);
      return true;
    }
  );
});

test("parseProviderSendResponse rejects HTTP errors with provider status", async () => {
  await assert.rejects(
    () => parseProviderSendResponse(
      new Response(JSON.stringify({ error: "bad_payload" }), {
        status: 502,
        headers: { "Content-Type": "application/json" }
      })
    ),
    (error) => {
      assert.equal(error.message, "newagent_send_failed");
      assert.equal(error.providerStatus, 502);
      assert.equal(error.providerCode, "http_error");
      return true;
    }
  );
});

test("buildProviderPayload keeps the NEwAGENT-IA gateway contract unchanged", () => {
  const payload = buildProviderPayload(GATEWAY_URL, {
    to: "+22670000000",
    message: "Alerte Viim : collision confirmée pour Guy.",
    kind: "collision",
    metadata: { contactName: "Awa" },
    params: { driverName: "Guy", location: OUAGA }
  });

  assert.deepEqual(payload, {
    source: "viim",
    channel: "whatsapp",
    kind: "collision",
    to: "+22670000000",
    message: "Alerte Viim : collision confirmée pour Guy.",
    metadata: { contactName: "Awa" }
  });
});

test("buildProviderPayload sends the alert_test template on the Meta endpoint", () => {
  const payload = buildProviderPayload(META_URL, {
    to: "+22670000000",
    message: "ignored for templates",
    kind: "alert_test",
    params: {}
  });

  assert.equal(payload.type, "template");
  assert.equal(payload.to, "22670000000");
  assert.equal(payload.template.name, "viim_alert_test");
  assert.equal(payload.template.language.code, "fr");
  assert.equal(payload.template.components, undefined);
});

test("buildProviderPayload builds a collision template with body params and a maps button", () => {
  const payload = buildProviderPayload(META_URL, {
    to: "+22670000000",
    message: "ignored",
    kind: "collision",
    params: { driverName: "Guy", location: OUAGA }
  });

  assert.equal(payload.type, "template");
  assert.equal(payload.template.name, "viim_collision_alert");

  const body = payload.template.components.find((component) => component.type === "body");
  assert.deepEqual(body.parameters, [
    { type: "text", text: "Guy" },
    { type: "text", text: "12.371800, -1.519600" }
  ]);

  const button = payload.template.components.find((component) => component.type === "button");
  assert.equal(button.sub_type, "url");
  assert.equal(button.index, "0");
  assert.deepEqual(button.parameters, [{ type: "text", text: "12.371800,-1.519600" }]);
});

test("buildProviderPayload uses the location_share template for position sharing", () => {
  const payload = buildProviderPayload(META_URL, {
    to: "+12045551234",
    message: "ignored",
    kind: "location_share",
    params: { driverName: "Guy", location: OUAGA }
  });

  assert.equal(payload.template.name, "viim_location_share");
  assert.equal(payload.to, "12045551234");
});

test("buildProviderPayload defaults the driver name when absent", () => {
  const payload = buildProviderPayload(META_URL, {
    to: "+22670000000",
    message: "ignored",
    kind: "collision",
    params: { location: OUAGA }
  });

  const body = payload.template.components.find((component) => component.type === "body");
  assert.equal(body.parameters[0].text, "Un utilisateur Viim");
});

test("buildProviderPayload falls back to text when a location alert has no coordinates", () => {
  const payload = buildProviderPayload(META_URL, {
    to: "+22670000000",
    message: "Guy partage sa position via Viim.",
    kind: "location_share",
    params: { driverName: "Guy" }
  });

  assert.equal(payload.type, "text");
  assert.equal(payload.text.body, "Guy partage sa position via Viim.");
});

test("buildProviderPayload falls back to text for an unknown Meta kind", () => {
  const payload = buildProviderPayload(META_URL, {
    to: "+22670000000",
    message: "Message libre",
    kind: "reminder",
    params: {}
  });

  assert.equal(payload.type, "text");
  assert.equal(payload.text.body, "Message libre");
});
