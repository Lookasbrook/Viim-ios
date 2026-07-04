# Phase 1 — Données trajets visibles et calibration locale

- Date : 2026-07-03
- Par : Codex builder
- Référence : [architecture/data-models.md](../../architecture/data-models.md), [architecture/sensor-algorithms.md](../../architecture/sensor-algorithms.md), [features/onglet-1-accueil.md](../../features/onglet-1-accueil.md)
- Bug lié : `TRIP-001`

## Résultat

- Ajout d'un modèle CoreData local offline-first : `Trip`, `TripEvent`, `DailySummary`, avec `synced` et `createdAt`.
- Ajout de `TripStore` et `TripManager` pour enregistrer les trajets terminés depuis `LocationService`.
- Accueil : état du trajet en cours, résumé du jour dynamique, compteur calibration et trajets récents persistés. Le contrôle explicite initial a été supersédé par la détection automatique `CoreMotion`.
- Votre conduite : compteurs du héros alimentés par les trajets des 30 derniers jours.
- Calibration : les 5 premiers trajets sont persistés avec `isCalibration=true`, score masqué pendant cette phase.

## Vérification

- `xcodebuild test -project ios/Viim.xcodeproj -scheme Viim -destination 'id=03FD6AF7-BDCD-4BE5-A376-D6BAD4B0A734' CODE_SIGNING_ALLOWED=NO` : OK.
- Build signé iPhone réel : OK.
- Installation iPhone réel : OK.
- Lancement `com.yamstack.viim` sur l'iPhone de Guy : OK.

## Limites restantes

- `SensorService` CoreMotion 50 Hz et détection d'événements restent à implémenter.
- La fin automatique d'un trajet suit encore la règle GPS actuelle : arrêt > 5 minutes.
- MapKit miniature réelle des trajets reste à faire ; l'Accueil affiche encore une route stylisée.
