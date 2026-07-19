# DEBUG REPORT - Donnees trajets et score - 2026-07-07

## Symptom

Les donnees affichees semblaient non fiables: score de conduite douteux, nombre de trajets faux, distance douteuse, duree fausse.

## Root cause

1. La distance persistee venait de `CompletedDetectedTrip.distanceMeters`, un accumulateur produit pendant le suivi actif. La politique projet demandait pourtant une distance calculee depuis les points GPS filtres.
2. Les points GPS etaient filtres par precision horizontale, mais les segments n'etaient pas validates physiquement. Un saut GPS avec une bonne accuracy pouvait donc creer un faux trajet, gonfler la distance et incrementer le nombre de trajets.
3. La duree d'un trajet termine par detection stationnaire utilisait l'heure de confirmation/fin, ce qui incluait l'attente immobile. Le trajet devait finir au dernier echantillon encore en mouvement.
4. Le score vitesse penaliseait un pic GPS instantane. Le document capteurs demande un exces de vitesse soutenu 10 s.

## Fix

- Ajout de `TripMetricsCalculator.distanceMetric` et `durationMetric`, avec validation des segments par vitesse physique maximum selon le type de vehicule.
- `TripManager` refuse maintenant un trajet non fiable avant insertion.
- `TripStore` recalcule la distance depuis les samples GPS filtres et valide avant de creer l'objet CoreData.
- `LocationService` garde `lastMovingAt` et termine les trajets stationnaires sur cet instant.
- `ScoreEngine` ne penalise la vitesse que si l'exces dure au moins 10 s.

## Evidence

Commande:

```bash
xcodebuild test -project ios/Viim.xcodeproj -scheme Viim -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' CODE_SIGNING_ALLOWED=NO
```

Resultat: `** TEST SUCCEEDED **`

## Regression tests

- `TripReliabilityTests.testDistanceMetricRejectsImpossibleGpsJumpEvenWithGoodAccuracy`
- `TripManagerTests.testImpossibleGpsJumpIsNotPersistedAndDoesNotIncrementTripCount`
- `TripStoreTests.testStoredDistanceUsesFilteredGpsSegmentsInsteadOfReportedAccumulator`
- `TripStoreTests.testRejectedUnreliableTripDoesNotLeavePartialCoreDataObject`
- `LocationServiceTests.testStationaryFinalizationEndsAtLastMovingSample`
- `ScoreEngineTests.testBriefSpeedSpikeDoesNotPenalizeScore`
- `ScoreEngineTests.testSustainedOverspeedPenalizesScore`

## Related

Le worktree contenait deja beaucoup de changements non commit avant cette investigation. Les corrections ont ete limitees au pipeline trajet/score et aux tests associes.

## Status

DONE
