# Indicateur GPS visible après autorisation

- Date : 2026-07-03
- Par : Codex builder
- Référence : `blueprints/01-ios-app.md`, `architecture/sensor-algorithms.md`, `qa/known-issues.md`

## Réalisé

- Cause confirmée : Viim démarrait le suivi GPS continu au lancement après onboarding, demandait automatiquement `Always` et activait l'indicateur arrière-plan.
- Suppression de la demande automatique `Always`.
- Désactivation de `showsBackgroundLocationIndicator`.
- Remplacement du démarrage automatique par une préparation passive de la localisation.
- Ajout de l'ADR `decisions/2026-07-03-localisation-discrete-ios.md`.

## Vérification

- `rg` confirme l'absence de `requestAlwaysAuthorization` et de `showsBackgroundLocationIndicator=true`.
- `git diff --check` OK.
- Build simulateur iOS OK.
- Build signé iPhone réel OK.
- Installation et lancement de `com.yamstack.viim` confirmés sur l'iPhone de Guy.

## Limite restante

Le suivi automatique écran verrouillé doit être repris avec un consentement explicite et une stratégie discrète : CoreMotion pour détecter un déplacement probable, puis confirmation GPS courte.
