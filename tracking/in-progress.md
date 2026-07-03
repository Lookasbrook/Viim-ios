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
  - Accès VPS/Coolify confirmé par l'agent infrastructure : VPS `178.105.115.6`, Coolify joignable, PostgreSQL `g1gh08f3k842vrnjy4lxmoi8` sain.
  - Blocage source Coolify résolu : le repo GitHub `Lookasbrook/Viim-ios` n'est plus vide ; le monorepo local a été publié sur `main`, commit `253ee3a`.
  - Blocages restants côté déploiement : DNS `api.burktech-ia.com` en `NXDOMAIN`, secrets `NEWAGENT_URL` et `NEWAGENT_TOKEN` non disponibles/configurés, Uptime Robot non configuré.

Format d'entrée :

```
## [Nom de la tâche]
- Démarré le : YYYY-MM-DD
- Par : [builder]
- Référence : [lien vers features/ ou architecture/]
- Notes d'avancement : …
```
