# ADR — Un seul repo Git `viim` (monorepo iOS + backend)

**Date** : 2026-07-01 · **Statut** : Accepté · **Décideur** : Claude (Architecte/QA), tranché pour débloquer le builder

## Contexte
`blueprints/00-ordre-execution.md` laissait le choix ouvert entre un repo unique `viim` et deux repos séparés `viim-ios` / `viim-backend`, avec ADR obligatoire avant le premier commit. Un seul builder (François De Salle) travaille sur les deux couches en parallèle (P0 Fondations démarre les deux en même temps).

## Décision
**Un seul repo Git, nommé `viim`.** Structure à la racine :

```
viim/
├── ios/            (projet Xcode "Viim" — blueprints/01-ios-app.md)
├── backend/         (viim-api Node.js/PostgreSQL — blueprints/02-backend-coolify.md)
├── architecture/    (doc existante, inchangée)
├── blueprints/
├── decisions/
├── design/
├── features/
├── qa/
├── tracking/
├── README.md
└── CHANGELOG.md
```

Coolify pointe son build de l'app `viim-api` sur le sous-dossier `backend/` du même repo (build context configurable dans Coolify).

## Justification
- Un seul contributeur sur les deux couches : pas de bénéfice à séparer, seulement de la friction (deux PR, deux CHANGELOG, deux historiques à recouper).
- La documentation (`architecture/`, `qa/`, `tracking/`) est déjà transverse aux deux couches — la garder dans le même repo que le code qu'elle décrit évite la dérive doc/code.
- Un seul PR peut couvrir un changement de contrat API (ex. `data-models.md` + `ios/Services/SyncManager.swift` + `backend/src/routes/trips.js`) sans coordination inter-repos.
- Coolify supporte nativement un build context sur sous-dossier — aucune contrainte technique à séparer les repos pour le déploiement.

## Conséquences
- `tracking/in-progress.md` et `tracking/done/[date]-[tâche].md` doivent préciser la couche concernée (`ios/` ou `backend/`) dans leurs entrées.
- Si l'équipe grandit avec des développeurs dédiés à chaque couche (post-MVP), réévaluer via un nouvel ADR — la séparation en deux repos reste une option ouverte à ce moment-là.
- `blueprints/00-ordre-execution.md` (prérequis 4) et `blueprints/01-ios-app.md` / `02-backend-coolify.md` (arborescences) sont mis à jour en conséquence.
