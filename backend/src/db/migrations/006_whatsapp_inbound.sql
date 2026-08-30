-- Webhook WhatsApp entrant : opt-out STOP, statuts de livraison, idempotence.

-- 1. Autoriser le statut 'read' sur les alertes (accusé de lecture WhatsApp).
DO $$
DECLARE
  status_constraint record;
BEGIN
  FOR status_constraint IN
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'alerts'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%status%'
  LOOP
    EXECUTE format('ALTER TABLE alerts DROP CONSTRAINT %I', status_constraint.conname);
  END LOOP;

  ALTER TABLE alerts
    ADD CONSTRAINT alerts_status_check
    CHECK (status IN ('queued', 'sent', 'delivered', 'read', 'failed'));
END
$$;

-- 2. Horodatages de livraison / lecture (utiles à la cascade contact 1 -> 2 -> 3).
ALTER TABLE alerts ADD COLUMN IF NOT EXISTS delivered_at timestamptz;
ALTER TABLE alerts ADD COLUMN IF NOT EXISTS read_at timestamptz;

-- 3. Table d'idempotence : un événement Meta traité une seule fois.
CREATE TABLE IF NOT EXISTS whatsapp_webhook_events (
  event_id text PRIMARY KEY,
  received_at timestamptz NOT NULL DEFAULT now()
);

-- 4. Recherche de l'utilisateur par numéro pour appliquer le STOP.
CREATE INDEX IF NOT EXISTS users_phone_e164_idx ON users (phone_e164);
