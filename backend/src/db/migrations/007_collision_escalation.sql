-- Cascade des alertes collision : relance le contact suivant si personne n'a lu sous 5 minutes.

CREATE TABLE IF NOT EXISTS collision_escalations (
  incident_id uuid PRIMARY KEY,
  driver_name text NOT NULL,
  location jsonb NOT NULL,
  contacts jsonb NOT NULL,
  next_index integer NOT NULL,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'read', 'exhausted')),
  last_attempt_at timestamptz,
  lease_until timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Rattache chaque envoi (table alerts) à son incident et à son rang dans la liste de contacts.
ALTER TABLE alerts ADD COLUMN IF NOT EXISTS incident_id uuid;
ALTER TABLE alerts ADD COLUMN IF NOT EXISTS contact_index integer;

CREATE INDEX IF NOT EXISTS alerts_incident_id_idx
  ON alerts (incident_id)
  WHERE incident_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS collision_escalations_due_idx
  ON collision_escalations (last_attempt_at)
  WHERE status = 'active';
