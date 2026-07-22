import { Router } from "express";
import { randomUUID } from "node:crypto";
import { createAlertStore } from "../services/alertStore.js";
import { sendWhatsAppMessage } from "../services/newagent.js";

// E.164 : indicatif international explicite, 8 a 15 chiffres au total.
// Les numeros burkinabe (+226XXXXXXXX) restent valides ; les contacts des
// utilisateurs hors Burkina (ex. +1 Canada) le deviennent aussi.
const e164PhonePattern = /^\+[1-9]\d{6,14}$/;
const maxContactsPerAlert = 4;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function createAlertsRouter({
  sendMessage = sendWhatsAppMessage,
  logger = console,
  alertStore = createAlertStore()
} = {}) {
  const router = Router();

  router.post("/test", async (request, response) => {
    const parsed = parseSingleContactRequest(request.body);
    if (!parsed.ok) {
      return response.status(422).json({ error: parsed.error });
    }

    const driverName = cleanOptionalString(request.body.driverName) ?? "Viim";
    const message = [
      `Test Viim : ${driverName} vérifie ses alertes famille.`,
      "Si vous recevez ce message, son canal WhatsApp d'urgence est prêt."
    ].join(" ");

    return dispatchWhatsApp(response, sendMessage, logger, alertStore, {
      kind: "alert_test",
      to: parsed.contact.phoneNumber,
      message,
      metadata: {
        contactName: parsed.contact.name
      }
    });
  });

  router.post("/location-share", async (request, response) => {
    const parsed = parseSingleContactRequest(request.body);
    if (!parsed.ok) {
      return response.status(422).json({ error: parsed.error });
    }

    const location = parseLocation(request.body.location);
    if (!location.ok) {
      return response.status(422).json({ error: location.error });
    }

    const driverName = cleanOptionalString(request.body.driverName) ?? "Votre proche";
    const mapsUrl = `https://maps.google.com/?q=${location.value.latitude},${location.value.longitude}`;
    const message = [
      `${driverName} partage sa position avec vous via Viim.`,
      `Coordonnées : ${location.value.latitude.toFixed(6)}, ${location.value.longitude.toFixed(6)}.`,
      mapsUrl
    ].join(" ");

    return dispatchWhatsApp(response, sendMessage, logger, alertStore, {
      kind: "location_share",
      to: parsed.contact.phoneNumber,
      message,
      metadata: {
        contactName: parsed.contact.name,
        location: location.value
      }
    });
  });

  router.post("/collision", async (request, response) => {
    const contacts = parseContacts(request.body.contacts);
    if (!contacts.ok) {
      return response.status(422).json({ error: contacts.error });
    }

    const location = parseLocation(request.body.location);
    if (!location.ok) {
      return response.status(422).json({ error: location.error });
    }

    const driverName = cleanOptionalString(request.body.driverName) ?? "Un utilisateur Viim";
    const mapsUrl = `https://maps.google.com/?q=${location.value.latitude},${location.value.longitude}`;
    const message = [
      `Alerte Viim : collision confirmée pour ${driverName}.`,
      `Position : ${location.value.latitude.toFixed(6)}, ${location.value.longitude.toFixed(6)}.`,
      mapsUrl
    ].join(" ");

    const medicalProfile = parseMedicalProfile(request.body.medicalProfile);

    const deliveries = [];
    for (const contact of contacts.value) {
      deliveries.push(await dispatchWhatsAppResult(sendMessage, logger, alertStore, {
        kind: "collision",
        to: contact.phoneNumber,
        message,
        metadata: {
          contactName: contact.name,
          contactsCount: contacts.value.length,
          location: location.value,
          incidentId: cleanOptionalString(request.body.incidentId),
          occurredAt: cleanOptionalString(request.body.occurredAt),
          medicalProfile: medicalProfile.value
        }
      }));
    }

    const sentCount = deliveries.filter((delivery) => delivery.statusCode === 200).length;
    if (sentCount === 0) {
      return response.status(deliveries[0].statusCode).json(deliveries[0].body);
    }
    return response.status(200).json({
      status: sentCount === deliveries.length ? "sent" : "partial",
      sentCount,
      failedCount: deliveries.length - sentCount,
      deliveries: deliveries.map((delivery) => delivery.body)
    });
  });

  router.get("/:id", async (request, response) => {
    const alertId = cleanRequiredString(request.params.id);
    if (!alertId || !uuidPattern.test(alertId)) {
      return response.status(422).json({ error: "invalid_alert_id" });
    }

    try {
      const alert = await alertStore.findById(alertId);
      if (!alert) {
        return response.status(404).json({ error: "not_found" });
      }
      return response.status(200).json(alert);
    } catch (error) {
      logger.warn("whatsapp.alert.lookup.failure", {
        alertId,
        providerCode: error.message ?? null
      });
      return response.status(503).json({ error: "alert_status_unavailable" });
    }
  });

  return router;
}

async function dispatchWhatsApp(response, sendMessage, logger, alertStore, payload) {
  const result = await dispatchWhatsAppResult(sendMessage, logger, alertStore, payload);
  return response.status(result.statusCode).json(result.body);
}

async function dispatchWhatsAppResult(sendMessage, logger, alertStore, payload) {
  const alertId = randomUUID();

  try {
    await alertStore.create({ id: alertId, ...payload });
  } catch (error) {
    logger.warn("whatsapp.alert.persist.failure", {
      kind: payload.kind,
      alertId,
      providerCode: error.message ?? null
    });
    return {
      statusCode: 503,
      body: { error: "alert_store_unavailable", alertId }
    };
  }

  try {
    const result = await sendMessage(payload);
    try {
      await alertStore.markSent(alertId, result);
    } catch (error) {
      logger.warn("whatsapp.alert.persist.failure", {
        kind: payload.kind,
        alertId,
        providerCode: error.message ?? null
      });
    }

    logger.info("whatsapp.dispatch.success", {
      kind: payload.kind,
      providerStatus: result.code ?? null,
      providerCode: result.status ?? null,
      providerMessageId: result.providerMessageId ?? null,
      alertId
    });
    return {
      statusCode: 200,
      body: {
        status: "sent",
        alertId,
        providerMessageId: result.providerMessageId,
        providerStatus: result.code ?? null
      }
    };
  } catch (error) {
    try {
      await alertStore.markFailed(alertId, error);
    } catch (persistError) {
      logger.warn("whatsapp.alert.persist.failure", {
        kind: payload.kind,
        alertId,
        providerCode: persistError.message ?? null
      });
    }

    logger.warn("whatsapp.dispatch.failure", {
      kind: payload.kind,
      providerStatus: error.providerStatus ?? null,
      providerCode: error.providerCode ?? error.message ?? null,
      providerBodySnippet: error.providerBodySnippet ?? null,
      alertId
    });
    return {
      statusCode: 503,
      body: {
        error: "newagent_unavailable",
        alertId,
        providerCode: error.providerCode ?? error.message ?? null
      }
    };
  }
}

function parseSingleContactRequest(body) {
  const contacts = parseContacts([body.contact]);
  if (!contacts.ok) {
    return contacts;
  }
  return { ok: true, contact: contacts.value[0] };
}

function parseContacts(contacts) {
  if (!Array.isArray(contacts) || contacts.length < 1 || contacts.length > maxContactsPerAlert) {
    return { ok: false, error: "invalid_contacts" };
  }

  const parsed = [];
  for (const contact of contacts) {
    const name = cleanRequiredString(contact?.name);
    const phoneNumber = cleanRequiredString(contact?.phoneNumber);
    if (!name || !phoneNumber || !e164PhonePattern.test(phoneNumber)) {
      return { ok: false, error: "invalid_contact" };
    }
    parsed.push({ name, phoneNumber });
  }

  return { ok: true, value: parsed };
}

function parseLocation(location) {
  const latitude = Number(location?.latitude);
  const longitude = Number(location?.longitude);
  const accuracyMeters = location?.accuracyMeters === undefined ? undefined : Number(location.accuracyMeters);

  if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90) {
    return { ok: false, error: "invalid_location" };
  }
  if (!Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
    return { ok: false, error: "invalid_location" };
  }
  if (accuracyMeters !== undefined && (!Number.isFinite(accuracyMeters) || accuracyMeters < 0)) {
    return { ok: false, error: "invalid_location" };
  }

  return {
    ok: true,
    value: {
      latitude,
      longitude,
      accuracyMeters
    }
  };
}

function parseMedicalProfile(profile) {
  if (!profile || typeof profile !== "object") {
    return { ok: true, value: undefined };
  }

  return {
    ok: true,
    value: {
      bloodType: cleanOptionalString(profile.bloodType),
      allergies: cleanOptionalString(profile.allergies),
      conditions: cleanOptionalString(profile.conditions),
      medications: cleanOptionalString(profile.medications),
      cnib: cleanOptionalString(profile.cnib)
    }
  };
}

function cleanRequiredString(value) {
  const cleaned = cleanOptionalString(value);
  return cleaned && cleaned.length <= 120 ? cleaned : null;
}

function cleanOptionalString(value) {
  if (typeof value !== "string") {
    return undefined;
  }
  const cleaned = value.trim();
  return cleaned.length > 0 ? cleaned.slice(0, 500) : undefined;
}
