# Installation iPhone réel — 2026-07-02

- Tâche : valider le DoD iOS Phase 0 sur iPhone réel.
- Appareil : `iPhone de Guy` (`E21236A8-1735-5EB6-9A8D-E41C165B962E`).
- Bundle : `com.yamstack.viim`.
- Profil : `iOS Team Provisioning Profile: com.yamstack.viim` (`bfcb5092-d1cc-4d49-96e2-6da8872ca581`).
- Résultat :
  - Build iPhone réel OK avec Push Notifications / `aps-environment`.
  - Installation via `xcrun devicectl device install app` OK.
  - Lancement via `xcrun devicectl device process launch` OK.
- Correctif associé : ajout des clés bundle standard dans `ios/Viim/Resources/Info.plist`.
