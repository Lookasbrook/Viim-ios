# Terminé — Diagnostic GPS et WhatsApp

- Date : 2026-07-05
- Par : Codex builder
- Référence : `blueprints/2026-07-05-diagnostic-gps-whatsapp.md`, `GPS-101`, `GPS-102`, `WA-101`, `WA-102`, `ASSIST-002`

## Livré

- Normaliseur iOS `BurkinaPhoneNumber` pour stocker les numéros Burkina au format exact `+226XXXXXXXX`.
- Onboarding et écran contacts : validation avec normalisation, refus des numéros non normalisables et blocage des anciens contacts Keychain invalides via l'état `Contact à corriger`.
- `BackendAPIClient` : décodage du body JSON d'erreur, mapping des erreurs 422/503/offline/timeout et logs publics sans contenu sensible.
- Assistance localisation : demande ponctuelle `requestLocation()`, état de recherche, timeout exploitable et partage de position avec erreurs plus précises.
- Accueil GPS : distinction entre position active seulement dans l'app et arrière-plan, avec bouton utilisateur pour demander l'autorisation `Always`.
- Backend WhatsApp : logs scrubbed sur succès/échec provider, sans numéro, token, métadonnées sensibles ni body provider.

## Écarts vs Spec

- Le vrai test WhatsApp avec un contact consenti reste manuel.
- Le scénario GPS écran verrouillé S1 reste à valider sur iPhone réel après acceptation de l'autorisation `Always`.
- La cascade contact 1 → 2 → 3, le fallback SMS et `SyncManager` restent hors de ce lot et consignés dans `ASSIST-003` / Phase 2.

## Vérification

- `npm test --prefix backend` : OK, 5 tests.
- `npm run check --prefix backend` : OK.
- `xcodebuild test -project ios/Viim.xcodeproj -scheme Viim -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/viim-deriveddata` : OK, 24 tests.

## Commits

- Non committé dans cette session.
