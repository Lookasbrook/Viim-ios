# Investigation — récupération Android Viim depuis Pixel 8

Date : 2026-08-30

## Symptôme

Le dossier source Android local n’était plus présent dans le clone Git restauré,
alors qu’une version de Viim fonctionnait toujours sur le Pixel 8.

## Éléments observés

- Pixel 8 joint par ADB Wi-Fi (`shiba`), paquet `com.yamstack.viim` présent.
- APK debug : version `0.1.0` (versionCode 1), installée/mise à jour le
  29 juillet 2026, `minSdk 26`, `targetSdk 36`.
- Copie de préservation sur le SSD externe :
  `/Volumes/Z Slim/Dev/Builds/Viim-ios/main/Viim-pixel8-debug-0.1.0-2026-07-29.apk`.
- SHA-256 : `06b7269a7280da4a4778b92eb7064cd96096d6ba3807e41f2f5c77bc58d1d26a`.
- Décompilation JADX conservée sur le SSD externe : 303 fichiers métier
  identifiables, avec les noms Kotlin d’origine préservés.

## Architecture récupérable prouvée

L’APK contenait notamment : Jetpack Compose, Hilt, Room, suivi GPS foreground,
trajets/qualité/scores, carburant/véhicules, entretien, assistance, coffre
médical, collision, synchronisation, Firebase et cercle de confiance. Les quatre
onglets sont les mêmes que sur iOS : Accueil, Conduite, Assistance et Prévention.

## Décision de reconstruction

Le Java produit par décompilation est une preuve de comportement, pas une source
de production fiable. Une base Android Kotlin/Compose propre a donc été créée
dans `android/`, alignée avec les contrats iOS existants. Les fonctions réseau ou
sensibles sont hors périmètre jusqu’à revue de leurs contrats backend, permissions
et règles de confidentialité.

## Vie privée

`run-as` a seulement confirmé que l’APK était une build debug. Aucun listing,
copie ou lecture des données privées de l’application installée n’a été effectué :
ni base locale, ni positions, ni contacts, ni données médicales.

## Validation

` :app:testDebugUnitTest :app:assembleDebug` a produit une APK et 4 tests verts.
Les produits de build sont redirigés vers `/Volumes/Z Slim/Dev/Builds/Viim-ios/main/android`.

## Suites recommandées

1. Porter la persistance Room et les migrations à partir des contrats iOS.
2. Réimplémenter la détection GPS/activité et la valider sur le Pixel sur de
   vrais trajets.
3. Réactiver seulement après revue les notifications, Firebase, synchronisation,
   collision et cercle de confiance.
