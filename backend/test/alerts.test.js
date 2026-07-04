import assert from "node:assert/strict";
import { once } from "node:events";
import { test } from "node:test";
import express from "express";
import { createAlertsRouter } from "../src/routes/alerts.js";

test("POST /v1/alerts/test sends a WhatsApp payload", async () => {
  const sentPayloads = [];
  const { server, baseUrl } = await startTestServer({
    sendMessage: async (payload) => {
      sentPayloads.push(payload);
      return { status: "ok", code: 202 };
    }
  });

  try {
    const response = await fetch(`${baseUrl}/v1/alerts/test`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        driverName: "Guy",
        contact: {
          name: "Contact",
          phoneNumber: "+22670000000"
        }
      })
    });

    assert.equal(response.status, 200);
    assert.equal(sentPayloads.length, 1);
    assert.equal(sentPayloads[0].kind, "alert_test");
    assert.equal(sentPayloads[0].to, "+22670000000");
  } finally {
    server.close();
  }
});

test("POST /v1/alerts/test rejects invalid Burkina phone numbers", async () => {
  const { server, baseUrl } = await startTestServer({
    sendMessage: async () => ({ status: "ok", code: 202 })
  });

  try {
    const response = await fetch(`${baseUrl}/v1/alerts/test`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contact: {
          name: "Contact",
          phoneNumber: "+2250700000000"
        }
      })
    });

    const body = await response.json();
    assert.equal(response.status, 422);
    assert.equal(body.error, "invalid_contact");
  } finally {
    server.close();
  }
});

test("POST /v1/alerts/location-share validates location and dispatches message", async () => {
  const sentPayloads = [];
  const { server, baseUrl } = await startTestServer({
    sendMessage: async (payload) => {
      sentPayloads.push(payload);
      return { status: "ok", code: 202 };
    }
  });

  try {
    const response = await fetch(`${baseUrl}/v1/alerts/location-share`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        driverName: "Guy",
        contact: {
          name: "Contact",
          phoneNumber: "+22670000000"
        },
        location: {
          latitude: 12.3714,
          longitude: -1.5197,
          accuracyMeters: 12
        }
      })
    });

    assert.equal(response.status, 200);
    assert.equal(sentPayloads[0].kind, "location_share");
    assert.equal(sentPayloads[0].metadata.location.latitude, 12.3714);
  } finally {
    server.close();
  }
});

test("POST /v1/alerts/collision sends only the first contact immediately", async () => {
  const sentPayloads = [];
  const { server, baseUrl } = await startTestServer({
    sendMessage: async (payload) => {
      sentPayloads.push(payload);
      return { status: "ok", code: 202 };
    }
  });

  try {
    const response = await fetch(`${baseUrl}/v1/alerts/collision`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        driverName: "Guy",
        contacts: [
          { name: "Contact 1", phoneNumber: "+22670000000" },
          { name: "Contact 2", phoneNumber: "+22671000000" }
        ],
        location: {
          latitude: 12.3714,
          longitude: -1.5197
        },
        medicalProfile: {
          bloodType: "O+",
          allergies: "Aucune"
        }
      })
    });

    assert.equal(response.status, 200);
    assert.equal(sentPayloads.length, 1);
    assert.equal(sentPayloads[0].to, "+22670000000");
    assert.equal(sentPayloads[0].metadata.contactsCount, 2);
    assert.equal(sentPayloads[0].metadata.medicalProfile.bloodType, "O+");
  } finally {
    server.close();
  }
});

async function startTestServer({ sendMessage }) {
  const app = express();
  app.use(express.json());
  app.use("/v1/alerts", createAlertsRouter({ sendMessage }));

  const server = app.listen(0, "127.0.0.1");
  await once(server, "listening");

  const address = server.address();
  return {
    server,
    baseUrl: `http://127.0.0.1:${address.port}`
  };
}
