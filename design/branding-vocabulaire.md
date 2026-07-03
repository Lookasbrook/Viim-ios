# Branding & vocabulaire — Viim

## Nom

**Viim** — « la vie » en mooré. Décision de Guy (PO), 2026-07-01. Remplace le nom de travail YAMSTACK pour tout ce qui est visible de l'utilisateur.

## Règle de marque (stricte)

- **Viim** : partout dans l'app, l'App Store, les messages WhatsApp, les notifications.
- **YAMSTACK TECHNOLOGIE** : une seule mention dans l'app, en pied de l'onglet Assistance — "Viim est édité par YAMSTACK TECHNOLOGIE — Ouagadougou, Burkina Faso". Conservée aussi dans les mentions légales/À propos (Paramètres) et les documents juridiques.
- Aucune autre occurrence de YAMSTACK dans l'UI.

## Ton et registre

- **Vouvoiement** dans toute l'interface ("Vos trajets", "Votre moto").
- **Tutoiement chaleureux** dans le résumé WhatsApp quotidien uniquement (canal intime, cf. template) : "Ton résumé Viim".
- Français simple et direct : phrases courtes, pas de jargon technique ("synchroniser" plutôt que "sync", "détection de collision" plutôt que "crash detection").
- Ancrage local naturel sans folklore : FCFA, Ouagadougou, saison des pluies, harmattan — jamais de clichés.
- Sécurité : ton sérieux et rassurant, jamais culpabilisant ("Votre conduite présente des risques" et non "Vous conduisez mal").

## Typographie et micro-règles (français)

- Espace insécable avant : `%`, `?`, `!`, `:`, `»` — et dans les nombres : "1 200 FCFA", "20 h 45".
- FCFA abrégé "F" dans les cartes compactes, "FCFA" en toutes lettres au premier affichage d'un écran.
- Heures au format "19 h 06". Dates : "1ᵉʳ juillet".
- Majuscule uniquement au premier mot des titres ("Résumé du jour", pas "Résumé Du Jour").
- Terminologie fixe : "trajet" (jamais "voyage"), "freinage brusque", "excès de vitesse", "fiche médicale", "contacts d'urgence", "moyen de déplacement".

## Couleurs

| Usage | Hex |
|---|---|
| Navy (Accueil, titres) | `#1A3A5C` |
| Bleu (Conduite, actions) | `#2E75B6` |
| Rouge (Assistance, urgence) | `#C00000` |
| Vert (Prévention, positif) | `#217346` |
| Or (accent marque Viim) | `#E8B932` |
| Succès / Alerte / Danger | `#1FA363` / `#F29B1D` / `#D93636` |

## Cartographie

**MapKit natif iOS exclusivement**, affiché dans l'app (jamais de redirection vers une app externe pour la consultation ; le lien Google Maps n'existe que pour le *partage* de position à un tiers).

## Langues

V1 : français. V2 : mooré et dioula (prévoir `Localizable.strings` dès le départ — aucune chaîne en dur dans le code).
