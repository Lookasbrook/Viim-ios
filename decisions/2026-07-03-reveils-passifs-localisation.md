# ADR — Réveils passifs de localisation et promotion GPS

- Date : 2026-07-03
- Statut : Accepté
- Décideur : Codex builder, sur demande de Guy
- Portée : iOS, détection de trajet, friction utilisateur, batterie

## Contexte

Guy a autorisé la localisation pour Viim mais ne voyait aucun trajet du jour dans l'Accueil.

Investigation sur l'iPhone réel :

- Autorisation iOS confirmée : `authorizedAlways`.
- Base locale copiée depuis le conteneur app : `ZTRIP=0`, `ZTRIPEVENT=0`, `ZDAILYSUMMARY=0`.
- Logs initiaux : Viim démarrait `CoreMotion`, mais un réveil passif pouvait promouvoir le GPS continu même si le téléphone était immobile.

Le problème n'était donc pas l'affichage des trajets. Aucun trajet n'avait été persisté. iOS ne permet pas de reconstruire rétroactivement un parcours que l'app n'a pas collecté.

## Décision

Viim garde une écoute légère via `startMonitoringSignificantLocationChanges` quand l'autorisation `Always` est disponible.

Cette écoute passive ne démarre pas systématiquement le GPS continu. Elle est promue vers `startUpdatingLocation` uniquement si le point reçu indique un mouvement réel :

- vitesse résolue au-dessus du seuil de départ de trajet ;
- ou déplacement significatif depuis le dernier point accepté.

Quand le téléphone redevient immobile avec un trajet actif, Viim finalise le trajet après un délai court et persiste le trajet si la distance ou la durée dépasse le seuil minimal.

## Conséquences

- L'Accueil affiche `Réveil automatique actif` au repos au lieu de laisser croire que rien n'est prêt.
- Le GPS continu ne démarre plus à l'arrêt sur un point initial de localisation.
- Un nouveau déplacement doit désormais déclencher la collecte puis alimenter les trajets d'aujourd'hui.
- Un trajet effectué avant cette correction ne peut pas être recréé sans données GPS déjà collectées.

## Vérification

- `xcodebuild test` simulateur : OK.
- Build signé iPhone réel : OK.
- Installation iPhone réel : OK.
- Logs iPhone après correctif : `location.authorization state=authorizedAlways`, `location.passiveWakeups.start`, `location.passiveWakeup.ignored count=1`, `motion.phase stationary`.
