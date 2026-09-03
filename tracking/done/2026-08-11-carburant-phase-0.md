# Carburant modélisé — Phase 0 contrats

- Date : 2026-08-11
- Builder : Codex
- Branche historique : `codex/carburant-phase-0`
- Référence : [blueprint actif](../../blueprints/2026-08-11-carburant-modelise-transport-indicateur.md)

## Livré

- Source partagée `shared-data/carburant-contract-v1.json`.
- Types iOS et backend pour les états de coût et la qualité du prix.
- Rôle canonique `conducteur | passager_transport | inconnu`, avec lecture des
  alias historiques `passager` et `bus` sans les conserver comme valeurs cibles.
- Feature flags `gpsSessionSplit`, `physicalFuelModel` et `transitClassifier`,
  tous désactivés par défaut.
- ADR catalogue amendé : dataset structuré canonique, artefacts générés.
- ADR motorisation : aucune inférence depuis les capteurs.
- État `confirmed` réservé à une mesure réelle future ; un coût fondé sur une
  consommation modélisée reste `estimated`, même avec un prix administré exact.

## Vérifications de restauration

- À exécuter après reconstruction : contrat backend, tests XCTest ciblés, JSON,
  projet Xcode et `git diff --check`.
- Le module Android complet n'était pas dans le clone distant de restauration ;
  ses fichiers de Phase 0 sont conservés dans l'historique de sessions et doivent
  être réintroduits avec le module Android, plutôt que comme sources orphelines.
- Aucun commit ni déploiement n'a été effectué par cette restauration.
