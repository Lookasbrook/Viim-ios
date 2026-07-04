# Phase 1 — Détection automatique sans bouton de suivi

- Date : 2026-07-03
- Par : Codex builder
- Référence : [architecture/sensor-algorithms.md](../../architecture/sensor-algorithms.md), [features/onglet-1-accueil.md](../../features/onglet-1-accueil.md), [decisions/2026-07-03-localisation-discrete-ios.md](../../decisions/2026-07-03-localisation-discrete-ios.md)
- Bug lié : `TRIP-002`

## Résultat

- Suppression du bouton manuel "Démarrer le suivi" sur l'Accueil.
- Ajout de `MotionActivityService` avec `CMMotionActivityManager`.
- Déclenchement automatique du GPS quand un mouvement probable est détecté selon le type de véhicule.
- Coupure du GPS quand le téléphone est immobile sans trajet actif.
- Accueil filtré sur les trajets d'aujourd'hui.

## Vérification

- `xcodebuild test -project ios/Viim.xcodeproj -scheme Viim -destination 'id=03FD6AF7-BDCD-4BE5-A376-D6BAD4B0A734' CODE_SIGNING_ALLOWED=NO` : OK.
- Build signé iPhone réel : OK.
- Installation iPhone réel : OK.
- Lancement `com.yamstack.viim` sur l'iPhone de Guy : OK.

## Limites restantes

- Le `SensorService` 50 Hz reste à implémenter pour les événements, collisions et scores fins.
- La collecte écran verrouillé prolongée demandera encore un flux de consentement arrière-plan explicite.
