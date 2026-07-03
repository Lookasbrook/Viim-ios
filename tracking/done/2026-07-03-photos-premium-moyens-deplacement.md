# Photos premium des moyens de déplacement

- Date : 2026-07-03
- Par : Codex builder
- Référence : `design/maquettes-ecrans.html`, `features/inscription-onboarding.md`

## Réalisé

- Ajout de trois photos locales dans `Assets.xcassets` : moto, voiture, vélo.
- Ajout d'une vignette photo dans la carte véhicule de l'Accueil, adaptée au type de véhicule du profil.
- Documentation des attributions et licences dans `design/vehicle-image-attributions.md`.
- Aucun chargement réseau runtime.

## Vérification

- Images redimensionnées à 1200 px maximum.
- `git diff --check` OK.
- Build simulateur iOS OK.
- Build signé iPhone réel OK.
- Installation et lancement de `com.yamstack.viim` confirmés sur l'iPhone de Guy.
