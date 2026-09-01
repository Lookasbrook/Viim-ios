# Viim Android — base reconstruite

Cette base Kotlin/Jetpack Compose est une reconstruction propre de l’APK debug
`com.yamstack.viim` version `0.1.0` retrouvé sur le Pixel 8. Elle ne copie pas
les fichiers Java de décompilation et ne lit aucune donnée privée présente sur
l’appareil.

## Alignement actuel avec iOS

- Navigation : Accueil, Conduite, Assistance, Prévention.
- Domaine : types de véhicule, rôles de trajet et seuils GPS compatibles.
- Trajet : seuil de persistance (60 s / 80 m / 2 points GPS), filtrage des
  vitesses invraisemblables et score de vitesse `score-speed-fluidity-eco-v3`.
- Carburant : le contrat canonique est consommé directement depuis
  `../shared-data/carburant-contract-v1.json`.
- Localisation : service foreground prévu, sans démarrage ni accès à la
  position avant consentement explicite.

Les anciens modules collision, Firebase, cercle de confiance, synchronisation
et coffre médical sont volontairement hors de cette première base : ils
nécessitent une validation sécurité/backend avant réactivation.

## Vérifier

Avant chaque build, monter `Z Slim` puis exécuter `dev-storage-check`.

```sh
./gradlew --project-cache-dir "/Volumes/Z Slim/Dev/Builds/Viim-ios/main/android/gradle-project-cache" :app:testDebugUnitTest :app:assembleDebug
```

L’APK debug est produit sous
`/Volumes/Z Slim/Dev/Builds/Viim-ios/main/android/app/outputs/apk/debug/app-debug.apk`.
