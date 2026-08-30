import { randomUUID } from "node:crypto";
import { buildCollisionMessage } from "./collisionMessage.js";

// Un tick de cascade : pour chaque incident dont le dernier envoi date de plus de
// `escalateAfterMinutes` sans accusé de lecture, joindre le contact suivant.
export async function runCollisionEscalationTick({
  store,
  sendMessage,
  alertStore,
  logger = console,
  leaseSeconds = 30,
  escalateAfterMinutes = 5
}) {
  const incidents = await store.claimDueIncidents({ leaseSeconds, escalateAfterMinutes });
  for (const incident of incidents) {
    try {
      await escalateIncident(incident, { store, sendMessage, alertStore, logger });
    } catch (error) {
      logger.warn("whatsapp.escalation.tick.failure", {
        incidentId: incident.incidentId,
        message: error?.message ?? null
      });
      await store.releaseLease(incident.incidentId).catch(() => {});
    }
  }
  return incidents.length;
}

async function escalateIncident(incident, { store, sendMessage, alertStore, logger }) {
  if (await store.anyContactRead(incident.incidentId)) {
    await store.markResolved(incident.incidentId, "read");
    logger.info("whatsapp.escalation.stopped", { incidentId: incident.incidentId, reason: "read" });
    return;
  }

  const contacts = Array.isArray(incident.contacts) ? incident.contacts : [];
  const index = incident.nextIndex;
  if (index >= contacts.length) {
    await store.markResolved(incident.incidentId, "exhausted");
    logger.info("whatsapp.escalation.stopped", { incidentId: incident.incidentId, reason: "exhausted" });
    return;
  }

  const contact = contacts[index];
  const message = buildCollisionMessage({
    driverName: incident.driverName,
    location: incident.location
  });
  const alertId = randomUUID();

  try {
    await alertStore.create({
      id: alertId,
      kind: "collision",
      to: contact.phoneNumber,
      message,
      incidentId: incident.incidentId,
      contactIndex: index,
      metadata: {
        contactName: contact.name,
        contactsCount: contacts.length,
        location: incident.location,
        escalated: true
      }
    });
  } catch (error) {
    logger.warn("whatsapp.escalation.persist.failure", {
      incidentId: incident.incidentId,
      message: error?.message ?? null
    });
  }

  try {
    const result = await sendMessage({
      kind: "collision",
      to: contact.phoneNumber,
      message,
      params: { driverName: incident.driverName, location: incident.location }
    });
    await alertStore.markSent(alertId, result).catch(() => {});
    logger.info("whatsapp.escalation.sent", {
      incidentId: incident.incidentId,
      contactIndex: index,
      providerMessageId: result?.providerMessageId ?? null
    });
  } catch (error) {
    await alertStore.markFailed(alertId, error).catch(() => {});
    logger.warn("whatsapp.escalation.send.failure", {
      incidentId: incident.incidentId,
      contactIndex: index,
      providerCode: error?.providerCode ?? error?.message ?? null
    });
  }

  // Avancer quoi qu'il arrive : un contact injoignable ne doit pas bloquer le suivant.
  await store.advance(incident.incidentId, index);
}
