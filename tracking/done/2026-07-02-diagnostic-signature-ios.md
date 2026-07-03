# Diagnostic signature iOS — 2026-07-02

- Tâche : isoler la cause de l'échec du build iPhone réel.
- Référence : Phase 0, DoD iPhone réel.
- Résultat :
  - iPhone détecté : `iPhone de Guy` (`E21236A8-1735-5EB6-9A8D-E41C165B962E`).
  - Équipe Apple détectée : `MJJ6A56JHS` (`YELIM SOLUTIONS`).
  - Certificats locaux valides : `Apple Development: Guy Kabore` et `Apple Distribution: YELIM SOLUTIONS`.
  - Build iPhone réel OK avec un fichier d'entitlements vide temporaire.
  - Build iPhone réel KO avec `ios/Viim/Resources/Viim.entitlements`, car le profil local `iOS Team Provisioning Profile: *` ne contient pas Push Notifications / `aps-environment`.
  - Aucun profil local Push pour `com.yamstack.viim`; les profils Push disponibles ciblent `com.nabtrack.Nabtrack`.
  - `xcodebuild -allowProvisioningUpdates` ne peut pas corriger automatiquement le profil, car Xcode CLI signale `No Accounts: Add a new account in Accounts settings`.
- Suite :
  - `xcodebuild -allowProvisioningUpdates` a ensuite créé/téléchargé `iOS Team Provisioning Profile: com.yamstack.viim`.
  - Le profil contient `aps-environment` et cible `MJJ6A56JHS.com.yamstack.viim`.
  - Le build iPhone réel avec Push activé réussit.
  - Un défaut de packaging a été corrigé dans `ios/Viim/Resources/Info.plist` pour ajouter `CFBundleIdentifier` et les clés bundle standard.
  - Installation et lancement de `com.yamstack.viim` confirmés sur l'iPhone de Guy.
- Statut : résolu pour la signature/build iPhone réel.
