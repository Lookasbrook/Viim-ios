# Health API Viim OK — 2026-07-03

- Tâche : finaliser la configuration NEwAGENT côté backend Coolify.
- Variables runtime confirmées par l'agent infrastructure :
  - `has_DATABASE_URL=true`
  - `has_NEWAGENT_URL=true`
  - `has_NEWAGENT_TOKEN=true`
  - `env=production`
  - `port=3000`
- Secret : le token NEwAGENT a été généré/configuré dans Coolify sans être affiché ni écrit dans le repo.
- Vérification publique :
  - `HTTP/2 200`
  - `{"status":"ok","api":"ok","db":"ok","whatsapp":"ok","version":"0.1.0"}`
- DNS : `api.burktech-ia.com -> 178.105.115.6`
- Statut : API Phase 0 verte. Uptime Robot reste à créer.
