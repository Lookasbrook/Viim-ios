# API Backend — Endpoints

Base : `https://api.burktech-ia.com/v1` ([ADR sous-domaine](../decisions/2026-07-01-sous-domaine-api.md)) — Auth : Bearer token par appareil (émis à l'inscription). Toutes les réponses en JSON.

## Santé & monitoring

| Méthode | Endpoint | Description |
|---|---|---|
| GET | `/health` | Statut API + DB + NEwAGENT-IA. Surveillé par Uptime Robot toutes les 5 min (alerte SMS + WhatsApp si down). **À configurer avant le premier utilisateur externe.** |

## Utilisateurs

| Méthode | Endpoint | Description |
|---|---|---|
| POST | `/users/register` | Inscription : prénom, téléphone E.164, véhicule (type, marque, modèle, année) → token. La photo du véhicule n'est jamais transmise. |
| PATCH | `/users/me` | Mise à jour profil (véhicule, opt-in classement, préférences notifications) |
| DELETE | `/users/me/history` | Suppression historique backend (droit à l'effacement) |
| GET | `/users/me/export` | Export JSON complet (portabilité) |

## Trajets & sync

| Méthode | Endpoint | Description |
|---|---|---|
| POST | `/trips/batch` | Sync différée : lot de trajets + événements avec flag `calibration`. Idempotent par `trip.id` (re-sync sans doublon). |
| GET | `/community/averages` | Moyennes Ouagadougou par critère (curseur "Les autres") — cache local 24h |
| GET | `/leaderboard` | Classement anonymisé du mois (uniquement si opt-in) |

## Urgence

| Méthode | Endpoint | Description |
|---|---|---|
| POST | `/alerts/collision` | Micro-sync collision (payload dans data-models.md). Déclenche la cascade WhatsApp : contact 1 → contact 2 si non-lu 5 min → contact 3. Réponse < 2 s attendue. |
| POST | `/alerts/test` | Envoi d'un message WhatsApp de test à un contact (bouton "Envoyer un test") |
| POST | `/alerts/location-share` | Partage de position ponctuel vers un contact choisi |

## Prévention (données statiques versionnées)

| Méthode | Endpoint | Description |
|---|---|---|
| GET | `/prevention/danger-zones` | Zones accidentogènes Ouagadougou (données ONASER, mise à jour manuelle par release) |
| GET | `/prevention/road-conditions` | Alertes actives : saison des pluies, harmattan, travaux, pénuries carburant |

## Tâches planifiées (backend)

| Tâche | Horaire | Description |
|---|---|---|
| Résumé journalier WhatsApp | 20h00 UTC+0 (heure Ouaga) | Via NEwAGENT-IA, pour chaque utilisateur ayant conduit ce jour. Template dans [features/backend-resume-whatsapp.md](../features/backend-resume-whatsapp.md). Opt-out par réponse STOP. |
| Recalcul moyennes communautaires | 02h00 | Agrégats par critère, hors trajets calibration |

## Codes d'erreur communs

`401` token invalide · `409` trajet déjà synchronisé (ignoré, succès logique) · `422` payload invalide · `503` NEwAGENT-IA indisponible → le client bascule en SMS fallback pour les alertes.
