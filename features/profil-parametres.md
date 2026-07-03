# Profil & Paramètres

Accessible via l'avatar en haut de l'accueil (comme l'icône profil BNA).

## Mon profil
- Prénom + numéro de téléphone (utilisé pour le résumé WhatsApp) — modifiables.
- Type de véhicule principal (moto/voiture/vélo) — **affecte alpha du filtre et les seuils de détection**.
- Fiche médicale : lien + statut Complète/Incomplète.
- Contacts d'urgence : lien vers la gestion des 3 contacts.
- Statistiques globales depuis l'inscription ; galerie de badges.

## Badges *(BNA : "Badges de conduite — Vous avez obtenu 62% des badges à remporter")*

| Badge | Condition | Niveau |
|---|---|---|
| 🥉 Conducteur Bronze | 5 trajets sans excès de vitesse | Débutant |
| 🥈 Conducteur Argent | 10 trajets avec score > 80 | Intermédiaire |
| 🥇 Conducteur Or | 30 trajets consécutifs score > 85 | Avancé |
| 🌿 Éco-conducteur | Économiser l'équivalent de 5 pleins | Spécial |
| 🛡 Conducteur sécuritaire | 0 événement dangereux sur 30 trajets | Spécial |
| 💯 Conducteur parfait | Score 100/100 sur un trajet | Rare |
| 🗓 Régulier | 30 jours consécutifs d'utilisation | Fidélité |
| 🏆 Meilleur du quartier | Score moyen > 90 sur le mois | Élite |

Affichage "Vous avez obtenu X% des badges. Autres conducteurs : Y%" (format BNA).

## Classement communautaire (opt-in)
- **Désactivé par défaut**, opt-in explicite. Données anonymisées ("Conducteur1, Conducteur2…").
- "Vous êtes dans le top 15% des conducteurs de Ouagadougou" + courbe d'évolution 3 mois.

## Paramètres
- Notifications : résumé journalier / alertes zones / rappels entretien — ON/OFF indépendants.
- Langue : Français (défaut) — Mooré et Dioula prévus V2.
- Confidentialité : voir quelles données sont locales vs serveur ; **export JSON** (`GET /users/me/export`) ; **suppression historique** locale + backend avec confirmation irréversible.
- Sensibilité détection collision : Faible / Normale / Élevée.
- Mode économie batterie : précision GPS 5 m → 20 m.
- À propos / mentions légales.

## Critères de validation (QA)
- [ ] Changement de véhicule applique les nouveaux seuils au trajet suivant (pas rétroactif).
- [ ] Suppression d'historique vide CoreData + backend (vérifier `/users/me/export` vide après).
- [ ] Classement invisible tant que l'opt-in n'est pas activé.
