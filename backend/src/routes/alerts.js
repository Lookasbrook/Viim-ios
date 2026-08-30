import { Router } from "express";
import { randomUUID } from "node:crypto";
import { config } from "../config.js";
import { createAlertStore } from "../services/alertStore.js";
import { buildCollisionMessage } from "../services/collisionMessage.js";
import { createCollisionEscalationStore } from "../services/collisionEscalationStore.js";
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
  alertStore = createAlertStore(),
  escalationStore = createCollisionEscalationStore(),
  requireContactsConsent = config.requireContactsConsent
} = {}) {
  const router = Router();

  // Politique WhatsApp : le destinataire doit avoir consenti. L'app iOS atteste ce consentement
  // (le conducteur confirme, sur l'écran contacts, que ses proches acceptent d'être prévenus).
  // Tant que `requireContactsConsent` est faux, l'absence d'attestation est seulement journalisée.
  function consentGate(body, kind, response) {
    const consent = parseContactsConsent(body);
    if (consent !== true) {
      if (requireContactsConsent) {
        response.status(422).json({ error: "contacts_consent_required" });
        return { blocked: true };
      }
      logger.warn("whatsapp.contacts_consent.missing", { kind, consent });
    }
    return { blocked: false, consent };
  }

  router.post("/test", async (request, response) => {
    const parsed = parseSingleContactRequest(request.body);
    if (!parsed.ok) {
      return response.status(422).json({ error: parsed.error });
    }

    const gate = consentGate(request.body, "alert_test", response);
    if (gate.blocked) {
      return undefined;
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
      contactsConsent: gate.consent,
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

    const gate = consentGate(request.body, "location_share", response);
    if (gate.blocked) {
      return undefined;
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
      contactsConsent: gate.consent,
      params: {
        driverName,
        location: location.value
      },
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

    const gate = consentGate(request.body, "collision", response);
    if (gate.blocked) {
      return undefined;
    }

    const driverName = cleanOptionalString(request.body.driverName) ?? "Un utilisateur Viim";
    const message = buildCollisionMessage({ driverName, location: location.value });
    const medicalProfile = parseMedicalProfile(request.body.medicalProfile);
    const incidentRef = randomUUID();

    // Envoi immédiat : essayer les contacts dans l'ordre, s'arrêter au premier accepté par
    // le fournisseur. Les contacts restants sont relancés par la cascade si personne ne lit.
    const deliveries = [];
    let reachedIndex = -1;
    for (let index = 0; index < contacts.value.length; index += 1) {
      const contact = contacts.value[index];
      const delivery = await dispatchWhatsAppResult(sendMessage, logger, alertStore, {
        kind: "collision",
        to: contact.phoneNumber,
        message,
        contactsConsent: gate.consent,
        params: {
          driverName,
          location: location.value
        },
        incidentId: incidentRef,
        contactIndex: index,
        metadata: {
          contactName: contact.name,
          contactsCount: contacts.value.length,
          location: location.value,
          incidentId: cleanOptionalString(request.body.incidentId),
          occurredAt: cleanOptionalString(request.body.occurredAt),
          medicalProfile: medicalProfile.value
        }
      });
      deliveries.push(delivery);
      if (delivery.statusCode === 200) {
        reachedIndex = index;
        break;
      }
    }

    if (reachedIndex === -1) {
      const last = deliveries[deliveries.length - 1];
      return response.status(last.statusCode).json(last.body);
    }

    const pendingContacts = contacts.value.length - (reachedIndex + 1);
    if (pendingContacts > 0) {
      try {
        await escalationStore.createIncident({
          incidentId: incidentRef,
          driverName,
          location: location.value,
          contacts: contacts.value,
          nextIndex: reachedIndex + 1
        });
      } catch (error) {
        logger.warn("whatsapp.escalation.persist.failure", {
          incidentId: incidentRef,
          providerCode: error?.message ?? null
        });
      }
    }

    return response.status(200).json({
      status: "sent",
      incidentId: incidentRef,
      sentCount: 1,
      failedCount: deliveries.length - 1,
      escalation: pendingContacts > 0
        ? { pendingContacts, escalateAfterMinutes: 5 }
        : null,
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

// Attestation d'opt-in des contacts, envoyée par l'app. Accepte `true`/`false` ou
// `{ acknowledged: bool }`. Toute autre valeur -> null (non renseigné).
function parseContactsConsent(body) {
  const raw = body?.contactsConsent;
  if (raw === true || raw === false) {
    return raw;
  }
  if (raw && typeof raw === "object" && typeof raw.acknowledged === "boolean") {
    return raw.acknowledged;
  }
  return null;
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
