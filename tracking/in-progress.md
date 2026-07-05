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

## Phase 3 — Correction test WhatsApp Assistance
- Démarré le : 2026-07-04
- Terminé le : 2026-07-04
- Par : Codex builder
- Référence : [features/onglet-3-assistance.md](../features/onglet-3-assistance.md), [architecture/api-endpoints.md](../architecture/api-endpoints.md), [qa/known-issues.md](../qa/known-issues.md)
- Notes d'avancement :
  - Objectif : investiguer pourquoi le bouton `Envoyer un test` ne fonctionne pas sur l'iPhone après déploiement des routes Assistance.
  - Contraintes : ne pas envoyer de WhatsApp réel vers un numéro non consenti ; ne pas exposer de token NEwAGENT ; garder les contacts d'urgence Keychain-only.
  - Cause confirmée : mismatch de format téléphone. L'onboarding pouvait stocker `+226 70 00 00 00` ou `70000000`, alors que le backend exige `+226XXXXXXXX`.
  - Implémenté : normalisation locale `BurkinaPhoneNumber`, stockage Keychain canonique, validation onboarding/formulaire Assistance et garde avant appel API.
  - Tests : `xcodebuild test` simulateur OK, build signé iPhone réel OK, installation et lancement de `com.yamstack.viim` confirmés sur l'iPhone de Guy.

## Phase 3 — Déblocage actions Assistance sur iPhone
- Démarré le : 2026-07-04
- Terminé le : 2026-07-04
- Par : Codex builder
- Référence : [features/onglet-3-assistance.md](../features/onglet-3-assistance.md), [architecture/api-endpoints.md](../architecture/api-endpoints.md), [qa/known-issues.md](../qa/known-issues.md)
- Notes d'avancement :
  - Objectif : corriger `Voir ma localisation` qui ne donne pas de position et `Envoyer un test WhatsApp` grisé sur l'iPhone.
  - Contraintes : garder MapKit natif, contacts Keychain-only, aucun envoi WhatsApp réel sans contact consenti.
  - Cause confirmée : l'écran localisation dépendait d'un `latestLocation` préexistant sans demander une position ponctuelle ; le bouton test était désactivé quand aucun contact valide n'était chargé.
  - Implémenté : demande GPS ponctuelle foreground, états localisés de recherche/permission/refus, bouton `Actualiser ma position`, action `Configurer un contact` au lieu d'un bouton test grisé.
  - Tests : `xcodebuild test` simulateur OK, build signé iPhone réel OK, installation et lancement de `com.yamstack.viim` confirmés sur l'iPhone de Guy.

## Investigation — WhatsApp et trajets absents après roulage Québec
- Démarré le : 2026-07-04
- Par : Codex builder
- Référence : [features/onglet-1-accueil.md](../features/onglet-1-accueil.md), [features/onglet-3-assistance.md](../features/onglet-3-assistance.md), [architecture/sensor-algorithms.md](../architecture/sensor-algorithms.md), [architecture/api-endpoints.md](../architecture/api-endpoints.md)
- Notes d'avancement :
  - Objectif : investiguer pourquoi l'alerte WhatsApp ne fonctionne pas et pourquoi aucun trajet du jour n'apparaît après plusieurs trajets réels au Québec.
  - Question produit : vérifier si la configuration Burkina bloque les tests au Québec ou si le problème vient du pipeline iOS/backend.
  - Contraintes : ne pas exposer les secrets NEwAGENT, ne pas envoyer de WhatsApp réel vers un numéro non consenti, ne pas contourner la collecte Keychain/CoreData.
  - 2026-07-04 : base CoreData copiée depuis l'iPhone réel ; `ZTRIP=0`, `ZTRIPEVENT=0`, `ZDAILYSUMMARY=0`, donc les trajets du jour n'ont pas été persistés.
  - 2026-07-04 : console iPhone au lancement : `authorizedAlways`, wakeups passifs démarrés, `vehicleType=voiture`, puis `location.passiveWakeup.ignored` et `motion.phase stationary`; aucun `trip.begin`, `trip.end` ou `trip.persisted`.
  - 2026-07-04 : `/health` public API OK avec `whatsapp:"ok"`, mais un test API avec numéro Québec fictif `+1` retourne `HTTP 422 {"error":"invalid_contact"}`.
  - Conclusion provisoire : le Québec bloque les tests WhatsApp si le contact n'est pas en `+226XXXXXXXX`; il ne doit pas bloquer les trajets. Le défaut trajets est dans la détection/promotion GPS/finalisation/persistance automatique.
  - 2026-07-04 : inspection complète du conteneur app iPhone : `Documents` vide ; pas de fichier de trajets hors `Library/Application Support/Viim.sqlite`; les trajets passés non collectés ne sont pas reconstructibles depuis l'app.
  - 2026-07-04 : correctif iOS implémenté et installé sur iPhone réel : fenêtre GPS de confirmation sur réveil passif, départ confirmé à 8 km/h pendant 15 s, persistance CoreData des snapshots de trajet actif, mise à jour du même enregistrement à la fin.
  - 2026-07-04 : tests ajoutés pour démarrage GPS simulé, snapshot actif inclus dans le résumé du jour, et mise à jour du snapshot par trajet terminé ; `xcodebuild test` simulateur OK, build signé iPhone réel OK, installation OK.


Format d'entrée :

```
## [Nom de la tâche]
- Démarré le : YYYY-MM-DD
- Par : [builder]
- Référence : [lien vers features/ ou architecture/]
- Notes d'avancement : …
```
