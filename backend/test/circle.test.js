import assert from "node:assert/strict";
import { once } from "node:events";
import { test } from "node:test";
import express from "express";
import { createCircleRouter, createJoinRouter } from "../src/routes/circle.js";
import { createMemoryCircleStore } from "../src/services/circleStore.js";

test("trusted-circle invitation is accepted once and creates a bidirectional relationship", async () => {
  const context = await startCircleServer();
  try {
    const guy = await register(context.baseUrl, "Guy", "11111111-1111-4111-8111-111111111111");
    const proche = await register(context.baseUrl, "Awa", "22222222-2222-4222-8222-222222222222");

    const inviteResponse = await authedFetch(context.baseUrl, guy.authToken, "/v1/circle/invitations", {
      method: "POST"
    });
    assert.equal(inviteResponse.status, 201);
    const invitation = await inviteResponse.json();
    const token = new URL(invitation.inviteURL).pathname.split("/").at(-1);

    const previewResponse = await authedFetch(context.baseUrl, proche.authToken, "/v1/circle/invitations/preview", {
      method: "POST",
      body: JSON.stringify({ token })
    });
    assert.equal(previewResponse.status, 200);
    assert.equal((await previewResponse.json()).inviterDisplayName, "Guy");

    const acceptResponse = await authedFetch(context.baseUrl, proche.authToken, "/v1/circle/invitations/accept", {
      method: "POST",
      body: JSON.stringify({ token })
    });
    assert.equal(acceptResponse.status, 200);

    const guyMembers = await authedJSON(context.baseUrl, guy.authToken, "/v1/circle/members");
    const procheMembers = await authedJSON(context.baseUrl, proche.authToken, "/v1/circle/members");
    assert.equal(guyMembers.members[0].displayName, "Awa");
    assert.equal(procheMembers.members[0].displayName, "Guy");

    const secondAccept = await authedFetch(context.baseUrl, proche.authToken, "/v1/circle/invitations/accept", {
      method: "POST",
      body: JSON.stringify({ token })
    });
    assert.equal(secondAccept.status, 409);
    assert.equal((await secondAccept.json()).error, "invitation_already_used");
  } finally {
    context.server.close();
  }
});

test("registration retry with the same installation secret is idempotent", async () => {
  const context = await startCircleServer();
  try {
    const installationId = "88888888-8888-4888-8888-888888888888";
    const registrationToken = "r".repeat(43);
    const first = await register(context.baseUrl, "Guy", installationId, registrationToken);
    const retry = await register(context.baseUrl, "Guy K.", installationId, registrationToken);
    assert.equal(retry.userId, first.userId);
    assert.equal(retry.authToken, registrationToken);
    assert.equal(retry.displayName, "Guy K.");

    const conflict = await fetch(`${context.baseUrl}/v1/circle/register`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        displayName: "Intrus",
        installationId,
        registrationToken: "x".repeat(43),
        pushEnvironment: "sandbox"
      })
    });
    assert.equal(conflict.status, 409);
  } finally {
    context.server.close();
  }
});

test("stats stay private until sharing is enabled and can be used for a circle challenge", async () => {
  const context = await startCircleServer();
  try {
    const first = await register(context.baseUrl, "Guy", "33333333-3333-4333-8333-333333333333");
    const second = await register(context.baseUrl, "Awa", "44444444-4444-4444-8444-444444444444");
    await connectUsers(context.baseUrl, first, second);

    const statsPayload = {
      score: 91,
      tripsCount: 8,
      distanceKm: 126.4,
      safeStreak: 6,
      periodStart: "2026-07-01T00:00:00.000Z"
    };
    let response = await authedFetch(context.baseUrl, second.authToken, "/v1/circle/stats", {
      method: "PUT",
      body: JSON.stringify(statsPayload)
    });
    assert.equal(response.status, 204);

    let members = await authedJSON(context.baseUrl, first.authToken, "/v1/circle/members");
    assert.equal(members.members[0].stats, null);

    response = await authedFetch(context.baseUrl, second.authToken, "/v1/circle/me", {
      method: "PATCH",
      body: JSON.stringify({ statsSharing: true })
    });
    assert.equal(response.status, 200);

    members = await authedJSON(context.baseUrl, first.authToken, "/v1/circle/members");
    assert.equal(members.members[0].stats.score, 91);
    assert.equal(members.members[0].stats.tripsCount, 8);
    assert.equal(members.members[0].stats.safeStreak, 6);
  } finally {
    context.server.close();
  }
});

test("collision incident is stored in every member inbox even when only one APNs push is possible", async () => {
  const pushed = [];
  const context = await startCircleServer({
    notifier: {
      async sendIncident(payload) {
        pushed.push(payload);
        return payload.recipient.pushToken ? { status: "sent" } : { status: "skipped" };
      }
    }
  });

  try {
    const driver = await register(context.baseUrl, "Guy", "55555555-5555-4555-8555-555555555555");
    const proche = await register(context.baseUrl, "Awa", "66666666-6666-4666-8666-666666666666");
    await connectUsers(context.baseUrl, driver, proche);

    const tokenResponse = await authedFetch(context.baseUrl, proche.authToken, "/v1/circle/me", {
      method: "PATCH",
      body: JSON.stringify({
        pushToken: "a".repeat(64),
        pushEnvironment: "sandbox"
      })
    });
    assert.equal(tokenResponse.status, 200);

    const incidentResponse = await authedFetch(context.baseUrl, driver.authToken, "/v1/circle/incidents", {
      method: "POST",
      body: JSON.stringify({
        occurredAt: "2026-07-21T12:00:00.000Z",
        severity: "confirmed",
        location: { latitude: 12.3714, longitude: -1.5197, accuracyMeters: 8 }
      })
    });
    assert.equal(incidentResponse.status, 201);
    const incidentResult = await incidentResponse.json();
    assert.equal(incidentResult.recipientsCount, 1);
    assert.equal(incidentResult.pushSentCount, 1);
    assert.equal(incidentResult.storedInApp, true);
    assert.equal(pushed.length, 1);

    const inbox = await authedJSON(context.baseUrl, proche.authToken, "/v1/circle/inbox");
    assert.equal(inbox.notifications.length, 1);
    assert.equal(inbox.notifications[0].sourceDisplayName, "Guy");
    assert.equal(inbox.notifications[0].severity, "confirmed");
    assert.equal(inbox.notifications[0].readAt, null);

    const readResponse = await authedFetch(
      context.baseUrl,
      proche.authToken,
      `/v1/circle/inbox/${inbox.notifications[0].id}/read`,
      { method: "POST" }
    );
    assert.equal(readResponse.status, 204);
    const readInbox = await authedJSON(context.baseUrl, proche.authToken, "/v1/circle/inbox");
    assert.ok(readInbox.notifications[0].readAt);
  } finally {
    context.server.close();
  }
});

test("circle endpoints reject missing authentication, malformed push tokens and invalid incidents", async () => {
  const context = await startCircleServer();
  try {
    const unauthorized = await fetch(`${context.baseUrl}/v1/circle/members`);
    assert.equal(unauthorized.status, 401);

    const user = await register(context.baseUrl, "Guy", "77777777-7777-4777-8777-777777777777");
    const badPush = await authedFetch(context.baseUrl, user.authToken, "/v1/circle/me", {
      method: "PATCH",
      body: JSON.stringify({ pushToken: "not-a-token" })
    });
    assert.equal(badPush.status, 422);

    const badIncident = await authedFetch(context.baseUrl, user.authToken, "/v1/circle/incidents", {
      method: "POST",
      body: JSON.stringify({
        occurredAt: "invalid",
        severity: "confirmed",
        location: { latitude: 190, longitude: 0 }
      })
    });
    assert.equal(badIncident.status, 422);
  } finally {
    context.server.close();
  }
});

test("public invitation link only exposes a deliberate open-in-app action", async () => {
  const context = await startCircleServer();
  try {
    const response = await fetch(`${context.baseUrl}/join/${"a".repeat(43)}`);
    assert.equal(response.status, 200);
    const html = await response.text();
    assert.match(html, /viim:\/\/join\?token=/);
    assert.doesNotMatch(html, /authToken/);
  } finally {
    context.server.close();
  }
});

async function startCircleServer({ notifier = { async sendIncident() { return { status: "skipped" }; } } } = {}) {
  const app = express();
  app.use(express.json());
  app.use("/v1/circle", createCircleRouter({
    store: createMemoryCircleStore(),
    notifier,
    publicBaseUrl: "http://example.test",
    logger: { info() {}, warn() {} }
  }));
  app.use("/join", createJoinRouter());
  const server = app.listen(0, "127.0.0.1");
  await once(server, "listening");
  const address = server.address();
  return { server, baseUrl: `http://127.0.0.1:${address.port}` };
}

async function register(baseUrl, displayName, installationId, registrationToken) {
  const response = await fetch(`${baseUrl}/v1/circle/register`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      displayName,
      installationId,
      registrationToken,
      pushEnvironment: "sandbox"
    })
  });
  assert.equal(response.status, 201);
  return response.json();
}

async function connectUsers(baseUrl, inviter, accepter) {
  const inviteResponse = await authedFetch(baseUrl, inviter.authToken, "/v1/circle/invitations", {
    method: "POST"
  });
  const invitation = await inviteResponse.json();
  const token = new URL(invitation.inviteURL).pathname.split("/").at(-1);
  const acceptResponse = await authedFetch(baseUrl, accepter.authToken, "/v1/circle/invitations/accept", {
    method: "POST",
    body: JSON.stringify({ token })
  });
  assert.equal(acceptResponse.status, 200);
}

async function authedJSON(baseUrl, token, path) {
  const response = await authedFetch(baseUrl, token, path);
  assert.equal(response.status, 200);
  return response.json();
}

function authedFetch(baseUrl, token, path, options = {}) {
  return fetch(`${baseUrl}${path}`, {
    ...options,
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      ...options.headers
    }
  });
}
