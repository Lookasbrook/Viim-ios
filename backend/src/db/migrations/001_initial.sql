CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY,
  device_id text NOT NULL,
  first_name text NOT NULL,
  phone_e164 text NOT NULL,
  vehicle_type text NOT NULL CHECK (vehicle_type IN ('moto', 'voiture', 'velo')),
  vehicle_brand text NOT NULL,
  vehicle_model text NOT NULL,
  vehicle_year integer,
  leaderboard_opt_in boolean NOT NULL DEFAULT false,
  daily_summary_opt_out boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS trips (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id text NOT NULL,
  start_date timestamptz NOT NULL,
  end_date timestamptz,
  distance_km numeric NOT NULL DEFAULT 0,
  duration_sec integer NOT NULL DEFAULT 0,
  avg_speed_kmh numeric NOT NULL DEFAULT 0,
  max_speed_kmh numeric NOT NULL DEFAULT 0,
  score integer,
  is_calibration boolean NOT NULL DEFAULT true,
  vehicle_type text NOT NULL,
  role text NOT NULL DEFAULT 'conducteur',
  received_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS trip_events (
  id uuid PRIMARY KEY,
  trip_id uuid NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  type text NOT NULL,
  timestamp timestamptz NOT NULL,
  latitude numeric NOT NULL,
  longitude numeric NOT NULL,
  intensity numeric NOT NULL,
  gps_confirmed boolean NOT NULL DEFAULT false
);

CREATE TABLE IF NOT EXISTS daily_summaries (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date date NOT NULL,
  trips_count integer NOT NULL DEFAULT 0,
  total_km numeric NOT NULL DEFAULT 0,
  total_duration_sec integer NOT NULL DEFAULT 0,
  avg_score integer,
  fuel_fcfa integer,
  received_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, date)
);

CREATE TABLE IF NOT EXISTS alerts (
  id uuid PRIMARY KEY,
  kind text NOT NULL CHECK (kind IN ('alert_test', 'location_share', 'collision')),
  to_e164 text NOT NULL,
  message text NOT NULL,
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'sent', 'delivered', 'failed')),
  provider_message_id text,
  provider_status integer,
  provider_code text,
  provider_error text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS alerts_status_created_at_idx
  ON alerts (status, created_at DESC);

CREATE INDEX IF NOT EXISTS alerts_provider_message_id_idx
  ON alerts (provider_message_id)
  WHERE provider_message_id IS NOT NULL;
