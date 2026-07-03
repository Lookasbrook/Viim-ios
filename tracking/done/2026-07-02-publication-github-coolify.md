# Publication GitHub pour Coolify — 2026-07-02

- Tâche : débloquer l'agent VPS/Coolify qui ne pouvait pas déployer Viim car le dépôt GitHub était vide.
- Repo : `https://github.com/Lookasbrook/Viim-ios.git`
- Branche : `main`
- Commit publié : `253ee3a`
- Contenu publié :
  - `backend/` avec `Dockerfile`, `package.json`, `package-lock.json`, endpoint `/health`.
  - `ios/` avec projet Xcode Viim.
  - Documentation, blueprints, décisions, QA et tracking.
- Vérifications avant publication :
  - `npm run check` OK dans `backend/`.
  - `xcodebuild -project ios/Viim.xcodeproj -scheme Viim -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` OK.
  - Pas de secret réel publié ; uniquement `.env.example` avec valeurs vides.
- Statut : source prête pour relance du déploiement Coolify.
