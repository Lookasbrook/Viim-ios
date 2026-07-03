# ADR — API Viim sur sous-domaine dédié `api.burktech-ia.com`

**Date** : 2026-07-01 · **Statut** : Accepté · **Décideur** : Claude (Architecte/QA), tranché pour débloquer le builder

## Contexte
`blueprints/02-backend-coolify.md` laissait le choix ouvert entre déployer `viim-api` sur le domaine racine `burktech-ia.com` ou sur un sous-domaine dédié, avec ADR obligatoire. NEwAGENT-IA (WhatsApp) tourne déjà sur le même VPS Hetzner CX33, potentiellement sur `burktech-ia.com`.

## Décision
**Sous-domaine dédié : `api.burktech-ia.com`.** Base URL de l'API Viim : `https://api.burktech-ia.com/v1`.

## Justification
- Coolify attribue un domaine par application déployée : partager `burktech-ia.com` entre NEwAGENT-IA et `viim-api` obligerait à gérer le routing par chemin (reverse-proxy manuel), fragile et hors du fonctionnement standard de Coolify.
- Isolation des certificats et des déploiements : un déploiement ou incident sur `viim-api` ne touche jamais NEwAGENT-IA, et inversement.
- Cohérent avec un futur portage Android (ADR [ios-first](2026-07-01-ios-first.md)) : le sous-domaine `api.` reste stable même si `burktech-ia.com` héberge d'autres services internes YAMSTACK à l'avenir.
- Monitoring `/health` (Uptime Robot) cible une URL stable et unique, sans ambiguïté avec les endpoints de NEwAGENT-IA.

## Conséquences
- Base URL API : `https://api.burktech-ia.com/v1` (remplace `https://burktech-ia.com/api/v1` dans `architecture/api-endpoints.md`).
- Health check : `https://api.burktech-ia.com/health` (remplace les occurrences dans `blueprints/02-backend-coolify.md` et `qa/test-plan.md`).
- Prérequis DNS à ajouter avant le déploiement P0 : enregistrement `api.burktech-ia.com` → IP du VPS Hetzner CX33 (à créer par Guy ou dans Coolify si gestion DNS intégrée).
- Aucun impact sur NEwAGENT-IA, qui garde son endpoint actuel sur `burktech-ia.com`.
