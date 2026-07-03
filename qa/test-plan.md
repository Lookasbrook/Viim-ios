# Plan de test — MVP fiabilité capteurs

Phase actuelle : groupe fermé (famille, amis) sur iPhone. Ce plan valide les capteurs, la sync et les alertes AVANT tout utilisateur externe.

## Métriques de sortie de phase

| Métrique | Seuil minimum | Seuil cible | Protocole |
|---|---|---|---|
| Précision GPS (trajet fidèle) | 85% | 95% | Comparer polyline vs trajet réel connu (10 trajets référence, moto + voiture) |
| Faux positifs collision | < 10% | < 3% | 20 trajets sur routes dégradées sans collision réelle ; compter les déclenchements |
| Précision détection freinages | 75% | 90% | Trajets scriptés : X freinages volontaires marqués manuellement vs détectés |
| Consommation batterie | < 20% / 2h | < 12% / 2h | Trajet continu 2h, batterie 100% au départ, mode normal puis mode éco |
| Sync offline→online | 100% | 100% | Mode avion pendant 3 trajets → réactiver → vérifier intégrité backend |
| Uptime backend | 99% | 99.9% | Uptime Robot sur /health, fenêtre 30 jours |
| Réception alertes WhatsApp | 90% | 99% | 30 tests répartis sur 2 semaines (bouton test + collisions simulées) |

## Scénarios de test critiques

### S1 — Background GPS
1. Démarrer un trajet, verrouiller l'écran immédiatement, rouler 20 min.
2. Attendu : trajet complet enregistré, aucune coupure de polyline.
3. Variante : app tuée manuellement pendant le trajet → relance et comportement documentés.

### S2 — Collision simulée (protocole sécurisé)
1. Véhicule à l'arrêt, secousse violente du téléphone après roulage (ou chute contrôlée sur coussin).
2. Attendu : notification 60 s → sans réponse → WhatsApp contact 1 < 90 s après expiration, position exacte, fiche médicale incluse.
3. Répondre OUI dans les 60 s → aucune alerte envoyée, événement loggé.
4. Couper le WiFi/data → SMS fallback proposé.

### S3 — Calibration
1. Nouvel utilisateur : vérifier qu'aucun score n'apparaît sur les trajets 1-5.
2. Backend : trajets reçus avec `calibration: true`, exclus de `/community/averages`.
3. Trajet 6 : score affiché.

### S4 — Sync différée
1. Mode avion, 3 trajets, vérifier stockage local (`synced: false`).
2. Réseau rétabli : sync automatique sans action utilisateur, aucun doublon (idempotence `trip.id`), résumé du jour correct.

### S5 — Bruit moto
1. Même parcours dégradé effectué en moto et en voiture.
2. Comparer les taux d'événements : la moto ne doit pas générer significativement plus de faux événements (validation alpha=0.15 + confirmation GPS).

### S6 — Résumé WhatsApp 20h
1. Conduire dans la journée → message entre 20h00 et 20h05.
2. Journée sans trajet → aucun message. STOP → plus de message.

## Prérequis avant premier testeur externe

- [ ] Uptime Robot configuré sur `https://api.burktech-ia.com/health` (5 min, alerte SMS + WhatsApp).
- [ ] S1, S2, S4 passés au seuil minimum.
- [ ] `known-issues.md` sans bug bloquant ouvert.

## Journal

Les résultats sont consignés dans [test-results.md](test-results.md), les bugs dans [known-issues.md](known-issues.md).
