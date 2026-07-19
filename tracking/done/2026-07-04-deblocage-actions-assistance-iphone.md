# Terminé — Déblocage actions Assistance sur iPhone

- Date : 2026-07-04
- Par : Codex builder
- Référence : `ASSIST-005`, `ASSIST-006`, `features/onglet-3-assistance.md`, `architecture/api-endpoints.md`

## Cause racine

- `Envoyer un test WhatsApp` était désactivé dès que `emergencyContact == nil`, sans action de récupération directe.
- `Voir ma localisation` affichait seulement `latestLocation`. Si aucun trajet ou réveil GPS n'avait encore produit de position, l'écran restait bloqué en attente.

## Correctif

- L'action principale Assistance ouvre `Configurer un contact` quand aucun contact d'urgence valide n'est chargé.
- Le contact Keychain est chargé via `loadNormalizedForBurkina()` pour éviter les états incohérents.
- L'écran localisation déclenche une position GPS ponctuelle foreground via `requestLocation()`.
- La demande ponctuelle ne promeut pas le service en suivi GPS continu.
- L'écran localisation affiche des états distincts : recherche, autorisation requise, position refusée, actualisation.

## Vérification

- `xcodebuild test -quiet -project ios/Viim.xcodeproj -scheme Viim -destination 'id=03FD6AF7-BDCD-4BE5-A376-D6BAD4B0A734' CODE_SIGNING_ALLOWED=NO` : OK.
- `LocationServiceTests.testForegroundLocationRequestDoesNotPromotePassiveWakeup` : OK.
- Build signé iPhone réel : OK.
- Installation iPhone réel : OK.
- Lancement `com.yamstack.viim` sur l'iPhone de Guy : OK.
- API publique `/health` : OK.

## Reste

- Guy doit retester l'appui réel sur `Voir ma localisation` et `Envoyer un test WhatsApp` avec un contact valide configuré.
- Aucun envoi WhatsApp réel n'a été lancé sans contact consenti.
