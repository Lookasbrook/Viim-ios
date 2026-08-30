import { config } from "../config.js";

export async function checkNewagent() {
  if (!config.newagentHealthUrl || !config.newagentToken) {
    return { status: "not_configured" };
  }

  const response = await fetch(config.newagentHealthUrl, {
    method: "GET",
    headers: {
      Authorization: `Bearer ${config.newagentToken}`
    },
    signal: AbortSignal.timeout(1500)
  });

  return { status: response.ok ? "ok" : "error", code: response.status };
}

export async function sendWhatsAppMessage({ to, message, kind, metadata = {}, params = {} }) {
  if (!config.newagentSendUrl || !config.newagentToken) {
    throw new Error("newagent_not_configured");
  }

  const providerPayload = buildProviderPayload(config.newagentSendUrl, {
    to,
    message,
    kind,
    metadata,
    params
  });
  const response = await fetch(config.newagentSendUrl, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${config.newagentToken}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify(providerPayload),
    signal: AbortSignal.timeout(5000)
  });

  return parseProviderSendResponse(response);
}

// Langue des modèles Meta approuvés (WhatsApp attend un code générique, pas `fr_FR`).
const META_TEMPLATE_LANGUAGE = "fr";

// Modèles Meta approuvés requis pour les messages initiés par l'entreprise. Un contact d'urgence
// n'a jamais ouvert de conversation : hors de la fenêtre de service de 24 h, WhatsApp n'accepte
// qu'un modèle approuvé, jamais un `type: "text"`. Voir architecture/meta-mcp-et-whatsapp.md §4.1.
// Les noms doivent correspondre aux modèles créés dans WhatsApp Manager
// (cf. backend/scripts/create-whatsapp-templates.mjs).
const META_TEMPLATES = {
  alert_test: { name: "viim_alert_test", body: "none", locationButton: false },
  collision: { name: "viim_collision_alert", body: "driver_location", locationButton: true },
  location_share: { name: "viim_location_share", body: "driver_location", locationButton: true }
};

export function buildProviderPayload(sendUrl, { to, message, kind, metadata = {}, params = {} }) {
  if (isMetaWhatsAppSendUrl(sendUrl)) {
    const recipient = to.replace(/^\+/, "");
    const templatePayload = buildMetaTemplatePayload(recipient, kind, params);
    if (templatePayload) {
      return templatePayload;
    }

    // Repli : uniquement valide dans une fenêtre de service ouverte par l'utilisateur.
    return {
      messaging_product: "whatsapp",
      recipient_type: "individual",
      to: recipient,
      type: "text",
      text: {
        preview_url: false,
        body: message
      }
    };
  }

  // Passerelle NEwAGENT-IA : contrat inchangé. `params` est ignoré côté passerelle tant qu'elle
  // n'est pas mise à jour pour construire les modèles elle-même.
  return {
    source: "viim",
    channel: "whatsapp",
    kind,
    to,
    message,
    metadata
  };
}

function buildMetaTemplatePayload(recipient, kind, params = {}) {
  const template = META_TEMPLATES[kind];
  if (!template) {
    return null;
  }

  const components = [];

  if (template.body === "driver_location") {
    const coordinates = coordinatesText(params.location);
    if (!coordinates) {
      // Paramètres incomplets : laisser le repli texte gérer plutôt que d'émettre un modèle
      // dont le nombre de variables ne correspondrait pas.
      return null;
    }
    const driverName = textParameter(params.driverName) ?? "Un utilisateur Viim";
    components.push({
      type: "body",
      parameters: [
        { type: "text", text: driverName },
        { type: "text", text: coordinates }
      ]
    });
  }

  if (template.locationButton) {
    const query = coordinatesQuery(params.location);
    if (!query) {
      return null;
    }
    components.push({
      type: "button",
      sub_type: "url",
      index: "0",
      parameters: [{ type: "text", text: query }]
    });
  }

  const payload = {
    messaging_product: "whatsapp",
    recipient_type: "individual",
    to: recipient,
    type: "template",
    template: {
      name: template.name,
      language: { code: META_TEMPLATE_LANGUAGE }
    }
  };
  if (components.length > 0) {
    payload.template.components = components;
  }
  return payload;
}

function readCoordinates(location) {
  if (!location || typeof location !== "object") {
    return null;
  }
  const latitude = Number(location.latitude);
  const longitude = Number(location.longitude);
  if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90) {
    return null;
  }
  if (!Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
    return null;
  }
  return { latitude, longitude };
}

// Texte lisible pour le corps du modèle, ex. « 12.371800, -1.519600 ».
function coordinatesText(location) {
  const coordinates = readCoordinates(location);
  return coordinates
    ? `${coordinates.latitude.toFixed(6)}, ${coordinates.longitude.toFixed(6)}`
    : null;
}

// Suffixe d'URL pour le bouton `https://maps.google.com/?q={{1}}`, sans espace.
function coordinatesQuery(location) {
  const coordinates = readCoordinates(location);
  return coordinates
    ? `${coordinates.latitude.toFixed(6)},${coordinates.longitude.toFixed(6)}`
    : null;
}

function textParameter(value) {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed.slice(0, 120) : null;
}

export async function parseProviderSendResponse(response) {
  const responseBody = await readProviderBody(response);

  if (!response.ok) {
    const error = new Error("newagent_send_failed");
    error.providerStatus = response.status;
    error.providerCode = "http_error";
    error.providerBodySnippet = bodySnippet(responseBody.raw);
    throw error;
  }

  const providerMessageId = extractProviderMessageId(responseBody.json);
  if (!providerMessageId) {
    const error = new Error("provider_no_message_id");
    error.providerStatus = response.status;
    error.providerCode = "provider_no_message_id";
    error.providerBodySnippet = bodySnippet(responseBody.raw);
    throw error;
  }

  return {
    status: "ok",
    code: response.status,
    providerMessageId
  };
}

async function readProviderBody(response) {
  const raw = await response.text();
  if (!raw) {
    return { raw: "", json: null };
  }

  try {
    return { raw, json: JSON.parse(raw) };
  } catch {
    return { raw, json: null };
  }
}

function extractProviderMessageId(body) {
  if (!body || typeof body !== "object") {
    return null;
  }

  const candidates = [
    body.providerMessageId,
    body.messageId,
    body.id,
    body.data?.providerMessageId,
    body.data?.messageId,
    body.data?.id,
    body.messages?.[0]?.id
  ];
  const messageId = candidates.find((value) => typeof value === "string" && value.trim().length > 0);
  return messageId?.trim() ?? null;
}

function isMetaWhatsAppSendUrl(value) {
  try {
    const url = new URL(value);
    return url.protocol === "https:" &&
      url.hostname === "graph.facebook.com" &&
      url.pathname.endsWith("/messages");
  } catch {
    return false;
  }
}

function bodySnippet(rawBody) {
  return String(rawBody ?? "")
    .replace(/\+\d{7,15}/g, "[phone]")
    .replace(/Bearer\s+[A-Za-z0-9._~+/=-]+/gi, "Bearer [redacted]")
    .slice(0, 500);
}
