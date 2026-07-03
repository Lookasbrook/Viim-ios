# Blueprint 01 — App iOS Viim

## Projet Xcode

- Nom : **Viim** · Bundle ID suggéré : `com.yamstack.viim` · Swift 5.9+ · iOS 16+ · SwiftUI.
- Capabilities : Background Modes (**Location updates**, Background fetch, Background processing), Push Notifications.
- `Info.plist` : `NSLocationAlwaysAndWhenInUseUsageDescription`, `NSLocationWhenInUseUsageDescription`, `NSMotionUsageDescription`, `NSCameraUsageDescription` (photo véhicule, constat) — textes en français simple, expliquant le bénéfice sécurité.
- Aucune dépendance tierce en V1 (tout est natif). Si besoin ponctuel : ADR obligatoire.

## Arborescence suggérée

Sous `ios/` à la racine du monorepo `viim` ([ADR repo](../decisions/2026-07-01-repo-monorepo.md)) :

```
ios/
├── App/                    (ViimApp.swift, RootTabView — 4 onglets)
├── DesignSystem/           (couleurs, typographies, composants : cartes, barres, chips)
├── Onboarding/             (3 étapes — features/inscription-onboarding.md)
├── Features/
│   ├── Accueil/  Conduite/  Assistance/  Prevention/  Profil/
├── Services/
│   ├── LocationService.swift      (CLLocationManager, allowsBackgroundLocationUpdates = true)
│   ├── SensorService.swift        (CMMotionManager 50 Hz, filtre passe-bas, buffer 30 s)
│   ├── TripManager.swift          (cycle de vie trajet, détection début/fin)
│   ├── ScoreEngine.swift          (5 critères — sensor-algorithms.md §6)
│   ├── CollisionDetector.swift    (pipeline §5, fenêtre 60 s)
│   ├── AlertService.swift         (WhatsApp via API + SMS MessageUI fallback)
│   ├── SyncManager.swift          (NWPathMonitor, URLSession background pour collision)
│   └── MedicalVault.swift         (Keychain AES-256)
├── Persistence/            (stack CoreData — data-models.md)
├── Resources/
│   ├── Localizable.strings (fr — aucune chaîne en dur)
│   └── Vehicles/           (illustrations par type + modèles courants Ouaga)
└── ViimTests/ + ViimUITests/
```

## Points d'implémentation critiques

1. **GPS background** : `allowsBackgroundLocationUpdates = true`, `pausesLocationUpdatesAutomatically = false` en trajet, `desiredAccuracy` 5 m (20 m mode éco). Tester écran verrouillé ET app tuée.
2. **Filtre + confirmation GPS** : implémenter exactement `sensor-algorithms.md` §1-3. Alpha lié au type de véhicule du profil.
3. **Calibration** : compteur de trajets dans UserProfile ; UI "Calibration en cours (trajet X/5)" ; jamais de score avant le 6ᵉ trajet.
4. **Collision** : buffer circulaire 30 s en mémoire ; notification locale interactive ("Êtes-vous en sécurité ? [OUI] [J'AI BESOIN D'AIDE]") ; envoi via `URLSessionConfiguration.background(withIdentifier:)` pour survivre à la suspension.
5. **MapKit** : `MKMapView`/`Map` SwiftUI, polyline colorée par segment (`MKPolyline` + renderer par score), marqueurs événements. Miniatures : `MKMapSnapshotter` (cache local).
6. **Véhicule adaptatif** : à l'inscription, `type+marque+modèle` → asset illustration (fallback silhouette) ; seuils/alpha/textes pilotés par `Vehicle.type` (table dans inscription-onboarding.md). Photo utilisateur : `photoLocalPath`, jamais synchronisée.
7. **Keychain** : `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` pour la fiche médicale ; lecture au moment de la collision uniquement.

## UI — références exactes

Maquettes : `design/maquettes-ecrans.html` (7 écrans). Charte : `design/branding-vocabulaire.md`. Tab bar : 4 items alignés, icônes SF Symbols (`house`, `gauge.with.needle` ou `steeringwheel`, `exclamationmark.triangle`, `shield`), teinte par onglet actif.

## Tests attendus (ViimTests)

- Unitaires : filtre passe-bas (signal synthétique bruité), confirmation GPS (cas nid-de-poule = rejet), ScoreEngine (jeux de données fixes), idempotence de la file de sync.
- Manuels terrain : scénarios S1-S6 de `qa/test-plan.md`, consignés dans `qa/test-results.md`.
