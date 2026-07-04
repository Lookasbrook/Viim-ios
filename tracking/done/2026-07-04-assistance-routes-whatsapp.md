# Terminé — Assistance fonctionnelle et routes WhatsApp

- Date : 2026-07-04
- Par : Codex builder
- Référence : `ASSIST-001`, `ASSIST-002`, `features/onglet-3-assistance.md`, `architecture/api-endpoints.md`

## Résumé

Le premier lot Assistance rend les boutons visibles exploitables et ajoute les endpoints backend minimum pour les alertes WhatsApp.

## Backend

- `POST /v1/alerts/test`
- `POST /v1/alerts/location-share`
- `POST /v1/alerts/collision`
- Validation téléphone Burkina au format `+226XXXXXXXX`.
- Validation coordonnées GPS.
- Client NEwAGENT WhatsApp en POST, sans log du token.
- Tests Node avec injection d'un faux provider, sans envoi WhatsApp réel.

## iOS

- Onglet Assistance sans actions vides.
- Appels natifs `18` et `17`.
- Écran MapKit de localisation.
- Partage de position vers le contact d'urgence.
- Contact d'urgence stocké et relu dans le Keychain.
- Fiche médicale stockée et relue dans le Keychain.
- Bouton test WhatsApp branché sur `/v1/alerts/test`.
- Accueil : statut `Alerte famille` passe à `Activé` si un contact est configuré.
- Votre conduite : `Voir mon style de conduite` ouvre un écran détaillé.

## Vérification

- `npm test` : OK.
- `npm run check` : OK.
- `xcodebuild test -project ios/Viim.xcodeproj -scheme Viim -destination 'id=03FD6AF7-BDCD-4BE5-A376-D6BAD4B0A734' CODE_SIGNING_ALLOWED=NO` : OK.
- Build signé iPhone réel : OK.
- Installation iPhone réel : OK.
- Lancement `com.yamstack.viim` sur l'iPhone de Guy : OK.
- Production Coolify redéployée sur `cf47617` : `/health` public OK.
- `POST /v1/alerts/test` public avec téléphone invalide : HTTP 422 `invalid_contact`, donc la route n'est plus en 404.

## Reste

- Faire un vrai test WhatsApp avec un contact consenti.
- Implémenter la cascade contact 1 → contact 2 → contact 3 et le fallback SMS (`ASSIST-003`).
