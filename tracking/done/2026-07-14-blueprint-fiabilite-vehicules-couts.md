# Terminé — Blueprint fiabilité, véhicules et coûts

- Date : 2026-07-14
- Par : Codex builder
- Référence : `blueprints/2026-07-14-fiabilite-vehicules-couts-internationalisation.md`

## Livré

- Diagnostic consolidé des trajets absents, de l'indicateur iOS persistant et du calcul de carburant actuel.
- Périmètre produit validé : Canada/Burkina, voiture et moto essence/diesel, un véhicule actif, XOF/CAD, aucune saisie de prix ou consommation, hybrides reportés.
- Architecture cible détaillée : catalogue technique backend, prix régionaux, taux BCEAO, instantanés historiques, sync idempotente, migration legacy et minimisation des routes GPS.
- Contrats d'exécution : seuils capteurs, schémas PostgreSQL, payloads API, fraîcheur des sources, états UI, accessibilité, assistance et portes QA.
- `blueprints/00-ordre-execution.md` réaligné pour rendre ce plan prioritaire en cas de contradiction documentaire.

## Vérification

- Revue sémantique : propre.
- Scan de confidentialité pour dépôt public : 0 HIGH, 0 MEDIUM, 0 LOW, 0 WARN.
- Revue d'exécutabilité après révision : 7/10.
- Aucun ticket GitHub, déploiement ou développement lancé depuis cette tâche documentaire.

## Étape suivante

Exécuter P0 : finaliser le correctif GPS/indicateur, incrémenter le build, installer sur l'iPhone privé lorsqu'il redevient disponible et effectuer les trois scénarios terrain.
