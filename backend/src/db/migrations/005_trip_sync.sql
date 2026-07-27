ALTER TABLE circle_users
  ADD COLUMN IF NOT EXISTS trip_sync_enabled boolean NOT NULL DEFAULT false;

ALTER TABLE circle_users
  ADD COLUMN IF NOT EXISTS trip_sync_consent_at timestamptz;

ALTER TABLE trips
  ADD COLUMN IF NOT EXISTS circle_user_id uuid REFERENCES circle_users(id) ON DELETE CASCADE;

ALTER TABLE trips
  ALTER COLUMN user_id DROP NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'trips_exactly_one_owner'
      AND conrelid = 'trips'::regclass
  ) THEN
    ALTER TABLE trips
      ADD CONSTRAINT trips_exactly_one_owner
      CHECK (num_nonnulls(user_id, circle_user_id) = 1);
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS trips_circle_user_received_at_idx
  ON trips (circle_user_id, received_at DESC)
  WHERE circle_user_id IS NOT NULL;
