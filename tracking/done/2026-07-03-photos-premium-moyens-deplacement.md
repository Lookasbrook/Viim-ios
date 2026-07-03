# Photos premium des moyens de déplacement

- Date : 2026-07-03
- Par : Codex builder
- Référence : `design/maquettes-ecrans.html`, `features/inscription-onboarding.md`

## Réalisé

- Ajout initial de trois photos locales dans `Assets.xcassets` : moto, voiture, vélo.
- Ajout d'une vignette photo dans la carte véhicule de l'Accueil.
- Documentation des attributions et licences dans `design/vehicle-image-attributions.md`.
- Aucun chargement réseau runtime.
- Supersédé le 2026-07-03 par le catalogue marque/modèle : les photos génériques ont été retirées pour éviter d'afficher une voiture sans rapport avec le modèle saisi.

## Vérification

- Images redimensionnées à 1200 px maximum.
- `git diff --check` OK.
- Build simulateur iOS OK.
- Build signé iPhone réel OK.
- Installation et lancement de `com.yamstack.viim` confirmés sur l'iPhone de Guy.
