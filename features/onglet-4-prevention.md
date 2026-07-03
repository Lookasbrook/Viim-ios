# Onglet 4 — Prévention

**Inspiration BNA** : section "Prévention" — "Entretien auto" (rappels de sécurité véhicule), "Alertes météo extrême" (avec statut Activé/Désactivé), "l'Aide-maison" (plan d'action personnalisé + badge "5+ tâches" + "Rappels : Activé"). Adapté : pas de neige, mais pluies, harmattan et zones accidentogènes ONASER.

## 1. Alertes zones dangereuses *(équivalent burkinabè des "Alertes météo extrême" BNA, avec le même statut 🔴 Alertes : Désactivé / 🟢 Activé)*
- Toggle ON/OFF — push quand l'utilisateur approche d'une zone à risque.
- Zones ONASER intégrées (mise à jour manuelle par release) : Boulevard de la Jeunesse (zone n°1, 60% des accidents), Boulevard de l'Insurrection Populaire, Avenue Bassawarga.
- Carte des zones colorées rouge/orange selon le niveau de danger.

## 2. Alertes conditions de route
- 🌧 Saison des pluies : routes glissantes, nids-de-poule aggravés.
- 🌪 Harmattan : visibilité réduite.
- 🚧 Travaux signalés sur les axes principaux.
- 🌙 Conduite de nuit : alerte automatique 20h-6h avec conseils spécifiques.
- ⛽ Pénuries carburant signalées (information communautaire).

## 3. Entretien véhicule *(BNA : "Entretien auto — Consultez les rappels de sécurité concernant votre véhicule", avec pastille "Rappels : Activé")*
- Sélection véhicule : moto / voiture / vélo — marque, modèle, année.
- Rappels maintenance : vidange tous les X km (kilométrage réel enregistré par l'app), pneus, chaîne moto.
- Rappels de sécurité constructeur connus.
- Prochain entretien estimé + "Marquer comme fait" avec historique.
- Badge compteur de tâches en attente (style "5+ tâche(s)" BNA).

## 4. Conseils personnalisés & défis
- Conseil du jour rotatif, basé sur les 7 derniers jours réels.
- Conseils ciblés par critère faible (vitesse, fluidité, vigilance, éco).
- 🏆 Défis hebdomadaires : "0 freinage brusque sur 5 trajets → badge Bronze".

## Critères de validation (QA)

- [ ] Push zone dangereuse déclenchée à l'entrée du périmètre (geofencing), pas en sortie.
- [ ] Statuts Activé/Désactivé persistants et reflétés sur l'accueil.
- [ ] Rappels entretien basés sur le kilométrage cumulé réel des trajets.
- [ ] Aucun conseil basé sur des trajets de calibration.
