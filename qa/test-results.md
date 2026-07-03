# Résultats de tests

Format d'entrée : date, scénario (S1…S6 du test-plan), appareil, véhicule, résultat, mesures, notes.

| Date | Scénario | Appareil | Véhicule | Résultat | Mesures | Notes |
|---|---|---|---|---|---|---|
| 2026-07-03 | S1 préflight | iPhone de Guy | Non roulant | OK partiel | Build signé OK, installation OK, lancement `com.yamstack.viim` OK | `LocationService` intégré ; le roulage 20 min écran verrouillé reste à exécuter pour valider la continuité GPS réelle. |

Les seuils calibrés (accéléromètre, collision) validés sur le terrain sont documentés ici puis reportés dans `architecture/sensor-algorithms.md`.
