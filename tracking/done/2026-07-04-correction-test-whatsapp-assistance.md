# Terminé — Correction test WhatsApp Assistance

- Date : 2026-07-04
- Par : Codex builder
- Référence : `ASSIST-004`, `features/onglet-3-assistance.md`, `architecture/api-endpoints.md`

## Cause racine

Le contact d'urgence pouvait être stocké depuis l'onboarding avec un format humain (`+226 70 00 00 00`) ou local (`70000000`). Le backend Assistance exige le format canonique `+226XXXXXXXX`; le bouton `Envoyer un test WhatsApp` envoyait donc parfois la valeur Keychain brute et recevait `422 invalid_contact`.

## Correctif

- Ajout de `BurkinaPhoneNumber.normalized(_:)`.
- Normalisation du contact d'urgence avant stockage Keychain.
- Normalisation défensive avant appel `/v1/alerts/test` et `/v1/alerts/location-share`.
- Validation onboarding renforcée pour le téléphone utilisateur et le contact d'urgence.
- Formulaire Assistance : sauvegarde en format canonique et affichage du numéro normalisé.
- Message localisé si le contact existant est invalide.

## Vérification

- Reproduction sans envoi réel : l'API rejette `+226 70 00 00 00` en HTTP 422.
- `xcodebuild test -quiet -project ios/Viim.xcodeproj -scheme Viim -destination 'id=03FD6AF7-BDCD-4BE5-A376-D6BAD4B0A734' CODE_SIGNING_ALLOWED=NO` : OK.
- `BurkinaPhoneNumberTests` : OK.
- Build signé iPhone réel : OK.
- Installation iPhone réel : OK.
- Lancement `com.yamstack.viim` sur l'iPhone de Guy : OK.
- API publique `/health` : OK.

## Reste

- Faire un vrai test WhatsApp avec un contact consenti.
- Déployer le commit iOS/backend sur Coolify si le backend change plus tard ; ce correctif est iOS-only.
