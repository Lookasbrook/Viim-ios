CREATE TABLE IF NOT EXISTS circle_users (
  id uuid PRIMARY KEY,
  installation_id uuid NOT NULL UNIQUE,
  display_name text NOT NULL,
  auth_token_hash text NOT NULL UNIQUE,
  push_token text,
  push_environment text NOT NULL DEFAULT 'production'
    CHECK (push_environment IN ('sandbox', 'production')),
  stats_sharing boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS circle_invitations (
  id uuid PRIMARY KEY,
  inviter_user_id uuid NOT NULL REFERENCES circle_users(id) ON DELETE CASCADE,
  token_hash text NOT NULL UNIQUE,
  expires_at timestamptz NOT NULL,
  accepted_by_user_id uuid REFERENCES circle_users(id) ON DELETE SET NULL,
  accepted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS circle_relationships (
  id uuid PRIMARY KEY,
  first_user_id uuid NOT NULL REFERENCES circle_users(id) ON DELETE CASCADE,
  second_user_id uuid NOT NULL REFERENCES circle_users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (first_user_id <> second_user_id),
  UNIQUE (first_user_id, second_user_id)
);

CREATE TABLE IF NOT EXISTS circle_stats (
  user_id uuid PRIMARY KEY REFERENCES circle_users(id) ON DELETE CASCADE,
  score integer CHECK (score IS NULL OR (score >= 0 AND score <= 100)),
  trips_count integer NOT NULL DEFAULT 0 CHECK (trips_count >= 0),
  distance_km numeric NOT NULL DEFAULT 0 CHECK (distance_km >= 0),
  safe_streak integer NOT NULL DEFAULT 0 CHECK (safe_streak >= 0),
  period_start timestamptz NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS circle_incidents (
  id uuid PRIMARY KEY,
  source_user_id uuid NOT NULL REFERENCES circle_users(id) ON DELETE CASCADE,
  occurred_at timestamptz NOT NULL,
  latitude numeric NOT NULL CHECK (latitude >= -90 AND latitude <= 90),
  longitude numeric NOT NULL CHECK (longitude >= -180 AND longitude <= 180),
  accuracy_meters numeric,
  severity text NOT NULL DEFAULT 'suspected'
    CHECK (severity IN ('suspected', 'confirmed', 'test')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS circle_notifications (
  id uuid PRIMARY KEY,
  recipient_user_id uuid NOT NULL REFERENCES circle_users(id) ON DELETE CASCADE,
  incident_id uuid NOT NULL REFERENCES circle_incidents(id) ON DELETE CASCADE,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (recipient_user_id, incident_id)
);

CREATE INDEX IF NOT EXISTS circle_invitations_token_hash_idx
  ON circle_invitations (token_hash);

CREATE INDEX IF NOT EXISTS circle_notifications_recipient_created_idx
  ON circle_notifications (recipient_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS circle_incidents_source_created_idx
  ON circle_incidents (source_user_id, created_at DESC);
