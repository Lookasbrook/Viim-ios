import { pool } from "../db/pool.js";

// Ordre de progression des statuts de livraison WhatsApp. `failed` est accepté à tout moment.
const STATUS_RANK = ["queued", "sent", "delivered", "read"];

export function createWhatsappInboundStore(database = pool) {
  if (!database) {
    return createNoopStore();
  }

  return {
    // Enregistre un événement Meta. Retourne true s'il est nouveau, false s'il a déjà été traité.
    async claimEvent(eventId) {
      const result = await database.query(
        `
        INSERT INTO whatsapp_webhook_events (event_id)
        VALUES ($1)
        ON CONFLICT (event_id) DO NOTHING
        `,
        [eventId]
      );
      return result.rowCount === 1;
    },

    // Applique le STOP : coupe le résumé quotidien pour l'utilisateur portant ce numéro.
    async optOutDailySummary(phoneFromMeta) {
      const withPlus = phoneFromMeta.startsWith("+") ? phoneFromMeta : `+${phoneFromMeta}`;
      const withoutPlus = phoneFromMeta.replace(/^\+/, "");
      const result = await database.query(
        `
        UPDATE users
        SET daily_summary_opt_out = true
        WHERE phone_e164 IN ($1, $2)
          AND daily_summary_opt_out = false
        `,
        [withPlus, withoutPlus]
      );
      return result.rowCount;
    },

    // Fait avancer le statut d'une alerte d'après un accusé Meta, sans jamais reculer.
    async recordDeliveryStatus(providerMessageId, status) {
      const result = await database.query(
        `
        UPDATE alerts
        SET status = $2,
            delivered_at = COALESCE(delivered_at, CASE WHEN $2 IN ('delivered', 'read') THEN now() END),
            read_at = COALESCE(read_at, CASE WHEN $2 = 'read' THEN now() END),
            updated_at = now()
        WHERE provider_message_id = $1
          AND (
            $2 = 'failed'
            OR array_position($3::text[], $2) > COALESCE(array_position($3::text[], status), 0)
          )
        `,
        [providerMessageId, status, STATUS_RANK]
      );
      return result.rowCount;
    }
  };
}

function createNoopStore() {
  return {
    async claimEvent() {
      return true;
    },
    async optOutDailySummary() {
      return 0;
    },
    async recordDeliveryStatus() {
      return 0;
    }
  };
}
