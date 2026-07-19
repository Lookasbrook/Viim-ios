# ADR — Fenêtre GPS de confirmation et snapshots actifs

- Date : 2026-07-04
- Statut : Accepté
- Décideur : Codex builder, sur demande de Guy
- Portée : iOS, détection automatique, CoreData, Accueil

## Contexte

Après plusieurs trajets réels au Québec, l'Accueil affichait encore `0 km`.

Investigation sur l'iPhone réel :

- Autorisation localisation : `authorizedAlways`.
- Conteneur app inspecté : `Documents` vide, aucun stockage trajet hors `Library/Application Support/Viim.sqlite`.
- Base CoreData : `ZTRIP=0`, `ZTRIPEVENT=0`, `ZDAILYSUMMARY=0`.
- Logs au repos : réveils passifs actifs, mais premier point ignoré et aucun `trip.begin`, `trip.end` ou `trip.persisted`.

La décision du 2026-07-03 était trop stricte : un réveil passif devait déjà contenir une vitesse ou un déplacement significatif pour ouvrir le GPS continu. En pratique, le premier point iOS peut être immobile, sans vitesse, ou insuffisant pour confirmer un trajet.

## Décision

Viim ouvre désormais une fenêtre GPS de confirmation courte lorsqu'un réveil passif fournit au moins une position utilisable.

Pendant cette fenêtre :

- le GPS continu collecte des points de confirmation ;
- le trajet démarre si la vitesse reste au moins à 8 km/h pendant 15 secondes ;
- si aucun trajet actif n'est confirmé après 3 minutes, Viim arrête le GPS continu et conserve l'écoute passive.

Quand un trajet actif existe, Viim persiste des snapshots CoreData au fil des échantillons. L'Accueil peut donc afficher les kilomètres du jour avant une finalisation parfaite. À la fin du trajet, le même enregistrement CoreData est mis à jour au lieu d'être ignoré comme doublon.

## Conséquences

- Les kilomètres du jour deviennent visibles dès qu'un trajet actif est confirmé.
- Un trajet actif n'est plus perdu si iOS ne livre pas correctement les points d'arrêt.
- Le GPS continu peut être ouvert pendant une courte fenêtre de confirmation après un réveil passif, puis s'arrête si rien ne confirme le déplacement.
- Les trajets passés non collectés avant ce correctif restent non reconstructibles depuis l'app.

## Vérification

- Tests ajoutés : snapshot actif inclus dans le résumé du jour, finalisation qui met à jour le snapshot, démarrage de trajet sur vitesse GPS simulée.
- `xcodebuild test` simulateur : OK.
- Build signé iPhone réel : OK.
- Installation sur l'iPhone réel de Guy : OK.
