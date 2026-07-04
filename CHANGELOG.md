# CHANGELOG — Viim (yamstack-ios)

Toutes les modifications notables du projet, par date (plus récent en haut).

## 2026-07-03

- **[iOS]** Ajout du parcours d'inscription 3 étapes au premier lancement : identité, moyen de déplacement adaptatif, sécurité.
- **[Sécurité]** Contact d'urgence stocké dans le Keychain uniquement ; profil local sauvegardé hors ligne avec `synced=false`.
- **[QA]** Onboarding validé par build simulateur, build signé iPhone réel, installation et lancement de `com.yamstack.viim` sur l'iPhone de Guy.
- **[iOS]** Ajout de `LocationService` : service de position, détection début/fin de trajet, précision normale/économie et état de suivi visible sur l'Accueil.
- **[QA]** Préflight S1 validé sur iPhone réel : build signé, installation et lancement OK ; roulage terrain 20 min écran verrouillé encore à exécuter.
- **[iOS]** Correction de l'affichage plein écran : ajout d'un Launch Screen natif pour supprimer le letterboxing sur iPhone.
- **[Design]** Réalignement des écrans Onboarding et Accueil sur `design/maquettes-ecrans.html` : brand mark, hero, carte véhicule, KPI, statuts et illustration adaptative.
- **[iOS]** Correction de lisibilité en mode sombre : textes explicites sur les cartes des onglets Votre conduite, Assistance et Prévention.
- **[Design]** Ajout du premier visuel système Viim : icône d'application iPhone complète dans `Assets.xcassets`.
- **[Design]** Remplacement des photos génériques par un catalogue local par marque/modèle : Corolla, Hilux, RAV4, Prado, Land Cruiser, Yamaha Crypton/YBR, Bajaj Boxer, TVS Apache et Honda CG125.
- **[QA]** Ajout du target `ViimTests` avec tests XCTest de résolution marque/modèle et vérification que chaque entrée du catalogue pointe vers un asset embarqué.
- **[iOS]** Correction du mode GPS visible après autorisation : Viim ne démarre plus le GPS continu au lancement, ne demande plus `Always` automatiquement et désactive l'indicateur arrière-plan par défaut.
- **[ADR]** Décision `2026-07-03-localisation-discrete-ios` : localisation discrète par défaut, suivi arrière-plan à traiter avec consentement explicite et déclenchement CoreMotion/GPS.
- **[Design]** Réalignement des onglets Votre conduite, Assistance et Prévention sur la maquette HTML : héros, cartes riches, listes d'actions, sections d'urgence, prévention ONASER et entretien.
- **[iOS]** Ajout de la base trajets réelle : modèle CoreData local `Trip`/`TripEvent`/`DailySummary`, `TripStore`, `TripManager`, `synced=false` par défaut et persistance des trajets terminés.
- **[iOS]** Accueil alimenté par les données locales : trajet en cours, résumé du jour, compteur calibration 0/5→5/5 et trajets récents persistés.
- **[iOS]** Onglet Votre conduite : compteurs du héros branchés sur les trajets des 30 derniers jours.
- **[QA]** Ajout de `TripStoreTests` pour valider sauvegarde offline, compteur calibration et protection contre doublons ; `xcodebuild test` simulateur OK, build signé iPhone réel OK, installation et lancement OK.
- **[ADR]** Décision `2026-07-03-coredata-modele-programmatique` : modèle CoreData V1 défini en Swift pour débloquer la persistance locale testable sans `.xcdatamodeld`.
- **[iOS]** Suppression du bouton manuel de suivi : Viim détecte maintenant un déplacement probable via `CoreMotion` et démarre automatiquement la confirmation GPS.
- **[iOS]** Accueil recentré sur les trajets d'aujourd'hui : la liste est filtrée sur la journée en cours et affiche seulement les trajets persistés aujourd'hui.
- **[QA]** Ajout de `MotionActivityServiceTests` pour valider les déclencheurs moto/voiture/vélo, l'immobilité et la faible confiance ; build/test simulateur OK, build signé iPhone réel OK, installation et lancement OK.
- **[ADR]** Décision `2026-07-03-detection-mouvement-sans-bouton` : détection automatique par mouvement, GPS coupé à l'arrêt, pas de friction utilisateur.
- **[iOS]** Correction du parcours du jour absent malgré GPS autorisé : ajout de diagnostics appareil, réveils passifs localisation, promotion GPS continu seulement sur mouvement réel et finalisation de trajet actif après immobilité.
- **[Design]** Accueil : statut `Réveil automatique actif` quand Viim est prêt à démarrer automatiquement un trajet sans suivi GPS continu.
- **[QA]** Diagnostic iPhone réel `TRIP-003` : autorisation `authorizedAlways` confirmée, base appareil vide (`ZTRIP=0`, `ZTRIPEVENT=0`, `ZDAILYSUMMARY=0`), tests simulateur OK, build signé et installation iPhone OK, logs finaux sans démarrage GPS continu à l'arrêt.
- **[ADR]** Décision `2026-07-03-reveils-passifs-localisation` : écoute légère par changements significatifs et impossibilité de reconstruire rétroactivement un trajet non collecté.
- **[Backend]** Ajout des routes Assistance `/v1/alerts/test`, `/v1/alerts/location-share` et `/v1/alerts/collision` avec validation téléphone Burkina, payload position et client NEwAGENT WhatsApp.
- **[iOS]** Onglet Assistance branché : appels `18`/`17`, écran MapKit de localisation, partage de position, contacts d'urgence Keychain, fiche médicale Keychain et bouton test WhatsApp.
- **[iOS]** Suppression du dernier bouton vide dans Votre conduite : `Voir mon style de conduite` ouvre maintenant un écran de portrait détaillé.
- **[QA]** Tests backend Node `alerts.test.js` OK, `npm run check` OK, `xcodebuild test` simulateur OK, build signé iPhone réel OK, installation et lancement iPhone OK.

## 2026-07-02

- **[P0]** Initialisation du repo GitHub cloné `Viim-ios` avec la documentation existante et la structure monorepo `ios/` + `backend/`.
- **[iOS]** Ajout du projet Xcode `Viim` (SwiftUI, iOS 16+, 4 onglets localisés, charte couleurs, background modes, entitlements Push, Team ID `MJJ6A56JHS`).
- **[Backend]** Ajout du squelette `viim-api` Node/Express avec `/health`, migration PostgreSQL initiale et Dockerfile Coolify.
- **[QA]** Build simulateur iOS OK, backend `/health` local OK ; blocages P0 consignés dans `qa/known-issues.md` pour signature iPhone réel, DNS API et SSH Coolify.
- **[QA]** Diagnostic signature iPhone réel affiné : certificat YELIM valide, build de contrôle OK sans APNs, échec normal causé par absence de profil Push `com.yamstack.viim` et par absence de compte Apple visible pour `xcodebuild`.
- **[iOS]** Résolution du build iPhone réel : profil `iOS Team Provisioning Profile: com.yamstack.viim` avec Push activé, build signé OK, installation et lancement confirmés sur l'iPhone de Guy.
- **[iOS]** Correction du packaging app : ajout des clés bundle standard dans `Info.plist` pour permettre l'installation (`CFBundleIdentifier`, version, exécutable, type).
- **[Repo]** Préparation de la publication du monorepo `Viim-ios` vers GitHub afin que Coolify puisse construire `backend/Dockerfile`.
- **[Repo]** Publication effective du monorepo sur `Lookasbrook/Viim-ios`, branche `main`, commit `253ee3a`, pour débloquer la création de l'app Viim dans Coolify.
- **[Backend]** Déploiement Coolify confirmé sur le VPS `178.105.115.6` : app Viim `blqn1beg8ae0dvddmqio6rth`, PostgreSQL Viim `v46pxb68fon91lz66pdyomot`, migrations initiales appliquées, `/health` runtime en `degraded` tant que NEwAGENT-IA n'est pas configuré.
- **[DNS]** Enregistrement `api.burktech-ia.com` corrigé côté authoritative vers `178.105.115.6`; TLS Let's Encrypt confirmé côté infra, mais `/health` reste `degraded` tant que le token NEwAGENT-IA n'est pas configuré.
- **[Backend]** Runtime Viim revérifié : `DATABASE_URL` et `NEWAGENT_URL` sont présents, `NEWAGENT_TOKEN` absent ; `/health` public retourne encore HTTP 503 `degraded`.
- **[Backend]** `NEWAGENT_TOKEN` configuré dans Coolify sans exposition du secret ; `/health` public de Viim retourne HTTP 200 avec `status:"ok"`, DB et WhatsApp OK.
- **[Monitoring]** Uptime Robot reste à configurer : endpoint `/health` prêt et vert, mais aucun accès/API key Uptime Robot disponible dans la session Codex.
- **[Décision]** Report PO de la configuration Uptime Robot : l'exécution Phase 1 peut continuer, mais le monitoring reste obligatoire avant tout testeur externe.

## 2026-07-01 (nuit) — QA pré-handoff builder

- **[ADR]** Les 2 décisions laissées ouvertes dans `blueprints/00-ordre-execution.md` et `02-backend-coolify.md` sont tranchées par Claude (Architecte/QA) pour débloquer le démarrage du builder :
  - Repo Git unique `viim` (monorepo `ios/` + `backend/`) — [décisions/2026-07-01-repo-monorepo.md](decisions/2026-07-01-repo-monorepo.md).
  - API sur sous-domaine dédié `api.burktech-ia.com` (au lieu du domaine racine partagé avec NEwAGENT-IA) — [décisions/2026-07-01-sous-domaine-api.md](decisions/2026-07-01-sous-domaine-api.md).
- **[Sync]** Références mises à jour en conséquence : `blueprints/00-ordre-execution.md`, `01-ios-app.md`, `02-backend-coolify.md`, `architecture/api-endpoints.md`, `architecture/overview.md`, `qa/test-plan.md`.
- **[QA]** Revue complète de la documentation (17 fichiers .md) avant transmission au builder : cohérence vérifiée (branding, seuils capteurs, endpoints, ADRs), aucun bug bloquant (`qa/known-issues.md` vide, projet non démarré).

## 2026-07-01 (soir)

- **[Naming]** L'application s'appelle **Viim** (« la vie » en mooré) — décision de Guy. Règle de marque : YAMSTACK TECHNOLOGIE visible uniquement en pied de l'onglet Assistance + mentions légales (`design/branding-vocabulaire.md`).
- **[Design]** Maquettes v2 (`design/maquettes-ecrans.html`) : écran d'inscription avec véhicule adaptatif et illustration (modèle BNA), onglets alignés (icônes SVG), vocabulaire et typographie français soignés, carte MapKit natif.
- **[Specs]** Nouveau `features/inscription-onboarding.md` (adaptation de l'app au moyen de déplacement) ; `data-models.md` (illustration/photo véhicule), `api-endpoints.md`, `onglet-1-accueil.md` (carte véhicule suivi) réalignés ; notification collision au vouvoiement.
- **[Blueprints]** Création de `blueprints/` : ordre d'exécution, blueprint iOS, blueprint backend Hetzner/Coolify — point d'entrée du builder (Codex).

## 2026-07-01

- **[Design]** Maquettes HTML des 6 écrans clés dans `design/maquettes-ecrans.html` + propositions de nom (LAAFI SIRA / SIRA / BURKINDI) — remplacées le soir même par la décision **Viim**.
- **[Init]** Création de la structure documentaire complète (architecture, features, tracking, qa, decisions) par Claude (Architecte/QA).
- **[Init]** Rédaction des 4 ADRs fondateurs : iOS-first, WhatsApp comme canal d'alerte primaire, Keychain pour données médicales, filtrage capteurs (low-pass + confirmation GPS).
- **[Init]** Spécifications features rédigées à partir du Cahier des Charges v2.0 et des captures d'écran de référence BNA (Banque Nationale Assurances).
- **[Init]** Plan de test MVP avec métriques cibles définies dans `qa/test-plan.md`.
