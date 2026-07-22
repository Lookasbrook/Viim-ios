import { createHash, randomBytes, randomUUID } from "node:crypto";
import { Router } from "express";
import { config } from "../config.js";
import { createCircleStore } from "../services/circleStore.js";
import { createPushNotifier } from "../services/pushNotifier.js";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const apnsTokenPattern = /^[0-9a-f]{32,256}$/i;
const invitationLifetimeMs = 7 * 24 * 60 * 60 * 1_000;
const incidentRateWindowMs = 10 * 60 * 1_000;
const maxIncidentsPerWindow = 5;

export function createCircleRouter({
  store = createCircleStore(),
  notifier = createPushNotifier(),
  logger = console,
  publicBaseUrl = config.publicBaseUrl,
  now = () => new Date()
} = {}) {
  const router = Router();
  const recentIncidents = new Map();

  router.post("/register", async (request, response) => {
    const installationId = cleanRequiredString(request.body?.installationId, 64);
    const displayName = cleanRequiredString(request.body?.displayName, 80);
    const pushEnvironment = parsePushEnvironment(request.body?.pushEnvironment);
    if (!installationId || !uuidPattern.test(installationId) || !displayName || !pushEnvironment) {
      return response.status(422).json({ error: "invalid_registration" });
    }

    const requestedToken = cleanRequiredString(request.body?.registrationToken, 128);
    if (requestedToken && !/^[A-Za-z0-9_-]{43,128}$/.test(requestedToken)) {
      return response.status(422).json({ error: "invalid_registration" });
    }
    const authToken = requestedToken ?? randomBytes(32).toString("base64url");
    const id = randomUUID();
    try {
      const user = await store.registerUser({
        id,
        installationId,
        displayName,
        authTokenHash: sha256(authToken),
        pushEnvironment
      });
      if (!user) {
        return response.status(409).json({ error: "installation_already_registered" });
      }
      return response.status(201).json({
        userId: user.id,
        authToken,
        displayName: user.displayName,
        statsSharing: user.statsSharing
      });
    } catch (error) {
      if (error.code === "23505") {
        return response.status(409).json({ error: "installation_already_registered" });
      }
      logger.warn("circle.registration.failure", { code: error.message ?? null });
      return response.status(503).json({ error: "circle_unavailable" });
    }
  });

  router.use(async (request, response, next) => {
    const token = bearerToken(request.headers.authorization);
    if (!token) {
      return response.status(401).json({ error: "unauthorized" });
    }
    try {
      const user = await store.authenticate(sha256(token));
      if (!user) {
        return response.status(401).json({ error: "unauthorized" });
      }
      request.circleUser = user;
      return next();
    } catch (error) {
      logger.warn("circle.authentication.failure", { code: error.message ?? null });
      return response.status(503).json({ error: "circle_unavailable" });
    }
  });

  router.patch("/me", async (request, response) => {
    const parsed = parseProfileChanges(request.body);
    if (!parsed.ok) {
      return response.status(422).json({ error: parsed.error });
    }
    try {
      const user = await store.updateProfile(request.circleUser.id, parsed.value);
      return response.status(200).json(publicUser(user));
    } catch (error) {
      logger.warn("circle.profile.failure", { code: error.message ?? null });
      return response.status(503).json({ error: "circle_unavailable" });
    }
  });

  router.post("/invitations", async (request, response) => {
    const token = randomBytes(32).toString("base64url");
    const expiresAt = new Date(now().getTime() + invitationLifetimeMs);
    try {
      await store.createInvitation({
        id: randomUUID(),
        inviterUserId: request.circleUser.id,
        tokenHash: sha256(token),
        expiresAt
      });
      return response.status(201).json({
        inviteURL: `${publicBaseUrl.replace(/\/$/, "")}/join/${encodeURIComponent(token)}`,
        expiresAt
      });
    } catch (error) {
      logger.warn("circle.invitation.failure", { code: error.message ?? null });
      return response.status(503).json({ error: "circle_unavailable" });
    }
  });

  router.post("/invitations/preview", async (request, response) => {
    const invitation = await loadInvitation(store, request.body?.token, now, logger, response);
    if (!invitation) return;
    return response.status(200).json({
      inviterDisplayName: invitation.inviterDisplayName,
      expiresAt: invitation.expiresAt
    });
  });

  router.post("/invitations/accept", async (request, response) => {
    const invitation = await loadInvitation(store, request.body?.token, now, logger, response);
    if (!invitation) return;
    if (invitation.inviterUserId === request.circleUser.id) {
      return response.status(409).json({ error: "cannot_accept_own_invitation" });
    }

    const [firstUserId, secondUserId] = [invitation.inviterUserId, request.circleUser.id].sort();
    try {
      const accepted = await store.acceptInvitation({
        invitationId: invitation.id,
        acceptingUserId: request.circleUser.id,
        firstUserId,
        secondUserId,
        relationshipId: randomUUID()
      });
      if (!accepted) {
        return response.status(409).json({ error: "invitation_no_longer_available" });
      }
      return response.status(200).json({ status: "accepted" });
    } catch (error) {
      logger.warn("circle.invitation.accept.failure", { code: error.message ?? null });
      return response.status(503).json({ error: "circle_unavailable" });
    }
  });

  router.get("/members", async (request, response) => {
    try {
      const members = await store.listMembers(request.circleUser.id);
      return response.status(200).json({ members });
    } catch (error) {
      logger.warn("circle.members.failure", { code: error.message ?? null });
      return response.status(503).json({ error: "circle_unavailable" });
    }
  });

  router.delete("/members/:relationshipId", async (request, response) => {
    if (!uuidPattern.test(request.params.relationshipId ?? "")) {
      return response.status(422).json({ error: "invalid_relationship" });
    }
    try {
      const removed = await store.removeRelationship(
        request.circleUser.id,
        request.params.relationshipId
      );
      if (!removed) {
        return response.status(404).json({ error: "not_found" });
      }
      return response.status(204).end();
    } catch (error) {
      logger.warn("circle.member.remove.failure", { code: error.message ?? null });
      return response.status(503).json({ error: "circle_unavailable" });
    }
  });

  router.put("/stats", async (request, response) => {
    const stats = parseStats(request.body);
    if (!stats.ok) {
      return response.status(422).json({ error: stats.error });
    }
    try {
      await store.upsertStats(request.circleUser.id, stats.value);
      return response.status(204).end();
    } catch (error) {
      logger.warn("circle.stats.failure", { code: error.message ?? null });
      return response.status(503).json({ error: "circle_unavailable" });
    }
  });

  router.post("/incidents", async (request, response) => {
    const incidentPayload = parseIncident(request.body);
    if (!incidentPayload.ok) {
      return response.status(422).json({ error: incidentPayload.error });
    }
    if (!mayCreateIncident(recentIncidents, request.circleUser.id, now())) {
      return response.status(429).json({ error: "incident_rate_limited" });
    }

    try {
      const recipients = await store.listIncidentRecipients(request.circleUser.id);
      const incident = {
        id: randomUUID(),
        sourceUserId: request.circleUser.id,
        ...incidentPayload.value
      };
      await store.createIncident({
        incident,
        recipientIds: recipients.map((recipient) => recipient.id)
      });

      const pushResults = await Promise.allSettled(
        recipients.map((recipient) => notifier.sendIncident({
          recipient,
          incident,
          sourceDisplayName: request.circleUser.displayName
        }))
      );
      const pushSentCount = pushResults.filter(
        (result) => result.status === "fulfilled" && result.value?.status === "sent"
      ).length;
      for (const result of pushResults) {
        if (result.status === "rejected") {
          logger.warn("circle.push.failure", {
            incidentId: incident.id,
            code: result.reason?.message ?? null,
            providerStatus: result.reason?.statusCode ?? null
          });
        }
      }

      return response.status(201).json({
        incidentId: incident.id,
        recipientsCount: recipients.length,
        pushSentCount,
        storedInApp: true
      });
    } catch (error) {
      logger.warn("circle.incident.failure", { code: error.message ?? null });
      return response.status(503).json({ error: "circle_unavailable" });
    }
  });

  router.get("/inbox", async (request, response) => {
    try {
      const notifications = await store.listInbox(request.circleUser.id, 50);
      return response.status(200).json({ notifications });
    } catch (error) {
      logger.warn("circle.inbox.failure", { code: error.message ?? null });
      return response.status(503).json({ error: "circle_unavailable" });
    }
  });

  router.post("/inbox/:notificationId/read", async (request, response) => {
    if (!uuidPattern.test(request.params.notificationId ?? "")) {
      return response.status(422).json({ error: "invalid_notification" });
    }
    try {
      const updated = await store.markNotificationRead(
        request.circleUser.id,
        request.params.notificationId
      );
      if (!updated) {
        return response.status(404).json({ error: "not_found" });
      }
      return response.status(204).end();
    } catch (error) {
      logger.warn("circle.inbox.read.failure", { code: error.message ?? null });
      return response.status(503).json({ error: "circle_unavailable" });
    }
  });

  return router;
}

export function createJoinRouter() {
  const router = Router();
  router.get("/:token", (request, response) => {
    const token = cleanRequiredString(request.params.token, 128);
    if (!token || !/^[A-Za-z0-9_-]{32,128}$/.test(token)) {
      return response.status(404).send("Invitation introuvable");
    }
    const appURL = `viim://join?token=${encodeURIComponent(token)}`;
    response
      .status(200)
      .type("html")
      .send(`<!doctype html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Invitation Viim</title><style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#f4f7fb;color:#10233f;display:grid;place-items:center;min-height:100vh;margin:0}.card{background:white;border-radius:24px;padding:32px;max-width:420px;box-shadow:0 16px 50px #10233f22;text-align:center}a{display:inline-block;background:#0756a3;color:white;text-decoration:none;padding:14px 22px;border-radius:14px;font-weight:700}</style></head>
<body><main class="card"><h1>Rejoindre un proche sur Viim</h1><p>Ouvrez l’invitation dans l’app pour choisir si vous souhaitez rejoindre son cercle de confiance.</p><a href="${appURL}">Ouvrir Viim</a></main></body></html>`);
  });
  return router;
}

async function loadInvitation(store, rawToken, now, logger, response) {
  const token = cleanRequiredString(rawToken, 128);
  if (!token || !/^[A-Za-z0-9_-]{32,128}$/.test(token)) {
    response.status(422).json({ error: "invalid_invitation" });
    return null;
  }
  try {
    const invitation = await store.findInvitation(sha256(token));
    if (!invitation) {
      response.status(404).json({ error: "invitation_not_found" });
      return null;
    }
    if (invitation.acceptedByUserId) {
      response.status(409).json({ error: "invitation_already_used" });
      return null;
    }
    if (invitation.expiresAt <= now()) {
      response.status(410).json({ error: "invitation_expired" });
      return null;
    }
    return invitation;
  } catch (error) {
    logger.warn("circle.invitation.lookup.failure", { code: error.message ?? null });
    response.status(503).json({ error: "circle_unavailable" });
    return null;
  }
}

function parseProfileChanges(body) {
  if (!body || typeof body !== "object") {
    return { ok: false, error: "invalid_profile" };
  }
  const value = {};
  if (body.displayName !== undefined) {
    const displayName = cleanRequiredString(body.displayName, 80);
    if (!displayName) return { ok: false, error: "invalid_display_name" };
    value.displayName = displayName;
  }
  if (body.pushToken !== undefined) {
    if (body.pushToken !== null && !apnsTokenPattern.test(body.pushToken)) {
      return { ok: false, error: "invalid_push_token" };
    }
    value.pushToken = body.pushToken?.toLowerCase() ?? null;
  }
  if (body.pushEnvironment !== undefined) {
    const environment = parsePushEnvironment(body.pushEnvironment);
    if (!environment) return { ok: false, error: "invalid_push_environment" };
    value.pushEnvironment = environment;
  }
  if (body.statsSharing !== undefined) {
    if (typeof body.statsSharing !== "boolean") {
      return { ok: false, error: "invalid_stats_sharing" };
    }
    value.statsSharing = body.statsSharing;
  }
  if (Object.keys(value).length === 0) {
    return { ok: false, error: "empty_profile_update" };
  }
  return { ok: true, value };
}

function parseStats(body) {
  const score = body?.score === null ? null : Number(body?.score);
  const tripsCount = Number(body?.tripsCount);
  const distanceKm = Number(body?.distanceKm);
  const safeStreak = Number(body?.safeStreak);
  const periodStart = new Date(body?.periodStart);
  if (score !== null && (!Number.isInteger(score) || score < 0 || score > 100)) {
    return { ok: false, error: "invalid_stats" };
  }
  if (!Number.isInteger(tripsCount) || tripsCount < 0 || tripsCount > 100_000) {
    return { ok: false, error: "invalid_stats" };
  }
  if (!Number.isFinite(distanceKm) || distanceKm < 0 || distanceKm > 10_000_000) {
    return { ok: false, error: "invalid_stats" };
  }
  if (!Number.isInteger(safeStreak) || safeStreak < 0 || safeStreak > 100_000) {
    return { ok: false, error: "invalid_stats" };
  }
  if (Number.isNaN(periodStart.getTime())) {
    return { ok: false, error: "invalid_stats" };
  }
  return { ok: true, value: { score, tripsCount, distanceKm, safeStreak, periodStart } };
}

function parseIncident(body) {
  const latitude = Number(body?.location?.latitude);
  const longitude = Number(body?.location?.longitude);
  const accuracyMeters = body?.location?.accuracyMeters === undefined
    ? null
    : Number(body.location.accuracyMeters);
  const occurredAt = new Date(body?.occurredAt);
  const severity = ["suspected", "confirmed", "test"].includes(body?.severity)
    ? body.severity
    : null;
  if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90 ||
      !Number.isFinite(longitude) || longitude < -180 || longitude > 180 ||
      (accuracyMeters !== null && (!Number.isFinite(accuracyMeters) || accuracyMeters < 0)) ||
      Number.isNaN(occurredAt.getTime()) || !severity) {
    return { ok: false, error: "invalid_incident" };
  }
  return {
    ok: true,
    value: { latitude, longitude, accuracyMeters, occurredAt, severity }
  };
}

function mayCreateIncident(recentIncidents, userId, date) {
  const cutoff = date.getTime() - incidentRateWindowMs;
  const recent = (recentIncidents.get(userId) ?? []).filter((timestamp) => timestamp > cutoff);
  if (recent.length >= maxIncidentsPerWindow) return false;
  recent.push(date.getTime());
  recentIncidents.set(userId, recent);
  return true;
}

function bearerToken(header) {
  if (typeof header !== "string" || !header.startsWith("Bearer ")) return null;
  const token = header.slice(7).trim();
  return token.length >= 32 && token.length <= 256 ? token : null;
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function cleanRequiredString(value, maxLength = 256) {
  if (typeof value !== "string") return null;
  const cleaned = value.trim().replace(/\s+/g, " ");
  return cleaned.length > 0 && cleaned.length <= maxLength ? cleaned : null;
}

function parsePushEnvironment(value) {
  return value === "sandbox" || value === "production" ? value : null;
}

function publicUser(user) {
  return {
    userId: user.id,
    displayName: user.displayName,
    statsSharing: user.statsSharing,
    pushConfigured: Boolean(user.pushToken)
  };
}
