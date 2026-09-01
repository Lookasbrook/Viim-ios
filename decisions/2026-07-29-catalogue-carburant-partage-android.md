# ADR — Catalogue carburant partagé iOS / Android

- Date : 2026-07-29
- Statut : accepté
- Décideur : Codex builder

## Contexte

Le catalogue iOS `VehicleFuelCatalog.swift` a servi de référence comportementale
pour les consommations indicatives par véhicule. Le blueprint Android interdit
sa ressaisie manuelle : elle créerait une dérive silencieuse entre plateformes.

La décision initiale faisait extraire du Swift par expressions régulières un
JSON destiné à Android. Cette approche ne permet pas de représenter proprement
des fiches sourcées, plages d'années, motorisations, normes d'homologation et
versions de données. Elle rend aussi Swift responsable d'un contrat backend.

## Décision

À partir du chantier du 2026-08-11, la source canonique est un **dataset structuré
et versionné**, indépendant de Swift, Kotlin et Node. Il contient les données,
leur provenance et leur période de validité. Les clients consomment des artefacts
générés ou des caches issus de cette source ; ils ne réécrivent pas le catalogue.

`shared-data/vehicle-fuel-catalog.json` reste temporairement l'artefact v7 en
production. `VehicleFuelCatalog.swift` et le générateur regex restent inchangés
tant que le nouveau dataset n'a pas franchi la porte de faisabilité de la Phase 3.
Ils ne doivent recevoir aucun nouveau champ métier complexe.

Les valeurs de contrat stables du chantier sont définies dans
`shared-data/carburant-contract-v1.json` et vérifiées par chaque runtime.

## Conséquences

- Jusqu'à la migration, toute modification du catalogue v7 impose encore la
  régénération du JSON et sa revue dans le même changement.
- Le futur générateur doit produire et valider les artefacts Swift, Kotlin et
  backend à partir du dataset canonique, avec des fixtures dorées communes.
- Une divergence entre runtimes devient une erreur de build ou de test.
- Le catalogue v7 reste un baseline historique, pas une preuve de consommation.
- Les prix régionaux, FX et snapshots immuables suivent les contrats du
  blueprint du 2026-07-14, étendus par celui du 2026-08-11.
