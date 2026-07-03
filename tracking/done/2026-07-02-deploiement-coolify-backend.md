# Déploiement Coolify backend — 2026-07-02

- Tâche : déployer le backend Viim sur le VPS Hetzner via Coolify.
- VPS : `178.105.115.6`
- App Coolify : `Viim`
- App UUID : `blqn1beg8ae0dvddmqio6rth`
- URL Coolify : `http://178.105.115.6:8000/project/xkfjzfvxqfdi8gj9xyja8dn9/environment/n3z5uix690oli7wax282vgv3/application/blqn1beg8ae0dvddmqio6rth`
- Repo déployé : `Lookasbrook/Viim-ios.git`
- Commit déployé : `4dd4ca395cdf7e004c4fae22156f523add79e24a`
- Root directory Coolify : `/backend`
- Dockerfile Coolify : `/Dockerfile` (donc `backend/Dockerfile` dans le repo)
- Port exposé : `3000`
- Domaine configuré : `https://api.burktech-ia.com`

## PostgreSQL

- Base Coolify : `Viim PostgreSQL`
- DB UUID : `v46pxb68fon91lz66pdyomot`
- Statut : healthy
- Migration initiale appliquée : `users`, `trips`, `trip_events`, `daily_summaries`

## Variables

- Configurées : `NODE_ENV=production`, `PORT=3000`, `HOST=0.0.0.0`, `DATABASE_URL`
- En attente : `NEWAGENT_URL`, `NEWAGENT_TOKEN`

## Vérifications

- DNS public : `api.burktech-ia.com` retourne `NXDOMAIN`.
- Health public : `curl https://api.burktech-ia.com/health` échoue avec `Could not resolve host`.
- Health forcé vers le VPS : `{"status":"degraded","api":"ok","db":"ok","whatsapp":"not_configured","version":"0.1.0"}`

## Statut

Backend et PostgreSQL déployés. Phase 0 reste bloquée par DNS public, secrets NEwAGENT-IA et Uptime Robot.
