import { config } from "../config.js";

export async function checkNewagent() {
  if (!config.newagentUrl || !config.newagentToken) {
    return { status: "not_configured" };
  }

  const response = await fetch(config.newagentUrl, {
    method: "GET",
    headers: {
      Authorization: `Bearer ${config.newagentToken}`
    },
    signal: AbortSignal.timeout(1500)
  });

  return { status: response.ok ? "ok" : "error", code: response.status };
}

export async function sendWhatsAppMessage({ to, message, kind, metadata = {} }) {
  if (!config.newagentUrl || !config.newagentToken) {
    throw new Error("newagent_not_configured");
  }

  const response = await fetch(config.newagentUrl, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${config.newagentToken}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      source: "viim",
      channel: "whatsapp",
      kind,
      to,
      message,
      metadata
    }),
    signal: AbortSignal.timeout(5000)
  });

  if (!response.ok) {
    throw new Error("newagent_send_failed");
  }

  return { status: "ok", code: response.status };
}
