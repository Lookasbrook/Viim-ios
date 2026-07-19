import { pool } from "../db/pool.js";

export function createAlertStore(database = pool) {
  if (!database) {
    return createNoopAlertStore();
  }

  return {
    async create(alert) {
      await database.query(
        `
        INSERT INTO alerts (
          id, kind, to_e164, message, status, metadata
        )
        VALUES ($1, $2, $3, $4, 'queued', $5::jsonb)
        ON CONFLICT (id) DO NOTHING
        `,
        [
          alert.id,
          alert.kind,
          alert.to,
          alert.message,
          JSON.stringify(alert.metadata ?? {})
        ]
      );
    },

    async markSent(id, result) {
      await database.query(
        `
        UPDATE alerts
        SET status = 'sent',
            provider_message_id = $2,
            provider_status = $3,
            provider_code = $4,
            provider_error = NULL,
            updated_at = now()
        WHERE id = $1
        `,
        [
          id,
          result.providerMessageId,
          result.code ?? null,
          result.status ?? null
        ]
      );
    },

    async markFailed(id, error) {
      await database.query(
        `
        UPDATE alerts
        SET status = 'failed',
            provider_status = $2,
            provider_code = $3,
            provider_error = $4,
            updated_at = now()
        WHERE id = $1
        `,
        [
          id,
          error.providerStatus ?? null,
          error.providerCode ?? error.message ?? null,
          error.providerBodySnippet ?? null
        ]
      );
    },

    async findById(id) {
      const result = await database.query(
        `
        SELECT
          id, kind, to_e164, status, provider_message_id,
          provider_status, provider_code, created_at, updated_at
        FROM alerts
        WHERE id = $1
        `,
        [id]
      );
      const row = result.rows[0];
      if (!row) {
        return null;
      }
      return {
        id: row.id,
        kind: row.kind,
        to: row.to_e164,
        status: row.status,
        providerMessageId: row.provider_message_id,
        providerStatus: row.provider_status,
        providerCode: row.provider_code,
        createdAt: row.created_at,
        updatedAt: row.updated_at
      };
    }
  };
}

function createNoopAlertStore() {
  return {
    async create() {},
    async markSent() {},
    async markFailed() {},
    async findById() {
      return null;
    }
  };
}
