import assert from "node:assert/strict";
import { test } from "node:test";
import { parseProviderSendResponse } from "../src/services/newagent.js";

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
