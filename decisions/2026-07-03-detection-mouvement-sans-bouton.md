# ADR — Détection de trajet sans bouton manuel

- Date : 2026-07-03
- Statut : accepté
- Décideur : Guy / Codex builder

## Contexte

L'objectif produit de Viim est de réduire la friction. Un bouton "Démarrer le suivi" force l'utilisateur à penser à l'app avant chaque trajet, ce qui est incompatible avec un suivi sécurité routière fiable.

Une décision précédente impose aussi une localisation discrète : Viim ne doit pas laisser le GPS actif en permanence quand l'utilisateur est immobile.

## Décision

Viim utilise `CoreMotion` via `CMMotionActivityManager` pour détecter un déplacement probable selon le type de véhicule :

- moto / voiture : activité automobile avec confiance moyenne ou élevée ;
- vélo : activité cycliste avec confiance élevée ou moyenne ;
- activité immobile ou faible confiance : pas de démarrage GPS.

Quand un déplacement probable est détecté, Viim démarre `LocationService` pour confirmer le trajet avec le GPS et consigner les données utiles. Quand le téléphone redevient immobile sans trajet actif, Viim coupe le suivi GPS.

## Conséquences

- L'Accueil affiche un statut de détection automatique, pas un bouton de démarrage.
- Le GPS reste coupé tant que le téléphone est immobile.
- Les trajets d'aujourd'hui sont visibles depuis le store local dès qu'ils sont confirmés et persistés.
- Le vrai `SensorService` 50 Hz reste à implémenter pour les événements, collisions et scores fins ; ce choix ne le remplace pas.
