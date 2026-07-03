# LocationService background GPS — 2026-07-03

- Tâche : GPS arrière-plan et détection automatique début/fin de trajet.
- Référence : `blueprints/01-ios-app.md`, `architecture/sensor-algorithms.md`, `qa/test-plan.md`.
- Implémentation iOS :
  - `LocationService` observable avec autorisation localisation, `allowsBackgroundLocationUpdates`, `pausesLocationUpdatesAutomatically=false`, indicateur arrière-plan et activité adaptée au véhicule.
  - Précision GPS 5 m par défaut, 20 m en mode économie.
  - Détection début : vitesse GPS > 10 km/h soutenue pendant 30 s.
  - Détection fin : arrêt prolongé sous 3 km/h pendant 5 min.
  - Échantillons GPS conservés en mémoire pour le trajet actif, distance approximative, dernier trajet complété.
  - Lancement automatique après onboarding, avec type de véhicule issu du profil.
  - État de suivi visible dans l'onglet Accueil.
- Vérifications :
  - `xcodebuild -quiet -project ios/Viim.xcodeproj -scheme Viim -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` : OK.
  - `xcodebuild -quiet -project ios/Viim.xcodeproj -scheme Viim -destination 'id=E21236A8-1735-5EB6-9A8D-E41C165B962E' -allowProvisioningUpdates -allowProvisioningDeviceRegistration DEVELOPMENT_TEAM=MJJ6A56JHS CODE_SIGN_STYLE=Automatic build` : OK.
  - Installation iPhone réel via `xcrun devicectl device install app` : OK.
  - Lancement iPhone réel de `com.yamstack.viim` : OK.
  - `npm run check` backend : OK.
- Limite : le scénario terrain S1 complet (20 min écran verrouillé) reste à exécuter avant testeurs externes.
