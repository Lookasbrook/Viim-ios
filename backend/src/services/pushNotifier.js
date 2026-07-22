import { createSign } from "node:crypto";
import http2 from "node:http2";
import { config } from "../config.js";

export function createPushNotifier(settings = config) {
  const isConfigured = Boolean(
    settings.apnsTeamId &&
    settings.apnsKeyId &&
    settings.apnsBundleId &&
    settings.apnsPrivateKey
  );

  return {
    isConfigured,
    async sendIncident({ recipient, incident, sourceDisplayName }) {
      if (!isConfigured || !recipient.pushToken) {
        return { status: "skipped" };
      }

      const host = recipient.pushEnvironment === "sandbox"
        ? "api.sandbox.push.apple.com"
        : "api.push.apple.com";
      const isTest = incident.severity === "test";
      const payload = {
        aps: {
          alert: {
            title: isTest ? "Test d’alerte Viim" : "Alerte collision Viim",
            body: isTest
              ? `${sourceDisplayName} teste son cercle de confiance. Ouvrez Viim pour confirmer la réception.`
              : `${sourceDisplayName} pourrait avoir eu un accident. Ouvrez Viim pour voir sa position.`
          },
          sound: "default",
          "interruption-level": isTest ? "active" : "time-sensitive"
        },
        type: "circle_incident",
        incidentId: incident.id
      };

      return sendAPNsRequest({
        host,
        deviceToken: recipient.pushToken,
        topic: settings.apnsBundleId,
        authorization: createProviderToken(settings),
        payload
      });
    }
  };
}

function createProviderToken(settings, now = new Date()) {
  const header = base64url(JSON.stringify({ alg: "ES256", kid: settings.apnsKeyId }));
  const claims = base64url(JSON.stringify({
    iss: settings.apnsTeamId,
    iat: Math.floor(now.getTime() / 1000)
  }));
  const signingInput = `${header}.${claims}`;
  const signer = createSign("SHA256");
  signer.update(signingInput);
  signer.end();
  const signature = signer.sign({
    key: settings.apnsPrivateKey.replaceAll("\\n", "\n"),
    dsaEncoding: "ieee-p1363"
  });
  return `${signingInput}.${base64url(signature)}`;
}

function sendAPNsRequest({ host, deviceToken, topic, authorization, payload }) {
  return new Promise((resolve, reject) => {
    const client = http2.connect(`https://${host}`);
    client.once("error", reject);

    const request = client.request({
      ":method": "POST",
      ":path": `/3/device/${deviceToken}`,
      authorization: `bearer ${authorization}`,
      "apns-topic": topic,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json"
    });
    let responseBody = "";
    let statusCode = 0;
    request.setEncoding("utf8");
    request.on("response", (headers) => {
      statusCode = Number(headers[":status"] ?? 0);
    });
    request.on("data", (chunk) => {
      responseBody += chunk;
    });
    request.on("end", () => {
      client.close();
      if (statusCode === 200) {
        resolve({ status: "sent" });
      } else {
        const error = new Error("apns_rejected");
        error.statusCode = statusCode;
        error.responseBody = responseBody.slice(0, 200);
        reject(error);
      }
    });
    request.once("error", (error) => {
      client.close();
      reject(error);
    });
    request.end(JSON.stringify(payload));
  });
}

function base64url(value) {
  return Buffer.from(value).toString("base64url");
}
