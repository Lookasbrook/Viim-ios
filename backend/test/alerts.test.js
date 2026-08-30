import assert from "node:assert/strict";
import { once } from "node:events";
import { test } from "node:test";
import express from "express";
import { createAlertsRouter } from "../src/routes/alerts.js";
import { sanitizeAlertMetadata } from "../src/services/alertStore.js";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

test("medical collision details are excluded from persisted alert metadata", () => {
  const safeMetadata = sanitizeAlertMetadata({
    contactName: "Awa",
    incidentId: "incident-1",
    medicalProfile: {
      bloodType: "O+",
      allergies: "Arachides"
    }
  });

  assert.deepEqual(safeMetadata, {
    contactName: "Awa",
    incidentId: "incident-1"
  });
});

test("POST /v1/alerts/test sends a WhatsApp payload", async () => {
  const sentPayloads = [];
  const { server, baseUrl, alertStore } = await startTestServer({
    sendMessage: async (payload) => {
      sentPayloads.push(payload);
      return { status: "ok", code: 202, providerMessageId: "wamid.test" };
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
    const body = await response.json();
    assert.equal(body.status, "sent");
    assert.match(body.alertId, uuidPattern);
    assert.equal(body.providerMessageId, "wamid.test");
    assert.equal(body.providerStatus, 202);
    assert.equal(sentPayloads.length, 1);
    assert.equal(sentPayloads[0].kind, "alert_test");
    assert.equal(sentPayloads[0].to, "+22670000000");

    const stored = await alertStore.findById(body.alertId);
    assert.equal(stored.status, "sent");
    assert.equal(stored.providerMessageId, "wamid.test");

    const statusResponse = await fetch(`${baseUrl}/v1/alerts/${body.alertId}`);
    assert.equal(statusResponse.status, 200);
    const statusBody = await statusResponse.json();
    assert.equal(statusBody.status, "sent");
  } finally {
    server.close();
  }
});

test("POST /v1/alerts/test rejects non-E164 phone numbers", async () => {
  const { server, baseUrl } = await startTestServer({
    sendMessage: async () => ({ status: "ok", code: 202, providerMessageId: "wamid.unused" })
  });

  try {
    for (const phoneNumber of ["70000000", "+0700000000", "0022670000000", "+12345678901234567"]) {
      const response = await fetch(`${baseUrl}/v1/alerts/test`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contact: {
            name: "Contact",
            phoneNumber
          }
        })
      });

      const body = await response.json();
      assert.equal(response.status, 422, `expected rejection for ${phoneNumber}`);
      assert.equal(body.error, "invalid_contact");
    }
  } finally {
    server.close();
  }
});

test("POST /v1/alerts/test accepts international E164 contacts", async () => {
  const sentPayloads = [];
  const { server, baseUrl } = await startTestServer({
    sendMessage: async (payload) => {
      sentPayloads.push(payload);
      return { status: "ok", code: 202, providerMessageId: "wamid.intl" };
    }
  });

  try {
    const response = await fetch(`${baseUrl}/v1/alerts/test`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contact: {
          name: "Contact Canada",
          phoneNumber: "+15141234567"
        }
      })
    });

    assert.equal(response.status, 200);
    assert.equal(sentPayloads[0].to, "+15141234567");
  } finally {
    server.close();
  }
});

test("POST /v1/alerts/collision accepts up to four contacts and rejects five", async () => {
  const sentPayloads = [];
  const { server, baseUrl } = await startTestServer({
    sendMessage: async (payload) => {
      sentPayloads.push(payload);
      return { status: "ok", code: 202, providerMessageId: "wamid.four" };
    }
  });

  const contact = (index) => ({ name: `Contact ${index}`, phoneNumber: `+2267000000${index}` });
  const location = { latitude: 12.3714, longitude: -1.5197 };

  try {
    const okResponse = await fetch(`${baseUrl}/v1/alerts/collision`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contacts: [contact(1), contact(2), contact(3), contact(4)],
        location
      })
    });
    assert.equal(okResponse.status, 200);
    assert.equal(sentPayloads[0].metadata.contactsCount, 4);

    const tooManyResponse = await fetch(`${baseUrl}/v1/alerts/collision`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contacts: [contact(1), contact(2), contact(3), contact(4), contact(5)],
        location
      })
    });
    const body = await tooManyResponse.json();
    assert.equal(tooManyResponse.status, 422);
    assert.equal(body.error, "invalid_contacts");
  } finally {
    server.close();
  }
});

test("POST /v1/alerts/location-share validates location and dispatches message", async () => {
  const sentPayloads = [];
  const { server, baseUrl } = await startTestServer({
    sendMessage: async (payload) => {
      sentPayloads.push(payload);
      return { status: "ok", code: 202, providerMessageId: "wamid.location" };
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

test("POST /v1/alerts/collision alerts the first contact and schedules the escalation", async () => {
  const sentPayloads = [];
  const escalationStore = createMemoryEscalationStore();
  const { server, baseUrl } = await startTestServer({
    escalationStore,
    sendMessage: async (payload) => {
      sentPayloads.push(payload);
      return { status: "ok", code: 202, providerMessageId: "wamid.collision" };
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
        location: { latitude: 12.3714, longitude: -1.5197 },
        medicalProfile: { bloodType: "O+", allergies: "Aucune" }
      })
    });

    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.status, "sent");
    assert.equal(body.sentCount, 1);
    assert.equal(body.failedCount, 0);
    assert.match(body.incidentId, uuidPattern);
    assert.deepEqual(body.escalation, { pendingContacts: 1, escalateAfterMinutes: 5 });

    assert.equal(sentPayloads.length, 1);
    assert.equal(sentPayloads[0].to, "+22670000000");
    assert.equal(sentPayloads[0].metadata.medicalProfile.bloodType, "O+");

    assert.equal(escalationStore.incidents.length, 1);
    assert.equal(escalationStore.incidents[0].incidentId, body.incidentId);
    assert.equal(escalationStore.incidents[0].nextIndex, 1);
    assert.equal(escalationStore.incidents[0].contacts.length, 2);
  } finally {
    server.close();
  }
});

test("POST /v1/alerts/collision does not schedule an escalation for a single contact", async () => {
  const escalationStore = createMemoryEscalationStore();
  const { server, baseUrl } = await startTestServer({
    escalationStore,
    sendMessage: async () => ({ status: "ok", code: 202, providerMessageId: "wamid.one" })
  });

  try {
    const response = await fetch(`${baseUrl}/v1/alerts/collision`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contacts: [{ name: "Contact 1", phoneNumber: "+22670000000" }],
        location: { latitude: 12.3714, longitude: -1.5197 }
      })
    });

    const body = await response.json();
    assert.equal(response.status, 200);
    assert.equal(body.sentCount, 1);
    assert.equal(body.escalation, null);
    assert.equal(escalationStore.incidents.length, 0);
  } finally {
    server.close();
  }
});

test("POST /v1/alerts/collision falls through to the next contact when the first send fails", async () => {
  const attempts = [];
  const escalationStore = createMemoryEscalationStore();
  const { server, baseUrl } = await startTestServer({
    escalationStore,
    sendMessage: async (payload) => {
      attempts.push(payload.to);
      if (payload.to === "+22670000000") {
        const error = new Error("provider_failed");
        error.providerStatus = 500;
        error.providerCode = "bad_payload";
        throw error;
      }
      return { status: "ok", code: 202, providerMessageId: "wamid.second" };
    }
  });

  try {
    const response = await fetch(`${baseUrl}/v1/alerts/collision`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contacts: [
          { name: "Contact 1", phoneNumber: "+22670000000" },
          { name: "Contact 2", phoneNumber: "+22671000000" },
          { name: "Contact 3", phoneNumber: "+22672000000" }
        ],
        location: { latitude: 12.3714, longitude: -1.5197 }
      })
    });

    const body = await response.json();
    assert.equal(response.status, 200);
    assert.deepEqual(attempts, ["+22670000000", "+22671000000"]);
    assert.equal(body.sentCount, 1);
    assert.equal(body.failedCount, 1);
    assert.equal(body.escalation.pendingContacts, 1);
    assert.equal(escalationStore.incidents[0].nextIndex, 2);
  } finally {
    server.close();
  }
});

test("POST /v1/alerts/test returns 503 when provider dispatch fails", async () => {
  const { server, baseUrl, alertStore } = await startTestServer({
    sendMessage: async () => {
      const error = new Error("provider_failed");
      error.providerStatus = 500;
      error.providerCode = "bad_payload";
      error.body = "sensitive provider body";
      throw error;
    }
  });

  try {
    const response = await fetch(`${baseUrl}/v1/alerts/test`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contact: {
          name: "Contact",
          phoneNumber: "+22670000000"
        }
      })
    });

    const body = await response.json();
    assert.equal(response.status, 503);
    assert.equal(body.error, "newagent_unavailable");
    assert.match(body.alertId, uuidPattern);
    assert.equal(body.providerCode, "bad_payload");

    const stored = await alertStore.findById(body.alertId);
    assert.equal(stored.status, "failed");
    assert.equal(stored.providerCode, "bad_payload");
  } finally {
    server.close();
  }
});

test("POST /v1/alerts/test returns 503 when provider has no message proof", async () => {
  const { server, baseUrl, alertStore } = await startTestServer({
    sendMessage: async () => {
      const error = new Error("provider_no_message_id");
      error.providerStatus = 200;
      error.providerCode = "provider_no_message_id";
      error.providerBodySnippet = "{\"reply\":\"message accepted\"}";
      throw error;
    }
  });

  try {
    const response = await fetch(`${baseUrl}/v1/alerts/test`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contact: {
          name: "Contact",
          phoneNumber: "+22670000000"
        }
      })
    });

    const body = await response.json();
    assert.equal(response.status, 503);
    assert.equal(body.error, "newagent_unavailable");
    assert.equal(body.providerCode, "provider_no_message_id");

    const stored = await alertStore.findById(body.alertId);
    assert.equal(stored.status, "failed");
    assert.equal(stored.providerCode, "provider_no_message_id");
  } finally {
    server.close();
  }
});

test("POST /v1/alerts/test does not send when alert persistence fails", async () => {
  let sendCalled = false;
  const { server, baseUrl } = await startTestServer({
    sendMessage: async () => {
      sendCalled = true;
      return { status: "ok", code: 202, providerMessageId: "wamid.unreachable" };
    },
    alertStore: {
      async create() {
        throw new Error("relation_alerts_missing");
      },
      async markSent() {},
      async markFailed() {},
      async findById() {
        return null;
      }
    }
  });

  try {
    const response = await fetch(`${baseUrl}/v1/alerts/test`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contact: {
          name: "Contact",
          phoneNumber: "+22670000000"
        }
      })
    });

    const body = await response.json();
    assert.equal(response.status, 503);
    assert.equal(body.error, "alert_store_unavailable");
    assert.match(body.alertId, uuidPattern);
    assert.equal(sendCalled, false);
  } finally {
    server.close();
  }
});

test("contacts consent: soft launch sends without attestation but logs it", async () => {
  const { server, baseUrl, alertStore, warnings } = await startTestServer({
    sendMessage: async () => ({ status: "ok", code: 202, providerMessageId: "wamid.soft" })
  });

  try {
    const response = await fetch(`${baseUrl}/v1/alerts/test`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ contact: { name: "Contact", phoneNumber: "+22670000000" } })
    });

    const body = await response.json();
    assert.equal(response.status, 200);
    assert.equal(body.status, "sent");
    assert.ok(warnings.some((entry) => entry.event === "whatsapp.contacts_consent.missing"));

    const stored = await alertStore.findById(body.alertId);
    assert.equal(stored.contactsConsent, null);
  } finally {
    server.close();
  }
});

test("contacts consent: the attestation is recorded on the alert", async () => {
  const { server, baseUrl, alertStore, warnings } = await startTestServer({
    sendMessage: async () => ({ status: "ok", code: 202, providerMessageId: "wamid.ack" })
  });

  try {
    const response = await fetch(`${baseUrl}/v1/alerts/test`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contact: { name: "Contact", phoneNumber: "+22670000000" },
        contactsConsent: true
      })
    });

    const body = await response.json();
    assert.equal(response.status, 200);
    assert.equal(warnings.length, 0);

    const stored = await alertStore.findById(body.alertId);
    assert.equal(stored.contactsConsent, true);
  } finally {
    server.close();
  }
});

test("contacts consent: hard enforcement rejects an alert without attestation", async () => {
  let sendCalled = false;
  const { server, baseUrl } = await startTestServer({
    requireContactsConsent: true,
    sendMessage: async () => {
      sendCalled = true;
      return { status: "ok", code: 202, providerMessageId: "wamid.blocked" };
    }
  });

  try {
    const response = await fetch(`${baseUrl}/v1/alerts/collision`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contacts: [{ name: "Contact 1", phoneNumber: "+22670000000" }],
        location: { latitude: 12.3714, longitude: -1.5197 }
      })
    });

    const body = await response.json();
    assert.equal(response.status, 422);
    assert.equal(body.error, "contacts_consent_required");
    assert.equal(sendCalled, false);
  } finally {
    server.close();
  }
});

test("contacts consent: hard enforcement passes when the attestation is present", async () => {
  const { server, baseUrl } = await startTestServer({
    requireContactsConsent: true,
    sendMessage: async () => ({ status: "ok", code: 202, providerMessageId: "wamid.okconsent" })
  });

  try {
    const response = await fetch(`${baseUrl}/v1/alerts/collision`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contacts: [{ name: "Contact 1", phoneNumber: "+22670000000" }],
        location: { latitude: 12.3714, longitude: -1.5197 },
        contactsConsent: { acknowledged: true }
      })
    });

    const body = await response.json();
    assert.equal(response.status, 200);
    assert.equal(body.status, "sent");
  } finally {
    server.close();
  }
});

async function startTestServer({
  sendMessage,
  alertStore = createMemoryAlertStore(),
  escalationStore = createMemoryEscalationStore(),
  requireContactsConsent = false
}) {
  const warnings = [];
  const app = express();
  app.use(express.json());
  app.use("/v1/alerts", createAlertsRouter({
    sendMessage,
    alertStore,
    escalationStore,
    requireContactsConsent,
    logger: {
      info() {},
      warn(event, detail) {
        warnings.push({ event, detail });
      }
    }
  }));

  const server = app.listen(0, "127.0.0.1");
  await once(server, "listening");

  const address = server.address();
  return {
    server,
    baseUrl: `http://127.0.0.1:${address.port}`,
    alertStore,
    warnings
  };
}

function createMemoryEscalationStore() {
  const incidents = [];
  return {
    incidents,
    async createIncident(incident) {
      incidents.push(incident);
    },
    async claimDueIncidents() {
      return [];
    },
    async anyContactRead() {
      return false;
    },
    async advance() {},
    async markResolved() {},
    async releaseLease() {}
  };
}

function createMemoryAlertStore() {
  const records = new Map();

  return {
    async create(alert) {
      records.set(alert.id, {
        ...alert,
        status: "queued",
        providerMessageId: null,
        providerStatus: null,
        providerCode: null
      });
    },

    async markSent(id, result) {
      const record = records.get(id);
      Object.assign(record, {
        status: "sent",
        providerMessageId: result.providerMessageId,
        providerStatus: result.code ?? null,
        providerCode: result.status ?? null
      });
    },

    async markFailed(id, error) {
      const record = records.get(id);
      Object.assign(record, {
        status: "failed",
        providerStatus: error.providerStatus ?? null,
        providerCode: error.providerCode ?? error.message ?? null
      });
    },

    async findById(id) {
      return records.get(id) ?? null;
    }
  };
}
