import { Router, static as expressStatic } from "express";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { config } from "../config.js";
import { checkDatabase } from "../db/pool.js";
import { createAdminAuth, createLoginLimiter } from "../services/adminAuth.js";
import { createAdminStore } from "../services/adminStore.js";
import { checkNewagent } from "../services/newagent.js";

const webRoot = join(dirname(fileURLToPath(import.meta.url)), "../admin-web");

export function createAdminRouter({
  store = createAdminStore(),
  auth = createAdminAuth({
    username: config.adminUsername,
    password: config.adminPassword,
    sessionSecret: config.adminSessionSecret,
    sessionHours: config.adminSessionHours,
    secureCookies: config.env === "production"
  }),
  loginLimiter = createLoginLimiter(),
  healthCheck = defaultHealthCheck,
  logger = console
} = {}) {
  const router = Router();

  router.use(adminSecurityHeaders);
  router.use("/assets", expressStatic(join(webRoot, "assets"), {
    fallthrough: false,
    maxAge: "5m"
  }));

  router.get("/login", (request, response) => {
    if (auth.verifySession(request)) return response.redirect(302, "/admin");
    return response.sendFile(join(webRoot, "login.html"));
  });

  router.post("/api/login", (request, response) => {
    if (!auth.configured) {
      return response.status(503).json({ error: "admin_not_configured" });
    }

    const limiterKey = request.ip ?? request.socket.remoteAddress ?? "unknown";
    const allowance = loginLimiter.check(limiterKey);
    if (!allowance.allowed) {
      response.set("Retry-After", String(allowance.retryAfterSeconds));
      return response.status(429).json({
        error: "too_many_attempts",
        retryAfterSeconds: allowance.retryAfterSeconds
      });
    }

    const username = typeof request.body?.username === "string" ? request.body.username : "";
    const password = typeof request.body?.password === "string" ? request.body.password : "";
    if (!auth.authenticate(username, password)) {
      loginLimiter.fail(limiterKey);
      return response.status(401).json({ error: "invalid_credentials" });
    }

    loginLimiter.succeed(limiterKey);
    response.set("Set-Cookie", auth.sessionCookie(auth.createSession()));
    return response.status(204).end();
  });

  router.post("/api/logout", (request, response) => {
    response.set("Set-Cookie", auth.expiredCookie());
    return response.status(204).end();
  });

  router.get("/", requireAdminPage(auth), (_request, response) => {
    response.set("Cache-Control", "no-store");
    return response.sendFile(join(webRoot, "index.html"));
  });

  router.use("/api", requireAdminAPI(auth));

  router.get("/api/overview", async (_request, response) => {
    await sendAdminResponse(response, logger, () => store.getOverview());
  });

  router.get("/api/users", async (request, response) => {
    await sendAdminResponse(response, logger, () => store.listUsers({
      search: String(request.query.search ?? ""),
      limit: parseInteger(request.query.limit, 50),
      offset: parseInteger(request.query.offset, 0)
    }));
  });

  router.get("/api/trips", async (request, response) => {
    await sendAdminResponse(response, logger, () => store.listTrips({
      limit: parseInteger(request.query.limit, 50),
      offset: parseInteger(request.query.offset, 0)
    }));
  });

  router.get("/api/alerts", async (request, response) => {
    await sendAdminResponse(response, logger, () => store.listAlerts({
      limit: parseInteger(request.query.limit, 50),
      offset: parseInteger(request.query.offset, 0)
    }));
  });

  router.get("/api/incidents", async (request, response) => {
    await sendAdminResponse(response, logger, () => store.listIncidents({
      limit: parseInteger(request.query.limit, 50),
      offset: parseInteger(request.query.offset, 0)
    }));
  });

  router.get("/api/system", async (_request, response) => {
    await sendAdminResponse(response, logger, healthCheck);
  });

  return router;
}

function requireAdminPage(auth) {
  return (request, response, next) => {
    if (!auth.configured) {
      return response.status(503).send("Dashboard admin non configuré.");
    }
    if (!auth.verifySession(request)) {
      return response.redirect(302, "/admin/login");
    }
    return next();
  };
}

function requireAdminAPI(auth) {
  return (request, response, next) => {
    if (!auth.configured) {
      return response.status(503).json({ error: "admin_not_configured" });
    }
    if (!auth.verifySession(request)) {
      return response.status(401).json({ error: "unauthorized" });
    }
    response.set("Cache-Control", "no-store");
    return next();
  };
}

async function defaultHealthCheck() {
  const [database, whatsapp] = await Promise.allSettled([
    checkDatabase(),
    checkNewagent()
  ]);
  return {
    generatedAt: new Date().toISOString(),
    api: { status: "ok", version: config.version },
    database: settledHealth(database),
    whatsapp: settledHealth(whatsapp),
    admin: { status: "ok" }
  };
}

function settledHealth(result) {
  return result.status === "fulfilled" ? result.value : { status: "error" };
}

async function sendAdminResponse(response, logger, operation) {
  try {
    return response.status(200).json(await operation());
  } catch (error) {
    logger.warn("admin.dashboard.query.failure", {
      code: error.code ?? error.message ?? "unknown"
    });
    return response.status(503).json({ error: "admin_data_unavailable" });
  }
}

function adminSecurityHeaders(_request, response, next) {
  response.set({
    "Content-Security-Policy": [
      "default-src 'self'",
      "script-src 'self'",
      "style-src 'self'",
      "img-src 'self' data:",
      "connect-src 'self'",
      "font-src 'self'",
      "object-src 'none'",
      "base-uri 'self'",
      "form-action 'self'",
      "frame-ancestors 'none'"
    ].join("; "),
    "Referrer-Policy": "no-referrer",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Permissions-Policy": "camera=(), microphone=(), geolocation=()"
  });
  next();
}

function parseInteger(value, fallback) {
  const parsed = Number.parseInt(String(value ?? ""), 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}
