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

export async function sendWhatsAppMessage({ to, message, kind, metadata = {} }) {
  if (!config.newagentSendUrl || !config.newagentToken) {
    throw new Error("newagent_not_configured");
  }

  const providerPayload = buildProviderPayload(config.newagentSendUrl, {
    to,
    message,
    kind,
    metadata
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

export function buildProviderPayload(sendUrl, { to, message, kind, metadata = {} }) {
  if (isMetaWhatsAppSendUrl(sendUrl)) {
    return {
      messaging_product: "whatsapp",
      recipient_type: "individual",
      to: to.replace(/^\+/, ""),
      type: "text",
      text: {
        preview_url: false,
        body: message
      }
    };
  }

  return {
    source: "viim",
    channel: "whatsapp",
    kind,
    to,
    message,
    metadata
  };
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
