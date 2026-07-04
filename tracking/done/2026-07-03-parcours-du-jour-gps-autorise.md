# Terminé — Parcours du jour absent malgré GPS autorisé

- Date : 2026-07-03
- Par : Codex builder
- Référence : `TRIP-003`, `features/onglet-1-accueil.md`, `architecture/sensor-algorithms.md`

## Résumé

Le bug signalé n'était pas un problème d'affichage des écrans. L'iPhone avait bien l'autorisation de localisation, mais aucun trajet n'était enregistré dans la base locale de Viim.

## Cause confirmée

- Logs iPhone : `location.authorization state=authorizedAlways`.
- Base CoreData copiée depuis l'iPhone : `ZTRIP=0`, `ZTRIPEVENT=0`, `ZDAILYSUMMARY=0`.
- Le pipeline pouvait rester en veille si le départ se produisait hors app active.
- Un réveil passif initial pouvait aussi lancer brièvement le GPS continu à l'arrêt, ce qui risquait de réafficher l'indicateur GPS sans créer de trajet utile.

## Implémentation

- Ajout de `ViimDiagnostics` pour tracer le pipeline mouvement → localisation → trajet → persistance.
- Ajout d'une écoute passive `startMonitoringSignificantLocationChanges` quand `authorizedAlways` est disponible.
- Promotion vers GPS continu seulement si le réveil passif indique une vitesse ou un déplacement réel.
- Finalisation d'un trajet actif après immobilité, avec seuil minimal de distance ou durée avant persistance.
- Accueil : affichage du statut `Réveil automatique actif` au repos.
- Tests : ajout de `LocationServiceTests` pour verrouiller les seuils de finalisation après immobilité.

## Vérification

- `xcodebuild test -project ios/Viim.xcodeproj -scheme Viim -destination 'id=03FD6AF7-BDCD-4BE5-A376-D6BAD4B0A734' CODE_SIGNING_ALLOWED=NO` : OK.
- Build signé iPhone réel : OK.
- Installation iPhone réel : OK.
- Logs iPhone après correctif : `location.authorization state=authorizedAlways`, `location.passiveWakeups.start`, `location.passiveWakeup.ignored count=1`, `motion.phase stationary`.

## Limite

Un parcours déjà effectué avant que Viim ne collecte les points GPS ne peut pas être reconstruit rétroactivement. Le prochain déplacement réel doit créer les données du jour.
