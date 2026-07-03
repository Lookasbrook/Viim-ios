# Visuel d'app Viim — 2026-07-03

- Tâche : ajouter un premier visuel système pour l'app.
- Référence : `design/branding-vocabulaire.md`.
- Implémentation iOS :
  - Création de `ios/Viim/Resources/Assets.xcassets/AppIcon.appiconset`.
  - Ajout d'une icône Viim sur fond navy, point or et route stylisée.
  - Génération des tailles iPhone requises : 20, 29, 40 et 60 pt en @2x/@3x, plus 1024 marketing.
  - Configuration Xcode : `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`.
- Règles respectées :
  - Nom visible : Viim.
  - Aucune mention YAMSTACK dans le visuel système.
  - Couleurs conformes à la charte : navy, bleu, vert et or.
- Vérifications :
  - Dimensions PNG vérifiées avec `sips -g pixelWidth -g pixelHeight`.
  - `xcodebuild -quiet -project ios/Viim.xcodeproj -scheme Viim -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` : OK.
  - `xcodebuild -quiet -project ios/Viim.xcodeproj -scheme Viim -destination 'id=E21236A8-1735-5EB6-9A8D-E41C165B962E' -allowProvisioningUpdates -allowProvisioningDeviceRegistration DEVELOPMENT_TEAM=MJJ6A56JHS CODE_SIGN_STYLE=Automatic build` : OK.
  - Installation iPhone réel via `xcrun devicectl device install app` : OK.
  - Lancement iPhone réel de `com.yamstack.viim` : OK.
