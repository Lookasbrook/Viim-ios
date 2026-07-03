# DNS API Burktech — 2026-07-03

- Tâche : résoudre le blocage DNS `api.burktech-ia.com`.
- Enregistrement attendu : `A api -> 178.105.115.6`.
- Résultat authoritative :
  - `dig @ns1.dns-parking.com +short api.burktech-ia.com A` -> `178.105.115.6`
  - `dig @ns2.dns-parking.com +short api.burktech-ia.com A` -> `178.105.115.6` (rapport agent VPS)
  - `dig @1.1.1.1 +short api.burktech-ia.com A` -> `178.105.115.6` (rapport agent VPS)
- TLS : certificat Let's Encrypt confirmé côté infrastructure pour `CN=api.burktech-ia.com`, expiration `2026-10-01`.
- Vérification Viim forcée vers le VPS :
  - `HTTP/2 503`
  - `{"status":"degraded","api":"ok","db":"ok","whatsapp":"not_configured","version":"0.1.0"}`
- Statut : DNS résolu. Phase 0 reste bloquée par `NEWAGENT_TOKEN` absent et Uptime Robot non configuré.
