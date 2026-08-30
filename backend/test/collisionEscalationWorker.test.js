import assert from "node:assert/strict";
import { test } from "node:test";
import { runCollisionEscalationTick } from "../src/services/collisionEscalationWorker.js";

const LOCATION = { latitude: 12.3714, longitude: -1.5197 };

function incident(overrides = {}) {
  return {
    incidentId: "11111111-1111-4111-8111-111111111111",
    driverName: "Guy",
    location: LOCATION,
    contacts: [
      { name: "Contact 1", phoneNumber: "+22670000000" },
      { name: "Contact 2", phoneNumber: "+22671000000" },
      { name: "Contact 3", phoneNumber: "+22672000000" }
    ],
    nextIndex: 1,
    ...overrides
  };
}

function fakeStore(due, { read = false } = {}) {
  const calls = { advance: [], resolved: [], released: [] };
  return {
    calls,
    async claimDueIncidents() {
      return due;
    },
    async anyContactRead() {
      return read;
    },
    async advance(id, index) {
      calls.advance.push({ id, index });
    },
    async markResolved(id, status) {
      calls.resolved.push({ id, status });
    },
    async releaseLease(id) {
      calls.released.push(id);
    }
  };
}

function fakeAlertStore() {
  const created = [];
  return {
    created,
    async create(alert) {
      created.push(alert);
    },
    async markSent() {},
    async markFailed() {}
  };
}

const silentLogger = { info() {}, warn() {} };

test("escalates to the next contact when nobody has read", async () => {
  const store = fakeStore([incident()]);
  const alertStore = fakeAlertStore();
  const sent = [];

  const count = await runCollisionEscalationTick({
    store,
    alertStore,
    logger: silentLogger,
    sendMessage: async (payload) => {
      sent.push(payload.to);
      return { status: "ok", code: 202, providerMessageId: "wamid.esc" };
    }
  });

  assert.equal(count, 1);
  assert.deepEqual(sent, ["+22671000000"]);
  assert.equal(alertStore.created[0].contactIndex, 1);
  assert.equal(alertStore.created[0].incidentId, incident().incidentId);
  assert.deepEqual(store.calls.advance, [{ id: incident().incidentId, index: 1 }]);
  assert.equal(store.calls.resolved.length, 0);
});

test("stops the cascade when a contact has read the alert", async () => {
  const store = fakeStore([incident()], { read: true });
  const sent = [];

  await runCollisionEscalationTick({
    store,
    alertStore: fakeAlertStore(),
    logger: silentLogger,
    sendMessage: async (payload) => {
      sent.push(payload.to);
      return { status: "ok", code: 202, providerMessageId: "x" };
    }
  });

  assert.deepEqual(sent, []);
  assert.deepEqual(store.calls.resolved, [{ id: incident().incidentId, status: "read" }]);
  assert.equal(store.calls.advance.length, 0);
});

test("marks the incident exhausted when no contact is left", async () => {
  const store = fakeStore([incident({ nextIndex: 3 })]);
  const sent = [];

  await runCollisionEscalationTick({
    store,
    alertStore: fakeAlertStore(),
    logger: silentLogger,
    sendMessage: async (payload) => {
      sent.push(payload.to);
      return { status: "ok", code: 202, providerMessageId: "x" };
    }
  });

  assert.deepEqual(sent, []);
  assert.deepEqual(store.calls.resolved, [{ id: incident().incidentId, status: "exhausted" }]);
});

test("still advances when the escalation send fails", async () => {
  const store = fakeStore([incident()]);

  await runCollisionEscalationTick({
    store,
    alertStore: fakeAlertStore(),
    logger: silentLogger,
    sendMessage: async () => {
      const error = new Error("provider_failed");
      error.providerCode = "http_error";
      throw error;
    }
  });

  assert.deepEqual(store.calls.advance, [{ id: incident().incidentId, index: 1 }]);
  assert.equal(store.calls.released.length, 0);
});

test("releases the lease when a tick step throws unexpectedly", async () => {
  const store = fakeStore([incident()]);
  store.anyContactRead = async () => {
    throw new Error("db down");
  };

  const count = await runCollisionEscalationTick({
    store,
    alertStore: fakeAlertStore(),
    logger: silentLogger,
    sendMessage: async () => ({ status: "ok", code: 202, providerMessageId: "x" })
  });

  assert.equal(count, 1);
  assert.deepEqual(store.calls.released, [incident().incidentId]);
});

test("does nothing when no incident is due", async () => {
  const store = fakeStore([]);
  const count = await runCollisionEscalationTick({
    store,
    alertStore: fakeAlertStore(),
    logger: silentLogger,
    sendMessage: async () => ({ status: "ok", code: 202, providerMessageId: "x" })
  });
  assert.equal(count, 0);
});
