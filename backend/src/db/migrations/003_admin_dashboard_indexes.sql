CREATE INDEX IF NOT EXISTS users_created_at_idx
  ON users (created_at DESC);

CREATE INDEX IF NOT EXISTS trips_received_at_idx
  ON trips (received_at DESC);

CREATE INDEX IF NOT EXISTS trips_user_received_at_idx
  ON trips (user_id, received_at DESC);

CREATE INDEX IF NOT EXISTS circle_users_updated_at_idx
  ON circle_users (updated_at DESC);

CREATE INDEX IF NOT EXISTS circle_incidents_occurred_at_idx
  ON circle_incidents (occurred_at DESC);
