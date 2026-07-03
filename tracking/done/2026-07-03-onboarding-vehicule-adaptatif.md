# Onboarding véhicule adaptatif — 2026-07-03

- Tâche : parcours d'inscription 3 étapes avec véhicule adaptatif.
- Référence : `features/inscription-onboarding.md`, `blueprints/01-ios-app.md`.
- Implémentation iOS :
  - `OnboardingView` SwiftUI avec étapes identité, véhicule et sécurité.
  - `OnboardingStore` pour profil local hors ligne avec `synced=false`.
  - Contact d'urgence optionnel stocké dans le Keychain uniquement.
  - `VehicleType` enrichi pour les libellés localisés, icônes, couleurs et paramètres capteurs.
- Règles respectées :
  - Nom visible : Viim.
  - Chaînes utilisateur dans `Localizable.strings`.
  - Vouvoiement et typographie française.
  - Données sensibles hors UserDefaults et non loggées.
- Vérifications :
  - `xcodebuild -project ios/Viim.xcodeproj -scheme Viim -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` : OK.
  - `xcodebuild -project ios/Viim.xcodeproj -scheme Viim -destination 'id=E21236A8-1735-5EB6-9A8D-E41C165B962E' -allowProvisioningUpdates -allowProvisioningDeviceRegistration DEVELOPMENT_TEAM=MJJ6A56JHS CODE_SIGN_STYLE=Automatic build` : OK.
  - Installation iPhone réel via `xcrun devicectl device install app` : OK.
  - Lancement iPhone réel de `com.yamstack.viim` : OK.
