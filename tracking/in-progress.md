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

Format d'entrée :

```
## [Nom de la tâche]
- Démarré le : YYYY-MM-DD
- Par : [builder]
- Référence : [lien vers features/ ou architecture/]
- Notes d'avancement : …
```
