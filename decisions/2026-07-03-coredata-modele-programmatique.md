# ADR — Modèle CoreData programmatique pour Viim iOS

- Date : 2026-07-03
- Statut : accepté
- Décideur : Codex builder

## Contexte

La Phase 1 exige une persistance locale offline-first pour les trajets (`Trip`, `TripEvent`, `DailySummary`) avec un flag `synced`. Le projet contenait `PersistenceController`, mais aucun fichier `.xcdatamodeld`. Dès que l'app devait réellement initialiser CoreData, le conteneur nommé `Viim` n'avait pas de modèle embarqué exploitable.

## Décision

Le modèle CoreData V1 est défini en Swift dans `PersistenceController.makeManagedObjectModel()` et passé à `NSPersistentContainer(name:managedObjectModel:)`.

Entités initiales :

- `Trip`
- `TripEvent`
- `DailySummary`

Chaque entité porte au minimum `synced` et `createdAt` quand elle représente une donnée persistée/synchronisable.

## Raisons

- Permet de débloquer rapidement l'offline-first sans ajouter une source Xcode fragile à la main.
- Rend les tests unitaires simples avec `PersistenceController(inMemory: true)`.
- Garde le contrat de données proche de `architecture/data-models.md`.

## Conséquences

- Les migrations CoreData devront être gérées explicitement en Swift quand le modèle évoluera.
- Si le modèle devient complexe, un passage à `.xcdatamodeld` pourra être décidé dans une ADR dédiée.
- Le schéma actuel ne remplace pas le futur `SensorService` ni le `ScoreEngine` ; il fournit seulement la base locale nécessaire pour afficher les trajets réels et préparer la sync.
