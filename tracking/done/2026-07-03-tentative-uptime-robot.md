# Tentative configuration Uptime Robot — 2026-07-03

- Tâche : créer le monitor Uptime Robot Phase 0.
- Endpoint cible : `https://api.burktech-ia.com/health`
- Vérification préalable :
  - DNS public OK : `api.burktech-ia.com -> 178.105.115.6`
  - Health public OK : `HTTP/2 200`
  - JSON : `{"status":"ok","api":"ok","db":"ok","whatsapp":"ok","version":"0.1.0"}`
- Recherche d'accès local :
  - Aucune variable `UPTIMEROBOT`, `UPTIME_ROBOT` ou équivalent dans l'environnement.
  - Aucune CLI `uptimerobot` installée.
  - Aucune configuration locale Uptime Robot trouvée dans les fichiers inspectés.
- Statut : bloqué par absence d'accès Uptime Robot/API key. Ne pas créer d'alternative silencieuse ; la DoD Phase 0 demande explicitement Uptime Robot.
