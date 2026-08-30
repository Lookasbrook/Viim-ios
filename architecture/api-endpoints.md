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
| POST | `/alerts/collision` | Alerte collision. Envoi immédiat au premier contact joignable, puis **cascade** : contact suivant si aucun n'a `read` 5 min après le dernier envoi (worker backend). Réponse < 2 s attendue. |
| POST | `/alerts/test` | Envoi d'un message WhatsApp de test à un contact (bouton "Envoyer un test") |
| POST | `/alerts/location-share` | Partage de position ponctuel vers un contact choisi |
| GET | `/alerts/{id}` | Statut interne d'une alerte : `queued`, `sent`, `delivered`, `read` ou `failed`. Réservé monitoring/support. |

Contrat WhatsApp backend :

- Une réponse `200` sur `POST /alerts/*` signifie que NEwAGENT-IA a retourné un identifiant provider exploitable (`providerMessageId`). Un simple `2xx` sans identifiant est traité comme échec.
- `POST /alerts/test` et `/alerts/location-share` — succès : `{ "status": "sent", "alertId": "...", "providerMessageId": "...", "providerStatus": 202 }`.
- `POST /alerts/collision` — succès : `{ "status": "sent", "incidentId": "...", "sentCount": 1, "failedCount": N, "escalation": { "pendingContacts": M, "escalateAfterMinutes": 5 } | null, "deliveries": [ ... ] }`. `incidentId` est généré côté serveur ; l'`incidentId` du client reste dans `metadata`.
- Réponse échec provider : `503` avec `{ "error": "newagent_unavailable", "alertId": "...", "providerCode": "..." }`. Pour `/collision`, ce `503` n'apparaît que si **aucun** contact n'a pu être joint. Le client peut basculer en fallback SMS.
- Si l'alerte ne peut pas être écrite en `queued` avant l'appel provider, le backend retourne `503 alert_store_unavailable` et n'appelle pas le provider.
- Les preuves d'envoi sont persistées dans `alerts` : `alertId`, type, destinataire E.164, statut, code provider, identifiant provider, `incident_id`, `contact_index`, `delivered_at`, `read_at` et horodatages.
- **Cascade** (`collision_escalations`) : le worker (`setInterval` 60 s, actif si `DATABASE_URL`) relance le contact suivant tant qu'aucun contact de l'incident n'est `read` et que la liste n'est pas épuisée. Nécessite le webhook entrant branché pour recevoir les `read`.
- **Opt-in contacts** : les 3 routes `/alerts/*` acceptent `contactsConsent` (`true` / `false` / `{ "acknowledged": bool }`), enregistré dans `alerts.contacts_consent`. Avec `REQUIRE_CONTACTS_CONSENT=true`, une alerte sans `contactsConsent: true` est refusée : `422 { "error": "contacts_consent_required" }`. Défaut `false` : l'alerte part, l'absence est seulement journalisée.
- Déploiement backend : exécuter `npm run migrate` (migrations `006`, `007`, `008` incluses) avant le premier trafic.

### Modèles WhatsApp (mode Meta natif)

Quand `NEWAGENT_SEND_URL` pointe directement `graph.facebook.com/.../messages`, `newagent.js`
envoie des modèles approuvés (obligatoire hors fenêtre de service de 24 h). Sinon, la passerelle
NEwAGENT-IA reçoit `{ source, channel, kind, to, message, metadata }` et reste responsable du choix
du modèle.

| `kind` | Modèle | Catégorie | Corps | Bouton |
|---|---|---|---|---|
| `alert_test` | `viim_alert_test` | utility | statique | — |
| `collision` | `viim_collision_alert` | utility | `{{1}}` nom conducteur, `{{2}}` coordonnées | URL `https://maps.google.com/?q={{1}}` (suffixe `lat,lon`) |
| `location_share` | `viim_location_share` | utility | `{{1}}` nom conducteur, `{{2}}` coordonnées | URL `https://maps.google.com/?q={{1}}` (suffixe `lat,lon`) |

Création : `node backend/scripts/create-whatsapp-templates.mjs --apply` (`WABA_ID`, `META_TOKEN`).
Détails et suite : [meta-mcp-et-whatsapp.md](meta-mcp-et-whatsapp.md) §4.1.

### Webhook WhatsApp entrant

| Méthode | Endpoint | Description |
|---|---|---|
| GET | `/v1/webhooks/whatsapp` | Vérification d'abonnement Meta. Renvoie `hub.challenge` (texte brut) si `hub.verify_token` == `WHATSAPP_VERIFY_TOKEN`, sinon `403`. |
| POST | `/v1/webhooks/whatsapp` | Événements Meta. Acquitte `200` immédiatement puis traite en différé, idempotent sur l'identifiant d'événement (table `whatsapp_webhook_events`). |

- **Auth des POST** : `X-Hub-Signature-256` (HMAC SHA-256 du corps brut avec `WHATSAPP_APP_SECRET`) si Meta appelle en direct ; sinon `Authorization: Bearer <WHATSAPP_WEBHOOK_SHARED_TOKEN>` si NEwAGENT-IA relaie. Aucun des deux configuré → `503 webhook_not_configured`. Signature/bearer invalide → `403`.
- **`messages[]` texte == STOP** (casse, accents et espaces normalisés) → `users.daily_summary_opt_out = true` pour le numéro émetteur.
- **`statuses[]`** (`sent` / `delivered` / `read` / `failed`) → met à jour l'alerte via `provider_message_id`, sans jamais reculer le statut ; `delivered_at` / `read_at` renseignés.
- Migration `006_whatsapp_inbound.sql` : ajoute le statut `read`, `delivered_at`, `read_at`, la table d'idempotence et l'index `users(phone_e164)`. Lancer `npm run migrate`.

## Prévention (données statiques versionnées)

| Méthode | Endpoint | Description |
|---|---|---|
| GET | `/prevention/danger-zones` | Zones accidentogènes Ouagadougou (données ONASER, mise à jour manuelle par release) |
| GET | `/prevention/road-conditions` | Alertes actives : saison des pluies, harmattan, travaux, pénuries carburant |

## Tâches planifiées (backend)

| Tâche | Horaire | Description |
|---|---|---|
| Cascade alertes collision | toutes les 60 s | Relance le contact suivant si aucun n'a `read` 5 min après le dernier envoi. Voir [meta-mcp-et-whatsapp.md](meta-mcp-et-whatsapp.md) §4.4. |
| Recalcul moyennes communautaires | 02h00 | Agrégats par critère, hors trajets calibration |

> ~~Résumé journalier WhatsApp 20h00~~ — **abandonné** (décision 2026-08-29). Doublon avec l'écran stats du cercle ; catégorie marketing (coût, opt-in, risque qualité du numéro). `features/backend-resume-whatsapp.md` est caduc.

## Codes d'erreur communs

`401` token invalide · `409` trajet déjà synchronisé (ignoré, succès logique) · `422` payload invalide · `503` NEwAGENT-IA indisponible → le client bascule en SMS fallback pour les alertes.

## Administration privée

Base : `https://api.burktech-ia.com/admin`. Ces routes utilisent une session admin signée distincte des jetons des appareils et ne doivent jamais être appelées par l'app iOS.

| Méthode | Endpoint | Description |
|---|---|---|
| GET | `/admin` | Interface du poste de contrôle ; redirection vers la connexion sans session valide. |
| POST | `/admin/api/login` | Ouvre une session `HttpOnly`, `SameSite=Strict`, limitée dans le temps. |
| POST | `/admin/api/logout` | Ferme la session admin. |
| GET | `/admin/api/overview` | Indicateurs, série 14 jours, activité récente, interventions et couverture. |
| GET | `/admin/api/users` | Comptes du cercle et futurs profils synchronisés ; téléphones masqués. |
| GET | `/admin/api/trips` | Trajets présents côté serveur. |
| GET | `/admin/api/alerts` | Preuves d'acheminement WhatsApp ; destinataires masqués. |
| GET | `/admin/api/incidents` | Incidents du cercle ; coordonnées arrondies à trois décimales. |
| GET | `/admin/api/system` | État de l'API, PostgreSQL, WhatsApp et de l'accès admin. |

Configuration et limites : [admin-dashboard.md](admin-dashboard.md).
