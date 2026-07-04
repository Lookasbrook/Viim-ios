# Résultats de tests

Format d'entrée : date, scénario (S1…S6 du test-plan), appareil, véhicule, résultat, mesures, notes.

| Date | Scénario | Appareil | Véhicule | Résultat | Mesures | Notes |
|---|---|---|---|---|---|---|
| 2026-07-03 | TRIP-003 diagnostic | iPhone de Guy | Voiture | OK diagnostic / OK correctif à l'arrêt | CoreData appareil : `ZTRIP=0`, `ZTRIPEVENT=0`, `ZDAILYSUMMARY=0`; logs finaux : `authorizedAlways`, `location.passiveWakeups.start`, `location.passiveWakeup.ignored count=1`, `motion.phase stationary` | Confirme que l'absence de données venait d'une absence de trajet persisté, pas d'un bug d'affichage. Roulage réel nécessaire pour valider la création d'un nouveau trajet après correctif. |
| 2026-07-03 | S1 préflight | iPhone de Guy | Non roulant | OK partiel | Build signé OK, installation OK, lancement `com.yamstack.viim` OK | `LocationService` intégré ; le roulage 20 min écran verrouillé reste à exécuter pour valider la continuité GPS réelle. |

Les seuils calibrés (accéléromètre, collision) validés sur le terrain sont documentés ici puis reportés dans `architecture/sensor-algorithms.md`.
