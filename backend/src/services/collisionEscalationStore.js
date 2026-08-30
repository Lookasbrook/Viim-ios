import { pool } from "../db/pool.js";

// Persiste et fait avancer la cascade d'alerte collision : contact suivant si personne n'a lu.
export function createCollisionEscalationStore(database = pool) {
  if (!database) {
    return createNoopStore();
  }

  return {
    // Enregistre un incident avec la liste ordonnée des contacts et l'index du prochain à joindre.
    async createIncident({ incidentId, driverName, location, contacts, nextIndex }) {
      await database.query(
        `
        INSERT INTO collision_escalations (
          incident_id, driver_name, location, contacts, next_index, status, last_attempt_at
        )
        VALUES ($1, $2, $3::jsonb, $4::jsonb, $5, 'active', now())
        ON CONFLICT (incident_id) DO NOTHING
        `,
        [incidentId, driverName, JSON.stringify(location), JSON.stringify(contacts), nextIndex]
      );
    },

    // Verrouille et retourne les incidents dont le dernier envoi date de plus de N minutes.
    async claimDueIncidents({ leaseSeconds = 30, escalateAfterMinutes = 5, limit = 20 } = {}) {
      const result = await database.query(
        `
        UPDATE collision_escalations
        SET lease_until = now() + make_interval(secs => $1),
            updated_at = now()
        WHERE incident_id IN (
          SELECT incident_id
          FROM collision_escalations
          WHERE status = 'active'
            AND last_attempt_at IS NOT NULL
            AND last_attempt_at <= now() - make_interval(mins => $2)
            AND (lease_until IS NULL OR lease_until < now())
          ORDER BY last_attempt_at
          LIMIT $3
          FOR UPDATE SKIP LOCKED
        )
        RETURNING incident_id, driver_name, location, contacts, next_index
        `,
        [leaseSeconds, escalateAfterMinutes, limit]
      );
      return result.rows.map((row) => ({
        incidentId: row.incident_id,
        driverName: row.driver_name,
        location: row.location,
        contacts: row.contacts,
        nextIndex: row.next_index
      }));
    },

    // Un accusé de lecture sur n'importe quel contact de l'incident arrête la cascade.
    async anyContactRead(incidentId) {
      const result = await database.query(
        "SELECT 1 FROM alerts WHERE incident_id = $1 AND status = 'read' LIMIT 1",
        [incidentId]
      );
      return result.rowCount > 0;
    },

    // Passe au contact suivant ; marque 'exhausted' quand la liste est épuisée.
    async advance(incidentId, attemptedIndex) {
      await database.query(
        `
        UPDATE collision_escalations
        SET next_index = $2 + 1,
            last_attempt_at = now(),
            lease_until = NULL,
            status = CASE
              WHEN $2 + 1 >= jsonb_array_length(contacts) THEN 'exhausted'
              ELSE 'active'
            END,
            updated_at = now()
        WHERE incident_id = $1
        `,
        [incidentId, attemptedIndex]
      );
    },

    async markResolved(incidentId, status) {
      await database.query(
        `
        UPDATE collision_escalations
        SET status = $2, lease_until = NULL, updated_at = now()
        WHERE incident_id = $1
        `,
        [incidentId, status]
      );
    },

    async releaseLease(incidentId) {
      await database.query(
        "UPDATE collision_escalations SET lease_until = NULL, updated_at = now() WHERE incident_id = $1",
        [incidentId]
      );
    }
  };
}

function createNoopStore() {
  return {
    async createIncident() {},
    async claimDueIncidents() {
      return [];
    },
    async anyContactRead() {
      return false;
    },
    async advance() {},
    async markResolved() {},
    async releaseLease() {}
  };
}
