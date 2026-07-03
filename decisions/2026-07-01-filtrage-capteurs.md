# ADR — Filtrage capteurs : low-pass + confirmation GPS obligatoire

**Date** : 2026-07-01 · **Statut** : Accepté

## Contexte
Cible principale : motos sur routes dégradées de Ouagadougou. L'accéléromètre brut y est inutilisable (vibrations, nids-de-poule). Les solutions occidentales supposent des routes lisses et des voitures — c'est précisément ce qui les rend inadaptées ici.

## Décision
Double barrière anti-bruit :
1. **Filtre passe-bas** sur l'accéléromètre, alpha ≈ 0.15 pour moto (0.25 voiture, 0.20 vélo).
2. **Confirmation GPS systématique** : aucun événement comptabilisé sans variation de vitesse GPS > 5 km/h dans la même fenêtre de 2 s.

Complétée par une **calibration silencieuse** de 5 trajets par utilisateur (bruit de fond individuel, aucun score affiché, flag `calibration: true`).

## Justification
Le filtre seul ne suffit pas : un nid-de-poule traversé à vitesse constante produit un pic filtré crédible. La confirmation GPS élimine cette classe entière de faux positifs. La calibration individualise les seuils (téléphone en poche vs support guidon).

## Conséquences
- Latence de détection ~2 s (fenêtre GPS) — acceptable, l'affichage des événements n'est pas temps réel.
- Les seuils numériques finaux sont fixés sur le terrain (test-plan S5) et documentés dans `sensor-algorithms.md`.
- Métriques de validation : faux positifs collision < 10% (cible < 3%), détection freinages ≥ 75% (cible 90%).
