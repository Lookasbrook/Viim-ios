import { randomUUID } from "node:crypto";
import { pool } from "../db/pool.js";

export function createCircleStore(database = pool) {
  return database ? createPostgresCircleStore(database) : createMemoryCircleStore();
}

function createPostgresCircleStore(database) {
  return {
    async registerUser({ id, installationId, displayName, authTokenHash, pushEnvironment }) {
      const result = await database.query(
        `
        INSERT INTO circle_users (
          id, installation_id, display_name, auth_token_hash, push_environment
        )
        VALUES ($1, $2, $3, $4, $5)
        ON CONFLICT (installation_id) DO UPDATE SET
          display_name = EXCLUDED.display_name,
          push_environment = EXCLUDED.push_environment,
          updated_at = now()
        WHERE circle_users.auth_token_hash = EXCLUDED.auth_token_hash
        RETURNING id, display_name, stats_sharing
        `,
        [id, installationId, displayName, authTokenHash, pushEnvironment]
      );
      return result.rows[0] ? mapUser(result.rows[0]) : null;
    },

    async authenticate(authTokenHash) {
      const result = await database.query(
        `
        SELECT id, display_name, push_token, push_environment, stats_sharing
        FROM circle_users
        WHERE auth_token_hash = $1
        `,
        [authTokenHash]
      );
      return result.rows[0] ? mapUser(result.rows[0]) : null;
    },

    async updateProfile(userId, { displayName, pushToken, pushEnvironment, statsSharing }) {
      const result = await database.query(
        `
        UPDATE circle_users
        SET display_name = COALESCE($2, display_name),
            push_token = CASE WHEN $3::boolean THEN $4 ELSE push_token END,
            push_environment = COALESCE($5, push_environment),
            stats_sharing = COALESCE($6, stats_sharing),
            updated_at = now()
        WHERE id = $1
        RETURNING id, display_name, push_token, push_environment, stats_sharing
        `,
        [
          userId,
          displayName ?? null,
          pushToken !== undefined,
          pushToken ?? null,
          pushEnvironment ?? null,
          statsSharing ?? null
        ]
      );
      return mapUser(result.rows[0]);
    },

    async createInvitation({ id, inviterUserId, tokenHash, expiresAt }) {
      await database.query(
        `
        INSERT INTO circle_invitations (id, inviter_user_id, token_hash, expires_at)
        VALUES ($1, $2, $3, $4)
        `,
        [id, inviterUserId, tokenHash, expiresAt]
      );
    },

    async findInvitation(tokenHash) {
      const result = await database.query(
        `
        SELECT i.id, i.inviter_user_id, i.expires_at, i.accepted_by_user_id,
               u.display_name AS inviter_display_name
        FROM circle_invitations i
        JOIN circle_users u ON u.id = i.inviter_user_id
        WHERE i.token_hash = $1
        `,
        [tokenHash]
      );
      return result.rows[0] ? mapInvitation(result.rows[0]) : null;
    },

    async acceptInvitation({ invitationId, acceptingUserId, firstUserId, secondUserId, relationshipId }) {
      const client = await database.connect();
      try {
        await client.query("BEGIN");
        const invitationResult = await client.query(
          `
          UPDATE circle_invitations
          SET accepted_by_user_id = $2, accepted_at = now()
          WHERE id = $1 AND accepted_at IS NULL AND expires_at > now()
          RETURNING id
          `,
          [invitationId, acceptingUserId]
        );
        if (invitationResult.rowCount !== 1) {
          await client.query("ROLLBACK");
          return false;
        }
        await client.query(
          `
          INSERT INTO circle_relationships (id, first_user_id, second_user_id)
          VALUES ($1, $2, $3)
          ON CONFLICT (first_user_id, second_user_id) DO NOTHING
          `,
          [relationshipId, firstUserId, secondUserId]
        );
        await client.query("COMMIT");
        return true;
      } catch (error) {
        await client.query("ROLLBACK");
        throw error;
      } finally {
        client.release();
      }
    },

    async listMembers(userId) {
      const result = await database.query(
        `
        SELECT r.id AS relationship_id,
               member.id, member.display_name, member.stats_sharing,
               s.score, s.trips_count, s.distance_km, s.safe_streak,
               s.period_start, s.updated_at
        FROM circle_relationships r
        JOIN circle_users member
          ON member.id = CASE
            WHEN r.first_user_id = $1 THEN r.second_user_id
            ELSE r.first_user_id
          END
        LEFT JOIN circle_stats s ON s.user_id = member.id AND member.stats_sharing = true
        WHERE r.first_user_id = $1 OR r.second_user_id = $1
        ORDER BY member.display_name ASC
        `,
        [userId]
      );
      return result.rows.map(mapMember);
    },

    async removeRelationship(userId, relationshipId) {
      const result = await database.query(
        `
        DELETE FROM circle_relationships
        WHERE id = $1 AND (first_user_id = $2 OR second_user_id = $2)
        `,
        [relationshipId, userId]
      );
      return result.rowCount === 1;
    },

    async upsertStats(userId, stats) {
      await database.query(
        `
        INSERT INTO circle_stats (
          user_id, score, trips_count, distance_km, safe_streak, period_start
        )
        VALUES ($1, $2, $3, $4, $5, $6)
        ON CONFLICT (user_id) DO UPDATE SET
          score = EXCLUDED.score,
          trips_count = EXCLUDED.trips_count,
          distance_km = EXCLUDED.distance_km,
          safe_streak = EXCLUDED.safe_streak,
          period_start = EXCLUDED.period_start,
          updated_at = now()
        `,
        [userId, stats.score, stats.tripsCount, stats.distanceKm, stats.safeStreak, stats.periodStart]
      );
    },

    async createIncident({ incident, recipientIds }) {
      const client = await database.connect();
      try {
        await client.query("BEGIN");
        await client.query(
          `
          INSERT INTO circle_incidents (
            id, source_user_id, occurred_at, latitude, longitude,
            accuracy_meters, severity
          )
          VALUES ($1, $2, $3, $4, $5, $6, $7)
          `,
          [
            incident.id,
            incident.sourceUserId,
            incident.occurredAt,
            incident.latitude,
            incident.longitude,
            incident.accuracyMeters,
            incident.severity
          ]
        );
        for (const recipientId of recipientIds) {
          await client.query(
            `
            INSERT INTO circle_notifications (id, recipient_user_id, incident_id)
            VALUES ($1, $2, $3)
            ON CONFLICT (recipient_user_id, incident_id) DO NOTHING
            `,
            [randomUUID(), recipientId, incident.id]
          );
        }
        await client.query("COMMIT");
      } catch (error) {
        await client.query("ROLLBACK");
        throw error;
      } finally {
        client.release();
      }
    },

    async listIncidentRecipients(userId) {
      const result = await database.query(
        `
        SELECT member.id, member.display_name, member.push_token, member.push_environment
        FROM circle_relationships r
        JOIN circle_users member
          ON member.id = CASE
            WHEN r.first_user_id = $1 THEN r.second_user_id
            ELSE r.first_user_id
          END
        WHERE r.first_user_id = $1 OR r.second_user_id = $1
        `,
        [userId]
      );
      return result.rows.map(mapUser);
    },

    async listInbox(userId, limit) {
      const result = await database.query(
        `
        SELECT n.id, n.read_at, n.created_at,
               i.id AS incident_id, i.occurred_at, i.latitude, i.longitude,
               i.accuracy_meters, i.severity,
               source.display_name AS source_display_name
        FROM circle_notifications n
        JOIN circle_incidents i ON i.id = n.incident_id
        JOIN circle_users source ON source.id = i.source_user_id
        WHERE n.recipient_user_id = $1
        ORDER BY n.created_at DESC
        LIMIT $2
        `,
        [userId, limit]
      );
      return result.rows.map(mapNotification);
    },

    async markNotificationRead(userId, notificationId) {
      const result = await database.query(
        `
        UPDATE circle_notifications
        SET read_at = COALESCE(read_at, now())
        WHERE id = $1 AND recipient_user_id = $2
        `,
        [notificationId, userId]
      );
      return result.rowCount === 1;
    }
  };
}

export function createMemoryCircleStore() {
  const users = new Map();
  const usersByToken = new Map();
  const invitations = new Map();
  const relationships = new Map();
  const stats = new Map();
  const incidents = new Map();
  const notifications = new Map();

  return {
    async registerUser(input) {
      const existing = [...users.values()].find((user) => user.installationId === input.installationId);
      if (existing?.authTokenHash === input.authTokenHash) {
        existing.displayName = input.displayName;
        existing.pushEnvironment = input.pushEnvironment;
        return { ...existing };
      }
      if (existing) {
        const error = new Error("duplicate_installation");
        error.code = "23505";
        throw error;
      }
      const user = {
        id: input.id,
        installationId: input.installationId,
        displayName: input.displayName,
        authTokenHash: input.authTokenHash,
        pushToken: null,
        pushEnvironment: input.pushEnvironment,
        statsSharing: false
      };
      users.set(user.id, user);
      usersByToken.set(user.authTokenHash, user.id);
      return { ...user };
    },
    async authenticate(authTokenHash) {
      const id = usersByToken.get(authTokenHash);
      return id ? { ...users.get(id) } : null;
    },
    async updateProfile(userId, changes) {
      const user = users.get(userId);
      if (!user) return null;
      if (changes.displayName !== undefined) user.displayName = changes.displayName;
      if (changes.pushToken !== undefined) user.pushToken = changes.pushToken;
      if (changes.pushEnvironment !== undefined) user.pushEnvironment = changes.pushEnvironment;
      if (changes.statsSharing !== undefined) user.statsSharing = changes.statsSharing;
      return { ...user };
    },
    async createInvitation(invitation) {
      invitations.set(invitation.tokenHash, { ...invitation, acceptedByUserId: null });
    },
    async findInvitation(tokenHash) {
      const invitation = invitations.get(tokenHash);
      if (!invitation) return null;
      return {
        ...invitation,
        inviterDisplayName: users.get(invitation.inviterUserId)?.displayName ?? "Viim"
      };
    },
    async acceptInvitation({ invitationId, acceptingUserId, firstUserId, secondUserId, relationshipId }) {
      const invitation = [...invitations.values()].find((item) => item.id === invitationId);
      if (!invitation || invitation.acceptedByUserId || invitation.expiresAt <= new Date()) return false;
      invitation.acceptedByUserId = acceptingUserId;
      relationships.set(relationshipId, { id: relationshipId, firstUserId, secondUserId });
      return true;
    },
    async listMembers(userId) {
      return [...relationships.values()]
        .filter((relationship) => relationship.firstUserId === userId || relationship.secondUserId === userId)
        .map((relationship) => {
          const memberId = relationship.firstUserId === userId
            ? relationship.secondUserId
            : relationship.firstUserId;
          const member = users.get(memberId);
          return {
            relationshipId: relationship.id,
            id: member.id,
            displayName: member.displayName,
            statsSharing: member.statsSharing,
            stats: member.statsSharing ? (stats.get(member.id) ?? null) : null
          };
        });
    },
    async removeRelationship(userId, relationshipId) {
      const relationship = relationships.get(relationshipId);
      if (!relationship || (relationship.firstUserId !== userId && relationship.secondUserId !== userId)) {
        return false;
      }
      relationships.delete(relationshipId);
      return true;
    },
    async upsertStats(userId, value) {
      stats.set(userId, { ...value, updatedAt: new Date() });
    },
    async listIncidentRecipients(userId) {
      const memberIds = [...relationships.values()]
        .filter((relationship) => relationship.firstUserId === userId || relationship.secondUserId === userId)
        .map((relationship) => relationship.firstUserId === userId
          ? relationship.secondUserId
          : relationship.firstUserId);
      return memberIds.map((id) => ({ ...users.get(id) }));
    },
    async createIncident({ incident, recipientIds }) {
      incidents.set(incident.id, { ...incident });
      for (const recipientUserId of recipientIds) {
        const id = randomUUID();
        notifications.set(id, {
          id,
          recipientUserId,
          incidentId: incident.id,
          readAt: null,
          createdAt: new Date()
        });
      }
    },
    async listInbox(userId, limit) {
      return [...notifications.values()]
        .filter((item) => item.recipientUserId === userId)
        .sort((left, right) => right.createdAt - left.createdAt)
        .slice(0, limit)
        .map((item) => {
          const incident = incidents.get(item.incidentId);
          return {
            id: item.id,
            readAt: item.readAt,
            createdAt: item.createdAt,
            incidentId: incident.id,
            occurredAt: incident.occurredAt,
            latitude: incident.latitude,
            longitude: incident.longitude,
            accuracyMeters: incident.accuracyMeters,
            severity: incident.severity,
            sourceDisplayName: users.get(incident.sourceUserId)?.displayName ?? "Viim"
          };
        });
    },
    async markNotificationRead(userId, notificationId) {
      const notification = notifications.get(notificationId);
      if (!notification || notification.recipientUserId !== userId) return false;
      notification.readAt ??= new Date();
      return true;
    }
  };
}

function mapUser(row) {
  return {
    id: row.id,
    displayName: row.display_name,
    pushToken: row.push_token ?? null,
    pushEnvironment: row.push_environment,
    statsSharing: row.stats_sharing
  };
}

function mapInvitation(row) {
  return {
    id: row.id,
    inviterUserId: row.inviter_user_id,
    inviterDisplayName: row.inviter_display_name,
    expiresAt: new Date(row.expires_at),
    acceptedByUserId: row.accepted_by_user_id
  };
}

function mapMember(row) {
  const hasStats = row.stats_sharing && row.period_start;
  return {
    relationshipId: row.relationship_id,
    id: row.id,
    displayName: row.display_name,
    statsSharing: row.stats_sharing,
    stats: hasStats ? {
      score: row.score,
      tripsCount: Number(row.trips_count),
      distanceKm: Number(row.distance_km),
      safeStreak: Number(row.safe_streak),
      periodStart: row.period_start,
      updatedAt: row.updated_at
    } : null
  };
}

function mapNotification(row) {
  return {
    id: row.id,
    readAt: row.read_at,
    createdAt: row.created_at,
    incidentId: row.incident_id,
    occurredAt: row.occurred_at,
    latitude: Number(row.latitude),
    longitude: Number(row.longitude),
    accuracyMeters: row.accuracy_meters === null ? null : Number(row.accuracy_meters),
    severity: row.severity,
    sourceDisplayName: row.source_display_name
  };
}
