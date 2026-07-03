# Bugs connus

Statuts : 🔴 Bloquant · 🟠 Majeur · 🟡 Mineur · ✅ Résolu (avec date et lien vers le fix)

| ID | Date | Statut | Description | Composant | Résolution |
|---|---|---|---|---|---|
| P0-001 | 2026-07-02 | ✅ Résolu | Build iPhone réel impossible avec les entitlements P0 : les identités Apple sont bien présentes (`Apple Development: Guy Kabore`, équipe `MJJ6A56JHS`) et un build diagnostic iPhone réussit avec un fichier d'entitlements vide, mais le seul profil utilisable pour `com.yamstack.viim` était `iOS Team Provisioning Profile: *`, qui ne contenait pas Push Notifications / `aps-environment`. | iOS / signature | Résolu le 2026-07-02 : `xcodebuild -allowProvisioningUpdates` a créé/téléchargé `iOS Team Provisioning Profile: com.yamstack.viim` avec `aps-environment`. Build iPhone réel OK avec Push activé. |
| P0-004 | 2026-07-02 | ✅ Résolu | Installation iPhone échouée après build réussi : `Viim.app` n'était pas reconnu comme bundle valide car `Info.plist` ne contenait pas `CFBundleIdentifier`. | iOS / packaging | Résolu le 2026-07-02 : ajout des clés bundle standard dans `ios/Viim/Resources/Info.plist` (`CFBundleIdentifier`, `CFBundleExecutable`, versions, type `APPL`). Installation et lancement iPhone OK. |
| P0-005 | 2026-07-02 | ✅ Résolu | Coolify ne pouvait pas déployer Viim car le repo GitHub `Lookasbrook/Viim-ios` était vide (`size: 0`) et ne contenait pas `backend/Dockerfile`. | Repo / déploiement | Résolu le 2026-07-02 : monorepo publié sur `main`, commit `253ee3a`, avec `ios/`, `backend/`, `backend/Dockerfile` et `backend/package-lock.json`. |
| P0-002 | 2026-07-02 | 🔴 Bloquant | `https://api.burktech-ia.com/health` ne résout pas DNS. | Backend / DNS | Créer ou corriger l'enregistrement DNS `api.burktech-ia.com` vers le VPS Hetzner CX33. |
| P0-003 | 2026-07-02 | ✅ Résolu | Accès Coolify/VPS non confirmé depuis la session Codex initiale. | VPS / Coolify | Résolu côté agent infrastructure le 2026-07-02 : VPS `178.105.115.6`, Coolify joignable sur `http://178.105.115.6:8000/login`, PostgreSQL Coolify existant `g1gh08f3k842vrnjy4lxmoi8` en `running:healthy`. |

Règle : tout bug 🔴 bloque le passage au testeur externe suivant (cf. prérequis du test-plan).
