import assert from "node:assert/strict";
import { once } from "node:events";
import { test } from "node:test";
import express from "express";
import { createAdminRouter } from "../src/routes/admin.js";
import { createAdminAuth, createLoginLimiter } from "../src/services/adminAuth.js";
import { createEmptyAdminStore } from "../src/services/adminStore.js";

const credentials = {
  username: "guy",
  password: "mot-de-passe-solide",
  sessionSecret: "s".repeat(48),
  sessionHours: 8,
  secureCookies: false
};

test("admin dashboard redirects pages and rejects APIs without a session", async () => {
  const context = await startAdminServer();
  try {
    const page = await fetch(`${context.baseUrl}/admin`, { redirect: "manual" });
    assert.equal(page.status, 302);
    assert.equal(page.headers.get("location"), "/admin/login");

    const api = await fetch(`${context.baseUrl}/admin/api/overview`);
    assert.equal(api.status, 401);
    assert.deepEqual(await api.json(), { error: "unauthorized" });
  } finally {
    context.server.close();
  }
});

test("valid admin credentials create a protected signed session", async () => {
  const context = await startAdminServer();
  try {
    const invalid = await fetch(`${context.baseUrl}/admin/api/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username: "guy", password: "incorrect" })
    });
    assert.equal(invalid.status, 401);
    assert.equal(invalid.headers.get("set-cookie"), null);

    const login = await fetch(`${context.baseUrl}/admin/api/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username: credentials.username, password: credentials.password })
    });
    assert.equal(login.status, 204);
    const cookie = login.headers.get("set-cookie");
    assert.match(cookie, /^viim_admin_session=/);
    assert.match(cookie, /HttpOnly/);
    assert.match(cookie, /SameSite=Strict/);

    const page = await fetch(`${context.baseUrl}/admin`, {
      headers: { Cookie: cookie },
      redirect: "manual"
    });
    assert.equal(page.status, 200);
    assert.match(await page.text(), /Poste de contrôle/);
    assert.match(page.headers.get("content-security-policy"), /frame-ancestors 'none'/);

    const overview = await fetch(`${context.baseUrl}/admin/api/overview`, {
      headers: { Cookie: cookie }
    });
    assert.equal(overview.status, 200);
    const body = await overview.json();
    assert.equal(body.metrics.circleUsers, 2);
    assert.equal(overview.headers.get("cache-control"), "no-store");
  } finally {
    context.server.close();
  }
});

test("admin access fails closed when production-grade secrets are missing", async () => {
  const context = await startAdminServer({
    auth: createAdminAuth({
      username: "admin",
      password: "short",
      sessionSecret: "short",
      secureCookies: false
    })
  });
  try {
    const login = await fetch(`${context.baseUrl}/admin/api/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username: "admin", password: "short" })
    });
    assert.equal(login.status, 503);
    assert.deepEqual(await login.json(), { error: "admin_not_configured" });

    const page = await fetch(`${context.baseUrl}/admin`, { redirect: "manual" });
    assert.equal(page.status, 503);
  } finally {
    context.server.close();
  }
});

test("login limiter blocks repeated password attempts for the same client", () => {
  let clock = 1_000;
  const limiter = createLoginLimiter({
    maxAttempts: 2,
    windowMs: 10_000,
    now: () => clock
  });

  assert.equal(limiter.check("client").allowed, true);
  limiter.fail("client");
  assert.equal(limiter.check("client").allowed, true);
  limiter.fail("client");
  assert.equal(limiter.check("client").allowed, false);
  clock += 10_001;
  assert.equal(limiter.check("client").allowed, true);
});

test("empty admin store explains when PostgreSQL is not configured", async () => {
  const overview = await createEmptyAdminStore().getOverview();
  assert.equal(overview.dataSourceStatus, "not_configured");
  assert.equal(overview.metrics.trips30d, 0);
  assert.equal(overview.coverage.medical, "never_stored");
});

async function startAdminServer({
  auth = createAdminAuth(credentials),
  store = createFixtureStore()
} = {}) {
  const app = express();
  app.use(express.json());
  app.use("/admin", createAdminRouter({
    auth,
    store,
    healthCheck: async () => ({
      api: { status: "ok", version: "test" },
      database: { status: "ok" },
      whatsapp: { status: "ok" },
      admin: { status: "ok" }
    }),
    logger: { warn() {} }
  }));
  const server = app.listen(0, "127.0.0.1");
  await once(server, "listening");
  const address = server.address();
  return { server, baseUrl: `http://127.0.0.1:${address.port}` };
}

function createFixtureStore() {
  return {
    async getOverview() {
      const overview = await createEmptyAdminStore().getOverview();
      overview.dataSourceStatus = "connected";
      overview.metrics.circleUsers = 2;
      return overview;
    },
    async listUsers() { return { total: 0, items: [] }; },
    async listTrips() { return { total: 0, items: [] }; },
    async listAlerts() { return { total: 0, items: [] }; },
    async listIncidents() { return { total: 0, items: [] }; }
  };
}
