# ADR — Reporter Uptime Robot après API verte

Date : 2026-07-03

## Statut

Accepté par le PO.

## Contexte

La Phase 0 demandait initialement un monitor Uptime Robot actif avant la suite de l'exécution. L'API Viim est désormais verte :

- DNS `api.burktech-ia.com` résolu vers `178.105.115.6`.
- TLS valide.
- `/health` public retourne HTTP 200 avec `status: ok`, `db: ok`, `whatsapp: ok`.

La configuration Uptime Robot reste impossible depuis la session Codex faute d'accès/API key.

## Décision

Reporter Uptime Robot et continuer l'exécution Phase 1.

## Contraintes

- Le report ne supprime pas l'exigence.
- Uptime Robot reste obligatoire avant tout testeur externe.
- Aucun service de monitoring alternatif ne remplace Uptime Robot sans nouvelle décision.
