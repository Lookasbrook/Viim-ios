import { Router } from "express";
import { sendWhatsAppMessage } from "../services/newagent.js";

const burkinaPhonePattern = /^\+226\d{8}$/;

export function createAlertsRouter({ sendMessage = sendWhatsAppMessage } = {}) {
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

    return dispatchWhatsApp(response, sendMessage, {
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

    return dispatchWhatsApp(response, sendMessage, {
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

    return dispatchWhatsApp(response, sendMessage, {
      kind: "collision",
      to: contacts.value[0].phoneNumber,
      message,
      metadata: {
        contactName: contacts.value[0].name,
        contactsCount: contacts.value.length,
        location: location.value,
        incidentId: cleanOptionalString(request.body.incidentId),
        occurredAt: cleanOptionalString(request.body.occurredAt),
        medicalProfile: medicalProfile.value
      }
    });
  });

  return router;
}

async function dispatchWhatsApp(response, sendMessage, payload) {
  try {
    const result = await sendMessage(payload);
    return response.status(200).json({
      status: "sent",
      providerStatus: result.status,
      providerCode: result.code ?? null
    });
  } catch (error) {
    return response.status(503).json({
      error: "newagent_unavailable"
    });
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
  if (!Array.isArray(contacts) || contacts.length < 1 || contacts.length > 3) {
    return { ok: false, error: "invalid_contacts" };
  }

  const parsed = [];
  for (const contact of contacts) {
    const name = cleanRequiredString(contact?.name);
    const phoneNumber = cleanRequiredString(contact?.phoneNumber);
    if (!name || !phoneNumber || !burkinaPhonePattern.test(phoneNumber)) {
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
