# 2026-07-04 — Trajets du jour et snapshots actifs

## Résumé
- Correction du bug `TRIP-004` : les kilomètres du jour ne s'affichaient pas après des trajets réels au Québec.
- Investigation iPhone : aucune source locale exploitable hors `Library/Application Support/Viim.sqlite`; les trajets passés non collectés ne peuvent pas être reconstruits rétroactivement par l'app.
- Implémentation : persistance CoreData des snapshots de trajet actif, mise à jour du même trajet à la finalisation, fenêtre GPS de confirmation sur réveil passif, seuil de départ ajusté à 8 km/h pendant 15 s.

## Fichiers modifiés
- `ios/Viim/Services/LocationService.swift`
- `ios/Viim/Services/TripManager.swift`
- `ios/Viim/Persistence/TripStore.swift`
- `ios/Viim/App/ViimApp.swift`
- `ios/ViimTests/LocationServiceTests.swift`
- `ios/ViimTests/TripStoreTests.swift`
- `decisions/2026-07-04-confirmation-gps-snapshots-actifs.md`

## Vérifications
- `xcodebuild -project ios/Viim.xcodeproj -scheme Viim -destination 'platform=iOS Simulator,id=03FD6AF7-BDCD-4BE5-A376-D6BAD4B0A734' test` : OK.
- Build signé iPhone réel `E21236A8-1735-5EB6-9A8D-E41C165B962E` : OK.
- Installation sur l'iPhone réel : OK.
- Lancement `com.yamstack.viim` : OK.

## Reste à vérifier
- Test terrain post-installation : rouler quelques minutes avec l'iPhone, puis confirmer que le résumé du jour affiche `km > 0` et que CoreData contient au moins une ligne `ZTRIP`.
