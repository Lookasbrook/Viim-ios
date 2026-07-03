# Vérification runtime NEwAGENT — 2026-07-03

- Tâche : vérifier l'état runtime après correction DNS et configuration partielle NEwAGENT.
- DNS public : `dig @1.1.1.1 api.burktech-ia.com A +short` -> `178.105.115.6`.
- Health public Viim :
  - `HTTP/2 503`
  - `{"status":"degraded","api":"ok","db":"ok","whatsapp":"not_configured","version":"0.1.0"}`
- Variables runtime rapportées par l'agent VPS :
  - `has_NEWAGENT_URL=true`
  - `has_NEWAGENT_TOKEN=false`
  - `has_DATABASE_URL=true`
- Conclusion : Phase 0 reste bloquée uniquement par l'absence du vrai `NEWAGENT_TOKEN` dans Coolify, puis par la configuration Uptime Robot après health OK.
