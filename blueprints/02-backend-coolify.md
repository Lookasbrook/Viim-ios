# Blueprint 02 — Backend Viim (Hetzner + Coolify)

## Cible

Node.js (Express ou Fastify — au choix, ADR si Fastify) + PostgreSQL, déployés via **Coolify** sur le VPS Hetzner CX33 existant (`burktech-ia.com`). NEwAGENT-IA (WhatsApp) tourne déjà sur ce VPS.

## Déploiement Coolify

1. Créer une ressource **PostgreSQL** dans Coolify (volume persistant + backups automatiques activés).
2. Créer l'application **viim-api** depuis le repo Git `viim` ([ADR monorepo](../decisions/2026-07-01-repo-monorepo.md)), build context sur le sous-dossier `backend/` (Dockerfile ou buildpack Node), domaine **`api.burktech-ia.com`** ([ADR sous-domaine](../decisions/2026-07-01-sous-domaine-api.md)) — enregistrement DNS à créer avant déploiement.
3. HTTPS automatique (Let's Encrypt via Coolify).
4. **Variables d'environnement Coolify** (jamais dans le repo — les valeurs sont sur le Mac de Guy) :

```
DATABASE_URL=postgres://…
JWT_SECRET=…                  # tokens appareils
NEWAGENT_URL=http://…         # endpoint interne NEwAGENT-IA sur le VPS
NEWAGENT_TOKEN=…
TZ=UTC                        # cron 20h00 UTC = heure de Ouagadougou
NODE_ENV=production
```

## Structure suggérée

Sous `backend/` à la racine du monorepo `viim` :

```
backend/
├── src/
│   ├── routes/   (health, users, trips, alerts, community, prevention — api-endpoints.md)
│   ├── services/ (whatsapp.js → NEwAGENT-IA, scoring-aggregates.js)
│   ├── jobs/     (daily-summary.js 20h00, community-averages.js 02h00 — node-cron)
│   ├── db/       (migrations SQL versionnées — data-models.md §PostgreSQL)
│   └── middleware/ (auth Bearer, validation, log-scrubbing)
└── Dockerfile
```

## Points critiques

1. **`GET /health`** : vérifie API + `SELECT 1` PostgreSQL + ping NEwAGENT-IA → `{status, db, whatsapp, version}`. Configurer **Uptime Robot** dessus (5 min, alertes SMS + WhatsApp) avant tout testeur externe.
2. **`POST /alerts/collision`** : traitement en mémoire uniquement du bloc `medical` — **jamais persisté, jamais loggé** (middleware de scrubbing sur ce champ). Cascade : contact 1 → non-lu 5 min → contact 2 → contact 3. Réponse < 2 s (l'envoi WhatsApp part en asynchrone après ACK).
3. **`POST /trips/batch`** : idempotent par `trip.id` (upsert, `409` logique = succès). Les trajets `calibration=true` sont stockés mais exclus des agrégats.
4. **Résumé 20 h 00** : `daily-summary.js` — uniquement les utilisateurs avec trajets du jour et sans opt-out STOP ; retry 20 h 15 / 20 h 30 ; template exact dans `features/backend-resume-whatsapp.md` (tutoiement, marque Viim).
5. **Webhook STOP** : NEwAGENT-IA doit relayer les réponses "STOP" → `users.dailySummaryOptOut = true`.
6. Logs : jamais de numéro de téléphone en clair (masquer +226XXXX**), jamais de données médicales.

## Definition of Done backend P0

- `curl https://api.burktech-ia.com/health` → 200 vert depuis l'extérieur.
- Uptime Robot actif et alertes testées.
- Migration initiale PostgreSQL appliquée via le pipeline Coolify (pas à la main).
- Un message WhatsApp de test envoyé via `/alerts/test` reçu sur le téléphone de Guy.
