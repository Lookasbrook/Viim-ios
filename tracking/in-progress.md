# En cours

## Phase 0 — Vérification des prérequis externes
- Démarré le : 2026-07-01
- Par : Codex builder
- Couche : monorepo `viim` (`ios/` + `backend/`)
- Référence : [blueprints/00-ordre-execution.md](../blueprints/00-ordre-execution.md), [blueprints/01-ios-app.md](../blueprints/01-ios-app.md), [blueprints/02-backend-coolify.md](../blueprints/02-backend-coolify.md)
- Notes d'avancement :
  - Repo GitHub `https://github.com/Lookasbrook/Viim-ios.git` cloné dans `Viim-ios/` ; le dépôt distant est vide.
  - Xcode disponible localement : `xcodebuild -version` OK.
  - Pré requis Apple confirmé : les certificats de signature existent hors sandbox (`Apple Development: Guy Kabore`, `Apple Distribution: YELIM SOLUTIONS`), l'équipe active est `MJJ6A56JHS`, et `xcodebuild` voit désormais le compte Apple Developer.
  - Blocage : `https://api.burktech-ia.com/health` ne résout pas DNS, même hors sandbox (`curl -I` → `Could not resolve host`). Le DNS `api.burktech-ia.com` n'est pas confirmé.
  - Blocage : aucun secret ou endpoint NEwAGENT-IA présent dans l'environnement local ; à obtenir auprès de Guy, sans l'écrire dans le repo.
  - Blocage : accès VPS Hetzner/Coolify non confirmé depuis cette session.
  - Repo local préparé dans `Viim-ios/` : documentation copiée, structure `ios/` + `backend/` créée.
  - iOS : projet Xcode `ios/Viim.xcodeproj`, app SwiftUI 4 onglets, localisation française, background modes, entitlements Push, Team ID `MJJ6A56JHS`.
  - Backend : squelette Node/Express dans `backend/`, endpoint `/health`, migration PostgreSQL initiale, Dockerfile Coolify.
  - Vérifié : `xcodebuild -list` OK ; build simulateur iOS OK ; `npm install` OK ; `npm run check` OK ; `/health` local OK hors sandbox.
  - Diagnostic signature résolu : `xcodebuild -allowProvisioningUpdates` a créé/téléchargé `iOS Team Provisioning Profile: com.yamstack.viim` avec `aps-environment`. Build iPhone réel OK avec Push activé.
  - Packaging iOS corrigé : ajout des clés bundle standard dans `ios/Viim/Resources/Info.plist`; installation et lancement de `com.yamstack.viim` confirmés sur l'iPhone de Guy.
  - Accès VPS/Coolify confirmé par l'agent infrastructure : VPS `178.105.115.6`, Coolify joignable, PostgreSQL initial `g1gh08f3k842vrnjy4lxmoi8` sain.
  - Blocage source Coolify résolu : le repo GitHub `Lookasbrook/Viim-ios` n'est plus vide ; le monorepo local a été publié sur `main`, commit `4dd4ca3`.
  - Déploiement Coolify Viim confirmé par l'agent infrastructure : app `Viim`, UUID `blqn1beg8ae0dvddmqio6rth`, commit déployé `4dd4ca395cdf7e004c4fae22156f523add79e24a`, root `/backend`, Dockerfile `/Dockerfile`, port `3000`, domaine `https://api.burktech-ia.com`.
  - PostgreSQL Viim créé dans Coolify : DB UUID `v46pxb68fon91lz66pdyomot`; migration initiale appliquée (`users`, `trips`, `trip_events`, `daily_summaries`).
  - Vérification runtime initiale : `curl -k --resolve api.burktech-ia.com:443:178.105.115.6 https://api.burktech-ia.com/health` retournait `{"status":"degraded","api":"ok","db":"ok","whatsapp":"not_configured","version":"0.1.0"}` avant configuration du token NEwAGENT.
  - DNS API résolu côté authoritative : `dig @ns1.dns-parking.com +short api.burktech-ia.com A` retourne `178.105.115.6`. Certains résolveurs locaux peuvent garder temporairement un cache `NXDOMAIN`.
  - Endpoint NEwAGENT configuré côté runtime : `has_NEWAGENT_URL=true`, `has_NEWAGENT_TOKEN=true`; token généré/configuré dans Coolify sans être affiché ni écrit dans le repo.
  - Health API public validé : `curl -i https://api.burktech-ia.com/health` retourne HTTP 200 avec `{"status":"ok","api":"ok","db":"ok","whatsapp":"ok","version":"0.1.0"}`.
  - Uptime Robot non configuré. Tentative Codex : aucune variable `UPTIMEROBOT`/`UPTIME_ROBOT`, aucune CLI `uptimerobot`, aucune configuration locale exploitable trouvée ; endpoint prêt pour monitor HTTPS GET toutes les 5 minutes.
  - Décision PO du 2026-07-03 : reporter Uptime Robot et continuer l'exécution. Ce report ne doit pas ouvrir l'app à des testeurs externes tant que le monitoring n'est pas actif.

## Phase 1 — Onboarding véhicule adaptatif
- Démarré le : 2026-07-03
- Terminé le : 2026-07-03
- Par : Codex builder
- Référence : [features/inscription-onboarding.md](../features/inscription-onboarding.md), [blueprints/01-ios-app.md](../blueprints/01-ios-app.md)
- Notes d'avancement :
  - Objectif : afficher au premier lancement un parcours d'inscription 3 étapes (identité, moyen de déplacement, sécurité) avec véhicule adaptatif.
  - Implémenté : `OnboardingStore`, stockage profil local hors ligne avec `synced=false`, contact d'urgence Keychain-only, écran SwiftUI 3 étapes et sélection véhicule adaptative.
  - Vérifié : build simulateur OK, build signé iPhone réel OK, installation et lancement de `com.yamstack.viim` confirmés sur l'iPhone de Guy.

## Phase 1 — LocationService background GPS
- Démarré le : 2026-07-03
- Terminé le : 2026-07-03
- Par : Codex builder
- Référence : [blueprints/01-ios-app.md](../blueprints/01-ios-app.md), [architecture/sensor-algorithms.md](../architecture/sensor-algorithms.md), [qa/test-plan.md](../qa/test-plan.md)
- Notes d'avancement :
  - Objectif : activer le GPS arrière-plan et la détection automatique début/fin de trajet.
  - Règle cible : début si vitesse GPS > 10 km/h pendant 30 s ; fin si arrêt prolongé > 5 min.
  - Implémenté : autorisation When In Use puis Always, `allowsBackgroundLocationUpdates`, indicateur arrière-plan, précision 5 m par défaut / 20 m en mode économie, activité adaptée au type de véhicule, échantillons GPS et état de trajet observable.
  - Accueil : affichage du véhicule utilisateur et de l'état de détection GPS avec chaînes localisées.
  - Vérifié : build simulateur OK, build signé iPhone réel OK, installation et lancement de `com.yamstack.viim` confirmés sur l'iPhone de Guy.
  - Validation terrain restante : scénario S1 complet (20 min écran verrouillé) à exécuter dans `qa/test-results.md` avant ouverture externe.

## UI — Plein écran et réalignement maquette HTML
- Démarré le : 2026-07-03
- Terminé le : 2026-07-03
- Par : Codex builder
- Référence : [design/maquettes-ecrans.html](../design/maquettes-ecrans.html), [qa/known-issues.md](../qa/known-issues.md)
- Notes d'avancement :
  - Objectif : corriger l'affichage letterboxé sur iPhone et réaligner les premiers écrans SwiftUI sur la maquette HTML.
  - Bugs ciblés : `UI-001` plein écran iOS, `UI-002` écart visuel HTML.
  - Implémenté : `LaunchScreen.storyboard` déclaré dans `Info.plist`, composants visuels partagés, onboarding et Accueil réalignés sur la maquette HTML.
  - Vérifié : build simulateur OK ; captures simulateur avant/après conservées dans `/private/tmp/viim-current-screen.png`, `/private/tmp/viim-after-localized-ui-fix.png` et `/private/tmp/viim-home-final-clean.png`.

## UI — Lisibilité des onglets Conduite, Assistance et Prévention
- Démarré le : 2026-07-03
- Terminé le : 2026-07-03
- Par : Codex builder
- Référence : [qa/known-issues.md](../qa/known-issues.md), [design/maquettes-ecrans.html](../design/maquettes-ecrans.html)
- Notes d'avancement :
  - Objectif : corriger le texte blanc illisible dans les trois onglets restants.
  - Bug ciblé : `UI-003`.
  - Cause : cartes blanches fixes avec textes restés sur les couleurs système `.primary` / `.secondary`, illisibles en mode sombre iPhone.
  - Implémenté : couleurs explicites `ViimColors.text` et `ViimColors.muted` dans `ViimCard`, `StatusRow`, Conduite, Assistance et Prévention.
  - Vérifié : grep sans texte `.secondary` dans les trois onglets, build simulateur OK, build signé iPhone réel OK, installation et lancement OK.

## UI — Visuel d'app Viim
- Démarré le : 2026-07-03
- Terminé le : 2026-07-03
- Par : Codex builder
- Référence : [design/branding-vocabulaire.md](../design/branding-vocabulaire.md)
- Notes d'avancement :
  - Objectif : ajouter un premier visuel système pour l'app, visible sur l'écran d'accueil iPhone.
  - Périmètre : icône d'application Viim dans l'asset catalog, sans mention YAMSTACK dans l'UI.
  - Implémenté : `AppIcon.appiconset` complet avec source 1024 px et déclinaisons iPhone.
  - Vérifié : dimensions PNG OK, build simulateur OK, build signé iPhone réel OK, installation et lancement OK.

## UI — Photos premium des moyens de déplacement
- Démarré le : 2026-07-03
- Terminé le : 2026-07-03
- Par : Codex builder
- Référence : [design/maquettes-ecrans.html](../design/maquettes-ecrans.html), [features/inscription-onboarding.md](../features/inscription-onboarding.md)
- Notes d'avancement :
  - Objectif : afficher de vraies photos réutilisables de moto, voiture et vélo dans l'Accueil pour un rendu plus premium.
  - Périmètre : assets locaux dans `Assets.xcassets`, attribution/licence documentée, aucune dépendance réseau runtime.
  - Implémenté : `VehiclePhotoMoto`, `VehiclePhotoCar`, `VehiclePhotoVelo`, vignette photo responsive dans la carte véhicule de l'Accueil.
  - Supersédé le 2026-07-03 : les photos génériques par type sont retirées au profit du catalogue marque/modèle, pour éviter une image incohérente avec le véhicule saisi.
  - Vérifié : images redimensionnées à 1200 px maximum ; build simulateur OK ; build signé iPhone réel OK ; installation et lancement OK.

## iOS — Indicateur GPS visible après autorisation
- Démarré le : 2026-07-03
- Terminé le : 2026-07-03
- Par : Codex builder
- Référence : [blueprints/01-ios-app.md](../blueprints/01-ios-app.md), [architecture/sensor-algorithms.md](../architecture/sensor-algorithms.md)
- Notes d'avancement :
  - Objectif : empêcher l'affichage persistant de l'indicateur de localisation en haut de l'écran après autorisation.
  - Cause confirmée : `showsBackgroundLocationIndicator=true`, demande automatique `Always` et démarrage immédiat du suivi GPS après onboarding.
  - Implémenté : préparation localisation passive au lancement, demande `When In Use` uniquement, plus d'escalade automatique `Always`, indicateur arrière-plan désactivé.
  - ADR : [2026-07-03-localisation-discrete-ios](../decisions/2026-07-03-localisation-discrete-ios.md).
  - Vérifié : grep sans `requestAlwaysAuthorization` ni `showsBackgroundLocationIndicator=true`; build simulateur OK ; build signé iPhone réel OK ; installation et lancement OK.

## UI — Catalogue véhicule par marque et modèle
- Démarré le : 2026-07-03
- Terminé le : 2026-07-03
- Par : Codex builder
- Référence : [features/inscription-onboarding.md](../features/inscription-onboarding.md), [design/maquettes-ecrans.html](../design/maquettes-ecrans.html)
- Notes d'avancement :
  - Objectif : remplacer les photos génériques par un catalogue modèle-aware, afin que l'Accueil affiche une photo cohérente avec la marque et le modèle saisis.
  - Périmètre : matching local offline, assets open source documentés, tests automatisés de résolution marque/modèle.
  - Implémenté : catalogue local `VehiclePhotoCatalog`, fallback neutre sans photo pour les modèles inconnus, 10 assets modèle-aware.
  - Tests : `ViimTests/VehiclePhotoCatalogTests.swift` couvre Corolla, Hilux, RAV4, Prado, Land Cruiser, Yamaha Crypton/YBR, Bajaj Boxer, TVS Apache, Honda CG125, les variantes de saisie et les cas inconnus.
  - Vérifié : `xcodebuild test` sur iPhone 17 Simulator OK, 5 tests passés ; build simulateur OK ; build signé iPhone réel OK ; installation et lancement OK.

## UI — Réalignement des onglets Conduite, Assistance et Prévention
- Démarré le : 2026-07-03
- Terminé le : 2026-07-03
- Par : Codex builder
- Référence : [design/maquettes-ecrans.html](../design/maquettes-ecrans.html), [qa/known-issues.md](../qa/known-issues.md)
- Notes d'avancement :
  - Objectif : finaliser `UI-002` en rapprochant les trois onglets restants de la maquette HTML.
  - Périmètre : structure visuelle, cartes, hiérarchie, couleurs, chaînes localisées, sans logique métier destructive.
  - Implémenté : onglet Conduite avec héros statistiques, performance, critères et conseil ; Assistance avec héros rouge, soutien temps réel, actions et urgences ; Prévention avec héros vert, zones ONASER, alertes, entretien et défi.
  - Vérifié : build simulateur OK ; grep sans texte français direct dans Swift ; build signé iPhone réel OK ; installation et lancement OK.

## Phase 1 — Données trajets visibles et calibration locale
- Démarré le : 2026-07-03
- Terminé le : 2026-07-03
- Par : Codex builder
- Référence : [architecture/data-models.md](../architecture/data-models.md), [architecture/sensor-algorithms.md](../architecture/sensor-algorithms.md), [features/onglet-1-accueil.md](../features/onglet-1-accueil.md)
- Notes d'avancement :
  - Objectif : résoudre l'absence de données visibles sur iPhone après autorisation de localisation.
  - Cause confirmée : l'autorisation position ne démarre plus le suivi GPS continu par défaut, `LocationService` garde les trajets terminés en mémoire uniquement, et aucune couche `TripManager`/CoreData n'alimente l'Accueil ou Votre conduite.
  - Périmètre : persistance locale offline-first des trajets terminés, compteur de calibration local, résumé du jour et contrôle explicite de suivi.
  - Implémenté : modèle CoreData programmatique `Trip`/`TripEvent`/`DailySummary`, `TripStore`, `TripManager`, résumé du jour dynamique, trajets récents persistés et compteur de calibration local. Le contrôle manuel initial a été supersédé par la détection automatique `CoreMotion`.
  - ADR : [2026-07-03-coredata-modele-programmatique](../decisions/2026-07-03-coredata-modele-programmatique.md).
  - Tests : `xcodebuild test` simulateur OK, build signé iPhone réel OK, installation et lancement de `com.yamstack.viim` confirmés sur l'iPhone de Guy.

## Phase 1 — Détection automatique sans bouton de suivi
- Démarré le : 2026-07-03
- Terminé le : 2026-07-03
- Par : Codex builder
- Référence : [architecture/sensor-algorithms.md](../architecture/sensor-algorithms.md), [features/onglet-1-accueil.md](../features/onglet-1-accueil.md), [decisions/2026-07-03-localisation-discrete-ios.md](../decisions/2026-07-03-localisation-discrete-ios.md)
- Notes d'avancement :
  - Objectif : réduire la friction en supprimant le bouton manuel de démarrage du suivi.
  - Décision produit : Viim doit détecter le mouvement du téléphone et lancer la collecte pertinente automatiquement, tout en évitant le GPS permanent quand l'utilisateur est immobile.
  - Périmètre : amorce `CoreMotion` basse friction, démarrage automatique du GPS uniquement quand un déplacement probable est détecté, et Accueil centré sur les données des trajets d'aujourd'hui.
  - Implémenté : `MotionActivityService`, démarrage automatique de `LocationService` sur mouvement probable, arrêt du GPS quand le téléphone est immobile sans trajet actif, suppression du bouton manuel et liste Accueil filtrée sur les trajets d'aujourd'hui.
  - ADR : [2026-07-03-detection-mouvement-sans-bouton](../decisions/2026-07-03-detection-mouvement-sans-bouton.md).
  - Tests : `MotionActivityServiceTests` et `TripStoreTests` mis à jour ; `xcodebuild test` simulateur OK ; build signé iPhone réel OK ; installation et lancement de `com.yamstack.viim` confirmés sur l'iPhone de Guy.

## Phase 1 — Parcours du jour absent malgré GPS autorisé
- Démarré le : 2026-07-03
- Terminé le : 2026-07-03
- Par : Codex builder
- Référence : [features/onglet-1-accueil.md](../features/onglet-1-accueil.md), [architecture/sensor-algorithms.md](../architecture/sensor-algorithms.md), [qa/known-issues.md](../qa/known-issues.md)
- Notes d'avancement :
  - Objectif : faire apparaître le parcours d'aujourd'hui dans l'Accueil après autorisation GPS.
  - Symptôme : Guy ne voit aucune donnée de trajet du jour sur iPhone.
  - Investigation demandée : lire les logs iPhone et trouver où le pipeline mouvement → GPS → trajet terminé → CoreData s'arrête.
  - Cause confirmée : l'iPhone a bien `authorizedAlways`, mais la base locale de l'appareil contenait `0` ligne dans `ZTRIP`, `ZTRIPEVENT` et `ZDAILYSUMMARY`; aucun trajet n'avait donc été persisté à afficher.
  - Cause technique : Viim dépendait surtout de l'app active et de `CoreMotion` pour lancer le GPS continu. Un départ en arrière-plan pouvait ne pas promouvoir la collecte, et un trajet actif pouvait rester non persisté si iOS cessait d'envoyer des points basse vitesse à l'arrêt.
  - Bug secondaire trouvé sur logs iPhone : le réveil passif envoyait un point initial immobile et lançait le GPS continu, créant une boucle `start active` → `stationary` → `stop`.
  - Implémenté : `ViimDiagnostics`, réveils passifs `startMonitoringSignificantLocationChanges`, promotion vers GPS continu seulement si vitesse/déplacement réel, finalisation de trajet actif après immobilité et affichage `Réveil automatique actif` dans l'Accueil.
  - Vérifié : `xcodebuild test` simulateur OK ; build signé iPhone réel OK ; installation OK ; logs iPhone finaux : `location.authorization state=authorizedAlways`, `location.passiveWakeups.start`, `location.passiveWakeup.ignored count=1`, `motion.phase stationary`, sans `location.start active` à l'arrêt.

## Phase 3 — Assistance fonctionnelle et routes WhatsApp
- Démarré le : 2026-07-04
- Terminé le : 2026-07-04
- Par : Codex builder
- Référence : [features/onglet-3-assistance.md](../features/onglet-3-assistance.md), [architecture/api-endpoints.md](../architecture/api-endpoints.md), [qa/known-issues.md](../qa/known-issues.md)
- Notes d'avancement :
  - Objectif : résoudre `ASSIST-001` et démarrer `ASSIST-002` en branchant les actions visibles de l'onglet Assistance et les endpoints backend WhatsApp minimum.
  - Périmètre initial : `/v1/alerts/test`, `/v1/alerts/location-share`, `/v1/alerts/collision`, bouton test WhatsApp, appels `18`/`17`, localisation MapKit, contacts d'urgence Keychain, fiche médicale Keychain.
  - Contraintes : aucun token NEwAGENT dans le repo, aucune donnée médicale/contacts hors Keychain côté iOS, payload médical envoyé uniquement sur collision confirmée.
  - Implémenté backend : routes `/v1/alerts/test`, `/v1/alerts/location-share`, `/v1/alerts/collision`, validation téléphone `+226`, validation localisation, client NEwAGENT POST sans log de token.
  - Implémenté iOS : Assistance sans actions vides, appels `18`/`17`, écran MapKit, partage de position, gestion contact d'urgence Keychain, fiche médicale Keychain, bouton test WhatsApp, statut Alerte famille dans l'Accueil.
  - Implémenté Conduite : le bouton `Voir mon style de conduite` ouvre un écran de portrait détaillé.
  - Tests : `npm test` OK hors sandbox, `npm run check` OK, `xcodebuild test` simulateur OK, build signé iPhone réel OK, installation et lancement sur l'iPhone de Guy OK.
  - Reste : vérifier les routes après déploiement public Coolify et effectuer un vrai test WhatsApp avec un contact consenti ; cascade 3 contacts et fallback SMS consignés dans `ASSIST-003`.

## Phase 3 — Diagnostic GPS et WhatsApp
- Démarré le : 2026-07-05
- Terminé le : 2026-07-05
- Par : Codex builder
- Référence : [blueprints/2026-07-05-diagnostic-gps-whatsapp.md](../blueprints/2026-07-05-diagnostic-gps-whatsapp.md), [features/onglet-3-assistance.md](../features/onglet-3-assistance.md)
- Notes d'avancement :
  - Objectif : corriger le chemin court du diagnostic terrain, en priorité la validation du contact WhatsApp, les messages d'erreur Assistance et la localisation ponctuelle.
  - Périmètre initial : normalisation téléphone Burkina côté iOS, mapping des erreurs API, demande de position fraîche dans Assistance et mise à jour QA.
  - Implémenté : normalisation `+226XXXXXXXX`, blocage des contacts invalides, erreurs API actionnables, localisation ponctuelle Assistance, bouton explicite d'activation arrière-plan et logs backend WhatsApp scrubbed.
  - Vérifié : `npm test --prefix backend` OK, `npm run check --prefix backend` OK, `xcodebuild test` iPhone 17 Pro Simulator OK.

## Phase A bis — Trajets réels toujours perdus malgré Phase A (DATA-003)
- Démarré le : 2026-07-09
- Par : Claude (session directe, PO présent)
- Référence : [blueprints/2026-07-08-fiabilite-pro-internationalisation.md](../blueprints/2026-07-08-fiabilite-pro-internationalisation.md), [qa/known-issues.md](../qa/known-issues.md) DATA-003
- Notes d'avancement :
  - Constat : deux trajets réels du 2026-07-09 absents de CoreData avec `activeDraftCount=0` — la détection n'a jamais démarré, la Phase A (journal/recorder) ne pouvait donc rien récupérer.
  - Cause 1 corrigée : promotion du réveil arrière-plan impossible à froid (`lastAcceptedLocation` toujours nil après relance + fix cellulaire > 100 m filtré). Nouvelle règle statique testée `LocationService.shouldPromotePassiveWakeup` : promotion systématique sur réveil récent sans référence, promotion sur vitesse GPS ou déplacement réel sinon.
  - Cause 2 corrigée : `allowsBackgroundLocationUpdates` réservé à `Always` → GPS coupé au verrouillage d'écran en WhenInUse, trajet en cours perdu. Désormais actif dès autorisation valide, indicateur système affiché en WhenInUse (obligatoire iOS).
  - Cause 3 corrigée : CoreMotion classe mal les motos (`automotive` rarement levé) et une autorisation Mouvement/Fitness refusée bloquait la phase indéfiniment. Moto : seuls marche/course excluent le départ ; mouvement non classé déclenche pour tous ; refus d'autorisation bascule sur détection GPS pure via `reconcileAutomaticTracking`.
  - Garde-fou ajouté : failsafe d'inactivité dans `LocationService` (arrêt du GPS après 3 min sans trajet actif ni candidat), autonome donc fonctionnel sans CoreMotion ni vue.
  - Câblage headless : `tripRecorder.observe/recoverActiveTrips` et la configuration véhicule déplacés de `RootTabView.task` vers `ViimApp.init` — actifs même quand iOS relance l'app en arrière-plan sans UI.
  - Robustesse distance : scan par ancre dans `distanceAnalysis` (un glitch isolé ne coûte qu'un segment et ne casse plus la continuité), `shouldBeginTripFromCandidateSamples` ne s'annule plus au premier segment invalide, `TripQualityEngine.countSegments` aligné sur le même parcours.
  - Tests : nouveaux XCTest promotion réveil (5 cas), glitch au démarrage, moto/marche/mouvement inconnu ; mise à jour du test distance (ancre).
  - Reste : validation terrain S1 (roulage réel écran verrouillé + app fermée) avant de fermer DATA-003 ; voir blueprint 2026-07-09.

## Validation terrain et WhatsApp production — blueprint 2026-07-09
- Démarré le : 2026-07-10
- Par : Codex builder
- Référence : [blueprints/2026-07-09-validation-terrain-et-suite.md](../blueprints/2026-07-09-validation-terrain-et-suite.md)
- Notes d'avancement :
  - Préflight exécuté : backend `npm test --prefix backend` 13/13 OK hors sandbox, `npm run check --prefix backend` OK, suite iOS simulateur iPhone 17 OS 26.5 `TEST SUCCEEDED`, build signé iPhone réel `BUILD SUCCEEDED`.
  - iPhone de Guy visible via `devicectl` (`E21236A8-1735-5EB6-9A8D-E41C165B962E`), build courant installé et lancé le 2026-07-10 01:33 UTC.
  - Baseline extraite dans `qa/artifacts/s1-20260709-validation-preflight` : `tripCount=6`, `localTripsTodayCount=0`, `activeDraftCount=0`, `activeSampleCount=0`, `diagnosticsLogPresent=true`, dernier trajet le 2026-07-08 23:11:41 UTC.
  - Probe production : `GET https://api.burktech-ia.com/health` HTTP 200 (`status=ok`, DB OK, WhatsApp OK) ; `POST /v1/alerts/test` avec `{}` HTTP 422 `invalid_contact`.
  - Garde-fou blueprint appliqué : S1-A/S1-B/S1-C n'ont pas encore de preuve terrain post-installation, donc DATA-003/GPS-101 restent ouverts et les Phases C/D/E ne doivent pas démarrer.
  - Étape 2 WA-103 reste bloquée côté production tant que le vrai `NEWAGENT_SEND_URL`, la migration Coolify, un contact consenti et la preuve `providerMessageId` en table `alerts` ne sont pas fournis/validés.
  - 2026-07-11 : Guy signale plusieurs trajets encore absents. Extraction `qa/artifacts/s1-20260711-user-reported-missing-trips` confirme `tripCount=6`, `localTripsTodayCount=0`, `activeDraftCount=0`, `activeSampleCount=0`, dernier trajet toujours le 2026-07-08 23:11:41 UTC.
  - Cause racine complémentaire prouvée par logs : réveil arrière-plan et `location.start active` fonctionnent, mais iOS livre parfois seulement un point GPS exploitable toutes les ~5 min ; la fenêtre candidat 120 s + exigence 3 points fait rejeter chaque départ (`trip.begin.candidateRejected samples=1`) avant création du journal.
  - Correctif installé sur l'iPhone de Guy : fenêtre candidat 15 min, acceptation d'un départ sparse avec 2 points précis séparés dans le temps/l'espace, et finalisation inactive seulement si le point tardif est stationnaire. Tests ciblés `LocationServiceTests` OK, suite iOS complète OK, build/install/lancement iPhone OK à 2026-07-12 00:42 UTC.
  - Reste : refaire un trajet terrain avec cette build ; les trajets manqués avant installation ne sont pas reconstructibles car aucun `ActiveTripDraft`/`ActiveTripSample` n'a été créé.

## Phase A ter — App suspendue par iOS pendant les trajets (DATA-003, cause racine amont)
- Démarré le : 2026-07-12
- Par : Claude (session directe, investigation /investigate)
- Référence : [qa/artifacts/s1-20260711-investigation-fresh](../qa/artifacts/s1-20260711-investigation-fresh), [qa/known-issues.md](../qa/known-issues.md) DATA-003
- Notes d'avancement :
  - Preuve de suspension : le failsafe programmé à +180 s a tiré à +301 s (2026-07-11T14:13:24Z), à la seconde exacte d'un réveil localisation — un timer ne peut pas dériver ainsi si le processus tourne. Livraison GPS exactement toutes les 300,0 s (14:18:25 → 14:23:25) = cadence des changements significatifs, pas du GPS continu.
  - Conclusion : iOS suspendait l'app écran verrouillé malgré `startUpdatingLocation` + `authorizedAlways` + `UIBackgroundModes location`. Le correctif « sparse start » du 2026-07-11 traitait le symptôme (démarrage impossible avec 1 point/5 min) mais pas la suspension.
  - Correctif principal : `CLBackgroundActivitySession` (iOS 17+, cible de déploiement 16 → `#available`) créée à chaque `startMonitoring` et invalidée au stop ; logs `location.backgroundSession.start/end` pour vérification terrain.
  - Correctif anti-flapping : preuve de mouvement calculée sur tous les points reçus, y compris trop imprécis pour la route (vitesse ≥ 10 km/h ou déplacement au-delà de la marge d'imprécision). Le failsafe d'inactivité et l'arrêt stationnaire CoreMotion sont différés tant qu'une preuve < 3 min existe (`location.idleFailsafe.deferred`, `motion.stationaryStop.deferred`). Les logs du 2026-07-11 montraient le failsafe et CoreMotion coupant la session en plein trajet probable (23:13:28 stop → 23:13:31 start → 23:13:36 stop).
  - Correctif anti-fusion : plafond dur 30 min dans `shouldFinalizeInactiveTripBeforeIngest` — au-delà de ce silence, le point entrant clôt l'ancien trajet même s'il est rapide (voiture garée puis nouveau départ).
  - Tests : `isMovementEvidence` (vitesse, déplacement imprécis probant, jitter non probant), `shouldDeferIdleStop`, plafond dur anti-fusion.
  - Reste : installer la build sur l'iPhone, rouler S1-A/B/C, vérifier au log `location.backgroundSession.start` présent et absence de cadence 300 s pendant un trajet. Vérifier aussi côté iPhone : Position exacte ON, Actualisation en arrière-plan ON pour Viim, Mode économie d'énergie OFF pendant la validation.
  - Build intermédiaire installé le 2026-07-12 à 02:11 UTC : `0.1.0 (2)`, `sha=cf47617-dirty`, `builtAt=2026-07-12T02:10:36Z`. Extraction de contrôle : `qa/artifacts/s1-20260712-build2-direct/report`.
  - Preuve anti-flapping sur build 2 : `location.backgroundSession.start` à 02:11:51Z, puis CoreMotion `stationary` à 02:12:02Z et `motion.stationaryStop.deferred reason=armingOrMovement`; aucun arrêt GPS immédiat.
  - Capture durable ajoutée : brouillon `candidate` dès le premier sample, promotion `active` avec le même ID, résultat terminal `trip.capture.outcome`, conservation du journal sur `failedRetryable`, reprise retentable et historique non limité à aujourd'hui.
  - Tests : suites ciblées OK, suite iOS complète `TEST SUCCEEDED`, tests Python du rapport 2/2, build physique et migration CoreData `ZPHASE` OK.
  - Candidat final installé et lancé le 2026-07-12 à 02:17 UTC : `0.1.0 (3)`, `sha=cf47617-dirty`, `builtAt=2026-07-12T02:16:01Z`. Extraction directe `qa/artifacts/s1-20260712-build3-direct/report` : identité conforme, 6 trajets historiques conservés, 0 brouillon actif, 0 sample orphelin, 0 session sans résultat terminal. Le build 3 charge l'historique complet dans l'Accueil au lieu de limiter la liste aux trajets du jour.
  - Reste bloquant : exécuter les 10 scénarios terrain du blueprint `2026-07-11-resolution-definitive-trajets.md`. Ne pas fermer DATA-003/GPS-101 avant preuve de trajets réels `trip.persisted` et visibles.

## Installation du build correctif + notes de fiabilité — 2026-07-17
- Démarré le : 2026-07-17
- Par : Claude (session directe)
- Référence : [blueprints/2026-07-14-fiabilite-vehicules-couts-internationalisation.md](../blueprints/2026-07-14-fiabilite-vehicules-couts-internationalisation.md) §14, [qa/known-issues.md](../qa/known-issues.md) DATA-003/DATA-005/GPS-103
- Notes d'avancement :
  - Constat clé : l'iPhone de Guy roulait toujours sur le build 6 (celui qui perd des trajets). Les builds correctifs 7, 8 et 9 étaient signés mais jamais installés (appareil `unavailable` depuis le 2026-07-15).
  - Audit code : tous les correctifs P0 sont présents et cohérents (réveil significatif conservé pendant le suivi standard, journal `candidate` durable dès le premier point, résultat terminal par session, récupération idempotente avec report des candidats vivants, anti-flapping, anti-fusion 30 min, moto tolérante, fallback GPS pur, `CLServiceSession` Always iOS 18, fast-start rafale 3 points/5 s).
  - Tests : suite iOS 123/123 (`TEST SUCCEEDED`), backend 13/13. Particularité : `npm test` global (node --test sans arguments) pend dans cet environnement ; exécuter par fichier.
  - Build `0.1.0 (10)` signé (destination générique iOS, le device étant `busy` en direct), installé via `devicectl`, version confirmée sur l'appareil.
  - Lancement à distance impossible : 6 tentatives `CoreDeviceError 4000` / `NWError 60` (tunnel developer disk image), alors que install/info fonctionnent. Premier lancement à faire par Guy.
  - Chaîne UI corrigée : `metric.reason.fuelEstimated.detail` n'affirme plus que le style de conduite entre dans le coût (la formule v4 l'exclut).
  - Notes de fiabilité /10 par donnée ajoutées à `data-reliability.md` (section datée 2026-07-17).
  - Reste : premier lancement manuel, 3 trajets terrain P0 (ouverte→verrouillé ; verrouillé départ ; arrêt+finalisation), extraction `tools/qa/s1_trip_report.py --device` après chaque trajet, vérification indicateur absent en veille 10 min. Fermer DATA-003/DATA-005/GPS-103 seulement sur ces preuves.

## Incident — sessions d'agents concurrentes sur le même dépôt (2026-07-17 soir)
- Constaté par : Claude (session directe), pendant le travail UI
- Faits : plusieurs processus Codex actifs sur la machine pendant la session Claude. Des fichiers de test ont été créés/modifiés à 21:14–21:19 (`TripRecorderTests.swift`, `LocationServiceTests.swift`, `ActiveTripJournalTests.swift`) et le `project.pbxproj` à 21:40. Vers 22:00–22:10, les sources `ios/Viim/**` sont revenues à un état antérieur (15 juillet) alors que les tests récents sont restés — la cible de tests ne compilait plus (`receivedAt`, `shouldFinalizeDespiteMotionMovement` manquants).
- Impact évité : le build 10 installé sur l'iPhone avait été compilé avant la régression et contient la version riche. Un build 11 compilé depuis l'arbre régressé aurait annulé des correctifs de capture.
- Réparation : restauration complète depuis la lecture de session (LocationService avec `receivedAt`/durée observée/`shouldFinalizeDespiteMotionMovement`, coordinateur `gpsOverrideMotion` dans ViimApp), double chronologie dans `segmentDistanceMeters`, conservation des échantillons rejetés pour audit dans `finalizeTrip`.
- Recommandation PO : ne jamais faire tourner deux agents (Claude + Codex) en écriture sur le même clone en même temps ; utiliser des branches ou des worktrees séparés.

Format d'entrée :

```
## [Nom de la tâche]
- Démarré le : YYYY-MM-DD
- Par : [builder]
- Référence : [lien vers features/ ou architecture/]
- Notes d'avancement : …
```
