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
