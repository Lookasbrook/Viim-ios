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
  - Blocage restant côté déploiement : Uptime Robot non configuré. Tentative Codex : aucune variable `UPTIMEROBOT`/`UPTIME_ROBOT`, aucune CLI `uptimerobot`, aucune configuration locale exploitable trouvée ; endpoint prêt pour monitor HTTPS GET toutes les 5 minutes.

Format d'entrée :

```
## [Nom de la tâche]
- Démarré le : YYYY-MM-DD
- Par : [builder]
- Référence : [lien vers features/ ou architecture/]
- Notes d'avancement : …
```
