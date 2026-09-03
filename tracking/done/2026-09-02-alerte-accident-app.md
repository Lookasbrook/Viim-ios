# Alerte accident côté app iOS — déclencheur manuel + attestation de consentement

- Démarré / terminé le : 2026-09-02
- Branche : `feat/alerte-accident-app`
- Référence : [architecture/meta-mcp-et-whatsapp.md](../../architecture/meta-mcp-et-whatsapp.md) §4.5 et §4.6

## Contexte

Le backend `POST /v1/alerts/collision` et la cascade proche 1→2→3→4 (§4.4) existaient et
étaient déployés, mais **rien dans l'app iOS ne les appelait** : pas de méthode client, pas
de déclencheur, `TripManager.collisionDetectionEnabled` était un booléen mort. L'attestation
de consentement des proches (`contactsConsent`, attendue par le backend depuis §4.5) n'était
pas non plus envoyée.

Vérifié via le MCP Meta (app « Agent IA » `893267796842438`) : approuvée, conforme, 0
violation, webhooks `whatsapp_business_account` déjà abonnés (`messages`,
`message_template_status_update`, `message_template_quality_update`, `account_update`…) vers
la passerelle NEwAGENT-IA. La configuration Meta est en place ; le MCP ne crée pas de modèles
et n'envoie pas de messages.

## Livré

- `BackendAPIClient.sendCollisionAlert(contacts:driverName:location:medicalProfile:)` →
  `POST /v1/alerts/collision` (jusqu'à 4 contacts, position, `occurredAt`, `contactsConsent`,
  fiche médicale si renseignée — non persistée côté serveur).
- Champ `contactsConsent` ajouté aux payloads `/alerts/{test,location-share,collision}` :
  vrai seulement si **tous** les contacts visés ont `consentAcknowledgedAt`.
- `EmergencyContact.consentAcknowledgedAt: Date?` (compat Keychain : clé absente → `nil`) +
  `hasProchesConsent`. `BurkinaPhoneNumber.normalizedContact` conserve la valeur.
- `AssistanceView` : bouton **« J'ai eu un accident »**. Position GPS fraîche (< 2 min) →
  `CollisionCountdownSheet` (compte à rebours 10 s annulable, envoi auto à zéro) → endpoint →
  retour utilisateur (proche prévenu / erreur réseau).
- `EmergencyContactsView` : `Toggle` de consentement **obligatoire** avant d'enregistrer un
  contact ; contacts d'avant cette version marqués « accord non confirmé ».
- `OnboardingView` (`safetyStep`) : même `Toggle` ; pas d'enregistrement du contact sans la
  case cochée.
- Chaînes FR (`Localizable.strings`, ~20 clés `assistance.collision.*`,
  `assistance.contacts.consent.*`, `onboarding.safety.consent.*`).
- Tests : `BackendAPIClientTests` — payload collision (contacts, `occurredAt`, `location`,
  `medicalProfile` omis si vide), `contactsConsent` vrai/faux selon les contacts. Build iOS
  `** TEST BUILD SUCCEEDED **`, `BackendAPIClientTests` 5/5, `BurkinaPhoneNumberTests` 7/7.

## Écarts par rapport à la demande initiale

La demande couvrait aussi la **détection automatique de collision**. Elle est découpée en un
lot séparé (voir « Reste à faire ») : bouton manuel livré d'abord, détection auto ensuite
derrière le flag existant.

## Reste à faire

### Lot 2 — détection automatique (app iOS, non commencé)

- Service `CollisionDetector` : CoreMotion accéléromètre haute fréquence, seuil en g +
  fenêtre de confirmation, **armé seulement pendant un trajet actif** (`LocationService.activeTrip`).
- Sur choc : `TripManager.collisionDetectionEnabled = true` (statut « actif » sur l'accueil,
  aujourd'hui « en préparation »), notification locale + feuille de confirmation 15 s
  annulable → `BackendAPIClient.sendCollisionAlert(...)`.
- Câblage dans `ViimApp` / `TripDetectionCoordinator` ; réglage pour couper les faux positifs
  (nids-de-poule, chute du téléphone). Nouveaux fichiers → entrée `ios/Viim.xcodeproj/project.pbxproj`.
- Tests avec traces d'accélération simulées.

### Opérateur — activation prod (secrets / dashboard Meta, hors dépôt)

1. `WABA_ID=… META_TOKEN=… node backend/scripts/create-whatsapp-templates.mjs --apply`
   (token `whatsapp_business_management`) puis **attendre `APPROVED`** pour
   `viim_alert_test` / `viim_collision_alert` / `viim_location_share`. Si les noms diffèrent,
   aligner `META_TEMPLATES` dans `backend/src/services/newagent.js`.
2. Choix du canal prod : soit mettre à jour la passerelle NEwAGENT-IA pour lire `kind` +
   `params` et choisir le modèle, soit pointer `NEWAGENT_SEND_URL` directement sur Graph API
   (`https://graph.facebook.com/<version>/<phone_number_id>/messages`) — le code backend gère
   déjà les deux modes.
3. Coolify : renseigner `WHATSAPP_VERIFY_TOKEN`, `WHATSAPP_WEBHOOK_SHARED_TOKEN` (ou
   `WHATSAPP_APP_SECRET` si Meta appelle Viim en direct), puis `npm run migrate` avant le
   premier trafic.
4. Vérifier l'abonnement webhook `messages` + `message_template_status_update` du WABA
   d'envoi (`devtools_webhook_list list_subscriptions` ; `devtools_webhook_manage subscribe`
   en portée `Manage` si manquant — action tracée, revenir à `Read` ensuite).
5. Quand tous les builds iOS déployés envoient `contactsConsent`, passer
   `REQUIRE_CONTACTS_CONSENT=true` côté Coolify.
