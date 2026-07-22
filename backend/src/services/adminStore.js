import { pool } from "../db/pool.js";

export function createAdminStore(database = pool) {
  return database ? createPostgresAdminStore(database) : createEmptyAdminStore();
}

function createPostgresAdminStore(database) {
  return {
    async getOverview() {
      const [metricsResult, seriesResult, feedResult, interventionsResult] = await Promise.all([
        database.query(`
          SELECT
            (SELECT COUNT(*)::int FROM circle_users) AS circle_users,
            (SELECT COUNT(*)::int FROM users) AS synced_profiles,
            (SELECT COUNT(*)::int FROM trips
              WHERE received_at >= now() - interval '30 days') AS trips_30d,
            (SELECT COALESCE(SUM(distance_km), 0)::float8 FROM trips
              WHERE received_at >= now() - interval '30 days') AS distance_30d,
            (SELECT COUNT(DISTINCT user_id)::int FROM trips
              WHERE received_at >= now() - interval '30 days') AS active_drivers_30d,
            (SELECT COUNT(*)::int FROM alerts
              WHERE created_at >= now() - interval '7 days') AS alerts_7d,
            (SELECT COUNT(*)::int FROM alerts
              WHERE created_at >= now() - interval '7 days' AND status = 'failed') AS failed_alerts_7d,
            (SELECT COUNT(*)::int FROM circle_incidents
              WHERE occurred_at >= now() - interval '30 days') AS incidents_30d,
            (SELECT COUNT(*)::int FROM circle_relationships) AS relationships,
            (SELECT COUNT(*)::int FROM circle_users
              WHERE push_token IS NOT NULL) AS push_ready,
            (SELECT ROUND(AVG(score))::int FROM circle_stats
              WHERE score IS NOT NULL) AS shared_average_score,
            GREATEST(
              COALESCE((SELECT MAX(received_at) FROM trips), '-infinity'::timestamptz),
              COALESCE((SELECT MAX(created_at) FROM alerts), '-infinity'::timestamptz),
              COALESCE((SELECT MAX(updated_at) FROM circle_users), '-infinity'::timestamptz)
            ) AS latest_server_activity
        `),
        database.query(`
          WITH days AS (
            SELECT generate_series(
              date_trunc('day', now()) - interval '13 days',
              date_trunc('day', now()),
              interval '1 day'
            ) AS day
          )
          SELECT
            day::date,
            (SELECT COUNT(*)::int FROM trips
              WHERE received_at >= day AND received_at < day + interval '1 day') AS trips,
            (SELECT COUNT(*)::int FROM alerts
              WHERE created_at >= day AND created_at < day + interval '1 day') AS alerts,
            (SELECT COUNT(*)::int FROM circle_incidents
              WHERE occurred_at >= day AND occurred_at < day + interval '1 day') AS incidents,
            (SELECT COUNT(*)::int FROM circle_users
              WHERE created_at >= day AND created_at < day + interval '1 day')
              +
            (SELECT COUNT(*)::int FROM users
              WHERE created_at >= day AND created_at < day + interval '1 day') AS registrations
          FROM days
          ORDER BY day ASC
        `),
        database.query(`
          SELECT kind, id, actor, metadata, occurred_at
          FROM (
            SELECT 'trip' AS kind, t.id::text AS id, u.first_name AS actor,
              json_build_object(
                'distanceKm', t.distance_km,
                'score', t.score,
                'vehicleType', t.vehicle_type
              ) AS metadata,
              t.received_at AS occurred_at
            FROM trips t
            JOIN users u ON u.id = t.user_id

            UNION ALL

            SELECT 'alert' AS kind, a.id::text AS id, NULL AS actor,
              json_build_object(
                'alertKind', a.kind,
                'status', a.status,
                'recipient', a.to_e164
              ) AS metadata,
              a.created_at AS occurred_at
            FROM alerts a

            UNION ALL

            SELECT 'incident' AS kind, i.id::text AS id, u.display_name AS actor,
              json_build_object('severity', i.severity) AS metadata,
              i.occurred_at AS occurred_at
            FROM circle_incidents i
            JOIN circle_users u ON u.id = i.source_user_id

            UNION ALL

            SELECT 'registration' AS kind, u.id::text AS id, u.display_name AS actor,
              json_build_object('source', 'circle') AS metadata,
              u.created_at AS occurred_at
            FROM circle_users u

            UNION ALL

            SELECT 'registration' AS kind, u.id::text AS id, u.first_name AS actor,
              json_build_object('source', 'profile') AS metadata,
              u.created_at AS occurred_at
            FROM users u
          ) activity
          ORDER BY occurred_at DESC
          LIMIT 18
        `),
        database.query(`
          SELECT
            (SELECT COUNT(*)::int FROM alerts
              WHERE status = 'failed' AND created_at >= now() - interval '24 hours') AS failed_alerts_24h,
            (SELECT COUNT(*)::int FROM alerts
              WHERE status = 'queued' AND created_at < now() - interval '5 minutes') AS stalled_alerts,
            (SELECT COUNT(*)::int FROM circle_incidents
              WHERE severity = 'confirmed' AND occurred_at >= now() - interval '7 days') AS confirmed_incidents_7d,
            (SELECT COUNT(*)::int FROM circle_notifications
              WHERE read_at IS NULL) AS unread_notifications
        `)
      ]);

      const metrics = metricsResult.rows[0];
      const totalAlerts = number(metrics.alerts_7d);
      const failedAlerts = number(metrics.failed_alerts_7d);
      return {
        dataSourceStatus: "connected",
        generatedAt: new Date().toISOString(),
        metrics: {
          circleUsers: number(metrics.circle_users),
          syncedProfiles: number(metrics.synced_profiles),
          trips30d: number(metrics.trips_30d),
          distance30d: number(metrics.distance_30d),
          activeDrivers30d: number(metrics.active_drivers_30d),
          alerts7d: totalAlerts,
          alertSuccessRate7d: totalAlerts === 0
            ? null
            : Math.round(((totalAlerts - failedAlerts) / totalAlerts) * 1_000) / 10,
          incidents30d: number(metrics.incidents_30d),
          relationships: number(metrics.relationships),
          pushReady: number(metrics.push_ready),
          sharedAverageScore: nullableNumber(metrics.shared_average_score),
          latestServerActivity: finiteDate(metrics.latest_server_activity)
        },
        series: seriesResult.rows.map((row) => ({
          date: row.day,
          trips: number(row.trips),
          alerts: number(row.alerts),
          incidents: number(row.incidents),
          registrations: number(row.registrations)
        })),
        activity: feedResult.rows.map(mapActivity),
        interventions: mapInterventions(interventionsResult.rows[0]),
        coverage: {
          circle: "active",
          alerts: "active",
          incidents: "active",
          profiles: number(metrics.synced_profiles) > 0 ? "active" : "waiting",
          trips: number(metrics.trips_30d) > 0 ? "active" : "waiting",
          medical: "never_stored",
          emergencyContacts: "never_stored"
        }
      };
    },

    async listUsers({ search = "", limit = 50, offset = 0 } = {}) {
      const result = await database.query(`
        WITH trip_totals AS (
          SELECT user_id,
            COUNT(*)::int AS trips_count,
            COALESCE(SUM(distance_km), 0)::float8 AS distance_km,
            ROUND(AVG(score))::int AS average_score,
            MAX(received_at) AS last_trip_at
          FROM trips
          GROUP BY user_id
        ), combined AS (
          SELECT
            'circle'::text AS source,
            cu.id,
            cu.display_name AS name,
            NULL::text AS phone_e164,
            NULL::text AS vehicle,
            cu.stats_sharing,
            (cu.push_token IS NOT NULL) AS push_ready,
            COALESCE(cs.trips_count, 0)::int AS trips_count,
            COALESCE(cs.distance_km, 0)::float8 AS distance_km,
            cs.score::int AS average_score,
            cu.created_at,
            GREATEST(cu.updated_at, COALESCE(cs.updated_at, cu.updated_at)) AS last_activity
          FROM circle_users cu
          LEFT JOIN circle_stats cs ON cs.user_id = cu.id

          UNION ALL

          SELECT
            'profile'::text AS source,
            u.id,
            u.first_name AS name,
            u.phone_e164,
            CONCAT_WS(' ', NULLIF(u.vehicle_brand, ''), NULLIF(u.vehicle_model, '')) AS vehicle,
            u.leaderboard_opt_in AS stats_sharing,
            false AS push_ready,
            COALESCE(tt.trips_count, 0)::int AS trips_count,
            COALESCE(tt.distance_km, 0)::float8 AS distance_km,
            tt.average_score,
            u.created_at,
            COALESCE(tt.last_trip_at, u.created_at) AS last_activity
          FROM users u
          LEFT JOIN trip_totals tt ON tt.user_id = u.id
        )
        SELECT *, COUNT(*) OVER()::int AS total_count
        FROM combined
        WHERE $1 = ''
          OR name ILIKE '%' || $1 || '%'
          OR COALESCE(phone_e164, '') ILIKE '%' || $1 || '%'
          OR COALESCE(vehicle, '') ILIKE '%' || $1 || '%'
        ORDER BY last_activity DESC, created_at DESC
        LIMIT $2 OFFSET $3
      `, [search.trim().slice(0, 80), clampLimit(limit), Math.max(0, number(offset))]);

      return {
        total: number(result.rows[0]?.total_count),
        items: result.rows.map((row) => ({
          id: row.id,
          source: row.source,
          name: row.name,
          phone: maskPhone(row.phone_e164),
          vehicle: row.vehicle || null,
          statsSharing: Boolean(row.stats_sharing),
          pushReady: Boolean(row.push_ready),
          tripsCount: number(row.trips_count),
          distanceKm: number(row.distance_km),
          averageScore: nullableNumber(row.average_score),
          createdAt: row.created_at,
          lastActivity: row.last_activity
        }))
      };
    },

    async listTrips({ limit = 50, offset = 0 } = {}) {
      const result = await database.query(`
        SELECT
          t.id, t.start_date, t.end_date, t.distance_km, t.duration_sec,
          t.avg_speed_kmh, t.max_speed_kmh, t.score, t.is_calibration,
          t.vehicle_type, t.role, t.received_at, u.first_name,
          COUNT(*) OVER()::int AS total_count
        FROM trips t
        JOIN users u ON u.id = t.user_id
        ORDER BY t.start_date DESC
        LIMIT $1 OFFSET $2
      `, [clampLimit(limit), Math.max(0, number(offset))]);
      return {
        total: number(result.rows[0]?.total_count),
        items: result.rows.map((row) => ({
          id: row.id,
          userName: row.first_name,
          startDate: row.start_date,
          endDate: row.end_date,
          distanceKm: number(row.distance_km),
          durationSec: number(row.duration_sec),
          averageSpeedKmh: number(row.avg_speed_kmh),
          maxSpeedKmh: number(row.max_speed_kmh),
          score: nullableNumber(row.score),
          calibration: Boolean(row.is_calibration),
          vehicleType: row.vehicle_type,
          role: row.role,
          receivedAt: row.received_at
        }))
      };
    },

    async listAlerts({ limit = 50, offset = 0 } = {}) {
      const result = await database.query(`
        SELECT id, kind, to_e164, status, provider_message_id,
          provider_status, provider_code, created_at, updated_at,
          COUNT(*) OVER()::int AS total_count
        FROM alerts
        ORDER BY created_at DESC
        LIMIT $1 OFFSET $2
      `, [clampLimit(limit), Math.max(0, number(offset))]);
      return {
        total: number(result.rows[0]?.total_count),
        items: result.rows.map((row) => ({
          id: row.id,
          kind: row.kind,
          recipient: maskPhone(row.to_e164),
          status: row.status,
          providerMessageId: row.provider_message_id,
          providerStatus: row.provider_status,
          providerCode: row.provider_code,
          createdAt: row.created_at,
          updatedAt: row.updated_at
        }))
      };
    },

    async listIncidents({ limit = 50, offset = 0 } = {}) {
      const result = await database.query(`
        SELECT i.id, i.occurred_at, i.latitude, i.longitude,
          i.accuracy_meters, i.severity, i.created_at,
          u.display_name AS source_name,
          COUNT(n.id)::int AS recipients_count,
          COUNT(n.id) FILTER (WHERE n.read_at IS NOT NULL)::int AS read_count,
          COUNT(*) OVER()::int AS total_count
        FROM circle_incidents i
        JOIN circle_users u ON u.id = i.source_user_id
        LEFT JOIN circle_notifications n ON n.incident_id = i.id
        GROUP BY i.id, u.display_name
        ORDER BY i.occurred_at DESC
        LIMIT $1 OFFSET $2
      `, [clampLimit(limit), Math.max(0, number(offset))]);
      return {
        total: number(result.rows[0]?.total_count),
        items: result.rows.map((row) => ({
          id: row.id,
          sourceName: row.source_name,
          occurredAt: row.occurred_at,
          latitude: roundCoordinate(row.latitude),
          longitude: roundCoordinate(row.longitude),
          accuracyMeters: nullableNumber(row.accuracy_meters),
          severity: row.severity,
          recipientsCount: number(row.recipients_count),
          readCount: number(row.read_count),
          createdAt: row.created_at
        }))
      };
    }
  };
}

export function createEmptyAdminStore() {
  const emptyList = async () => ({ total: 0, items: [] });
  return {
    async getOverview() {
      return {
        dataSourceStatus: "not_configured",
        generatedAt: new Date().toISOString(),
        metrics: {
          circleUsers: 0,
          syncedProfiles: 0,
          trips30d: 0,
          distance30d: 0,
          activeDrivers30d: 0,
          alerts7d: 0,
          alertSuccessRate7d: null,
          incidents30d: 0,
          relationships: 0,
          pushReady: 0,
          sharedAverageScore: null,
          latestServerActivity: null
        },
        series: [],
        activity: [],
        interventions: mapInterventions({}),
        coverage: {
          circle: "waiting",
          alerts: "waiting",
          incidents: "waiting",
          profiles: "waiting",
          trips: "waiting",
          medical: "never_stored",
          emergencyContacts: "never_stored"
        }
      };
    },
    listUsers: emptyList,
    listTrips: emptyList,
    listAlerts: emptyList,
    listIncidents: emptyList
  };
}

function mapActivity(row) {
  const metadata = row.metadata ?? {};
  if (metadata.recipient) metadata.recipient = maskPhone(metadata.recipient);
  return {
    kind: row.kind,
    id: row.id,
    actor: row.actor,
    metadata,
    occurredAt: row.occurred_at
  };
}

function mapInterventions(row) {
  return {
    failedAlerts24h: number(row?.failed_alerts_24h),
    stalledAlerts: number(row?.stalled_alerts),
    confirmedIncidents7d: number(row?.confirmed_incidents_7d),
    unreadNotifications: number(row?.unread_notifications)
  };
}

function maskPhone(value) {
  if (!value) return null;
  const digits = String(value).replace(/\D/g, "");
  if (digits.length <= 4) return `•••• ${digits}`;
  const knownCountry = digits.length === 11 && digits.startsWith("226")
    ? "226"
    : digits.length === 11 && digits.startsWith("1")
      ? "1"
      : null;
  const country = knownCountry ?? digits.slice(0, Math.max(1, digits.length - 8));
  return `+${country} •• •• ${digits.slice(-4)}`;
}

function roundCoordinate(value) {
  const parsed = nullableNumber(value);
  return parsed === null ? null : Math.round(parsed * 1_000) / 1_000;
}

function finiteDate(value) {
  if (!value) return null;
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date.toISOString() : null;
}

function clampLimit(value) {
  return Math.min(100, Math.max(1, number(value) || 50));
}

function number(value) {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function nullableNumber(value) {
  if (value === null || value === undefined) return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}
