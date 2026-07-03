# Inscription & Onboarding — véhicule adaptatif

**Inspiration BNA** : la carte du véhicule couvert avec sa photo ("TOYOTA COROLLA LE 4P — 2015 · ✓ Couvert"). Dans Viim, le véhicule déclaré à l'inscription personnalise toute l'app.

## Parcours d'inscription (3 étapes)

### Étape 1 — Identité
- Prénom + numéro de téléphone (E.164, +226…) — le numéro sert au résumé WhatsApp.
- Consentement localisation expliqué en langage simple avant la demande système iOS.

### Étape 2 — Moyen de déplacement (obligatoire)
- Type : **Moto / Voiture / Vélo** (sélecteur visuel).
- Marque + modèle (champ texte avec suggestions des modèles courants à Ouagadougou : Yamaha Crypton, Sirius, KTM, Aloba, Toyota Corolla…), année facultative.
- **Aperçu immédiat du véhicule** : illustration affichée dès la saisie (voir "Illustration véhicule" ci-dessous).

### Étape 3 — Sécurité (facultative, fortement incitée)
- Ajout d'au moins 1 contact d'urgence ; fiche médicale proposée ("2 minutes qui peuvent sauver votre vie").
- Passable ("Plus tard") — rappels doux ensuite.

Après l'étape 3 : phase de calibration silencieuse (5 trajets, aucun score affiché).

## Adaptation de l'app selon le véhicule inscrit

| Paramètre | Moto | Voiture | Vélo |
|---|---|---|---|
| Alpha filtre passe-bas | 0.15 | 0.25 | 0.20 |
| Seuil excès de vitesse | > 80 km/h | > 100 km/h | — (désactivé) |
| Rappels entretien | vidange, chaîne, pneus | vidange, pneus, freins | chaîne, freins |
| Textes UI | "votre moto" | "votre voiture" | "votre vélo" |
| Estimation carburant | oui | oui | non (calories/CO₂ évitables V2) |
| Détection collision | sensibilité Élevée par défaut | Normale par défaut | Élevée |

## Illustration véhicule (règle BNA)

1. **V1** : bibliothèque d'illustrations vectorielles par type + silhouettes des modèles les plus courants à Ouagadougou (mapping `marque+modèle → asset`, fallback silhouette générique du type).
2. L'utilisateur peut **prendre une photo réelle** de son véhicule (stockée localement uniquement) — elle remplace l'illustration.
3. L'illustration/photo apparaît : carte véhicule de l'Accueil ("✓ Suivi actif"), Profil, écran Entretien.

## Changement de véhicule

- Modifiable dans Profil. Les nouveaux seuils s'appliquent au trajet suivant (jamais rétroactif).
- Multi-véhicules : V2. En V1, un seul véhicule principal.

## Critères de validation (QA)

- [ ] Impossible de terminer l'inscription sans type de véhicule.
- [ ] L'illustration correspond au type dès l'étape 2, avant validation.
- [ ] Les seuils (alpha, vitesse) reflètent le type dès le premier trajet.
- [ ] Photo utilisateur : jamais synchronisée au backend.
- [ ] Vocabulaire conforme à [design/branding-vocabulaire.md](../design/branding-vocabulaire.md).
