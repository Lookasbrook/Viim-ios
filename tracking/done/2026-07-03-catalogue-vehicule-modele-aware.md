# Catalogue véhicule par marque et modèle

- Date : 2026-07-03
- Par : Codex builder
- Référence : `features/inscription-onboarding.md`, `design/maquettes-ecrans.html`, `qa/known-issues.md`

## Réalisé

- Ajout de `VehiclePhotoCatalog` pour résoudre une photo uniquement à partir du type, de la marque et du modèle saisis.
- Suppression des anciennes photos génériques par type, dont la voiture Waymo.
- Ajout de 10 assets modèle-aware : Toyota Corolla, Toyota Hilux, Toyota RAV4, Toyota Land Cruiser Prado, Toyota Land Cruiser, Yamaha Crypton, Yamaha YBR 125, Bajaj Boxer, TVS Apache et Honda CG125.
- Fallback neutre : si le modèle n'est pas reconnu, l'Accueil affiche une illustration, pas une photo potentiellement fausse.
- Ajout du target XCTest `ViimTests`.

## Vérification

- `xcodebuild test` sur iPhone 17 Simulator OK.
- 5 tests passés dans `VehiclePhotoCatalogTests`.
- Les tests vérifient les mappings marque/modèle, les variantes de saisie, les cas inconnus et la présence des assets dans le bundle.
- Build simulateur OK.
- Build signé iPhone réel OK.
- Installation et lancement de `com.yamstack.viim` confirmés sur l'iPhone de Guy.
