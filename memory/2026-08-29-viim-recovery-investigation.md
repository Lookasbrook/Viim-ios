# Investigation de récupération — Viim

- Date : 2026-08-29
- Statut : BLOCKED — aucun point de restauration local accessible

## Symptôme

Le dossier de travail historique `/Users/lookasbrook/Documents/Viim-ios` a
disparu sur ce Mac et sur le MacBook. Le clone GitHub restauré ne contient pas
le module Android ni les commits locaux non poussés.

## Éléments vérifiés

- GitHub expose uniquement `main`.
- La branche locale `feat/whatsapp-alertes-durcissement` ne contient pas
  `android/`.
- `git fsck --no-reflogs --unreachable` ne révèle aucun commit récupérable.
- Ni la corbeille, ni Documents, ni iCloud Drive ne contiennent un dossier
  Viim exploitable.
- `tmutil destinationinfo` ne rapporte aucune destination Time Machine et
  aucun snapshot local n'est disponible.
- Le worktree de sauvegarde sur `Z Slim` ne contient pas le module Android.
- Spotlight référençait des artefacts Hilt Android sous iCloud Drive, mais le
  dossier indexé est vide : ce sont des entrées d'index obsolètes, pas des
  sources récupérables.

## Hypothèse de cause

Le projet se trouvait sous Documents synchronisé par iCloud. Une suppression ou
un déplacement propagé par iCloud Drive est l'explication la plus cohérente avec
la disparition observée sur les deux Macs. Le système de fichiers disponible ne
conserve plus les journaux ni snapshots permettant de prouver l'événement exact.

## Données préservées

Les historiques Codex conservent des patches textuels permettant de reconstruire
une partie importante du chantier « carburant modélisé » (contrats, tests iOS,
backend, documentation et variante GPS). Ils ne remplacent pas le module Android
complet ni les commits Git non poussés.

## Recommandation

Ne plus utiliser iCloud Drive comme emplacement canonique d'un dépôt Git.
Conserver le dépôt sous `/Users/lookasbrook/05_Dev/apps/Viim-ios`, pousser
régulièrement les commits, et mettre en place une sauvegarde distincte du dépôt.
