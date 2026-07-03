# Réalignement des onglets Conduite, Assistance et Prévention

- Date : 2026-07-03
- Par : Codex builder
- Référence : `design/maquettes-ecrans.html`, `qa/known-issues.md`

## Réalisé

- Onglet Votre conduite : héros visuel, statistiques de calibration, performance globale, écoconduite, badges, critères vitesse/fluidité/vigilance, sécurité/éco et conseil.
- Onglet Assistance : héros rouge, soutien temps réel, actions rapides, urgences, hôpitaux proches, mention de confidentialité et pied YAMSTACK.
- Onglet Prévention : héros vert, zones dangereuses ONASER, alertes saisonnières, entretien du véhicule inscrit et défi de la semaine.
- Tous les nouveaux textes visibles passent par `Localizable.strings`.
- Les valeurs restent en calibration/configuration tant que les données métier réelles ne sont pas branchées.

## Vérification

- `git diff --check` OK.
- Build simulateur iOS OK.
- Grep sans texte français direct dans les trois fichiers Swift.
- Build signé iPhone réel OK.
- Installation et lancement de `com.yamstack.viim` confirmés sur l'iPhone de Guy.
