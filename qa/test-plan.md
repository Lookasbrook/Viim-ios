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

#### S1 — Procédure instrumentée Viim

Préflight déjà automatisable :

```sh
xcrun devicectl list devices
xcodebuild -project ios/Viim.xcodeproj -scheme Viim -destination 'platform=iOS,name=iPhone de Guy' -derivedDataPath /private/tmp/viim-dd-s1-real build
xcrun devicectl device install app --device E21236A8-1735-5EB6-9A8D-E41C165B962E /private/tmp/viim-dd-s1-real/Build/Products/Debug-iphoneos/Viim.app
xcrun devicectl device process launch --device E21236A8-1735-5EB6-9A8D-E41C165B962E com.yamstack.viim
```

Roulage réel :

1. Ouvrir Viim une fois, vérifier que le profil est terminé et que la localisation iOS est autorisée.
2. Lancer le parcours de référence dans Google Maps ou noter l'odomètre au départ.
3. Verrouiller l'écran immédiatement.
4. Rouler au moins 20 minutes.
5. Noter distance Google Maps/odomètre et heure de départ/arrivée.
6. Attendre la finalisation du trajet dans Viim après arrêt.

Extraction et rapport :

```sh
python3 tools/qa/s1_trip_report.py \
  --device E21236A8-1735-5EB6-9A8D-E41C165B962E \
  --reference-km 12.34
```

Si `devicectl` perd le tunnel CoreDevice ou si l'iPhone n'est plus connecté :

1. Ouvrir Xcode > Window > Devices and Simulators.
2. Sélectionner l'iPhone.
3. Sélectionner Viim dans Installed Apps.
4. Utiliser `Download Container...`.
5. Lancer le rapport sur le store exporté :

```sh
python3 tools/qa/s1_trip_report.py \
  --store "/path/to/Viim.xcappdata/AppData/Library/Application Support/Viim.sqlite" \
  --reference-km 12.34
```

Le script copie `Library/Application Support/Viim.sqlite` depuis le conteneur de l'app, puis écrit :

- `s1-trip-report.json`
- `s1-trip-report.md`

Critères de passage S1 :

- `tripCount >= 1`.
- `activeDraftCount == 0` après finalisation.
- Distance Viim vs référence : écart ≤ 5 %.
- `routePointCount` cohérent avec 20 min de trajet.
- `rejectedSegmentCount / (validSegmentCount + rejectedSegmentCount) <= 0.2`.
- Si l'app est tuée pendant le trajet, le prochain lancement récupère le brouillon et persiste le trajet ou consigne un rejet qualité.

#### Variantes obligatoires depuis DATA-003 (cf. blueprint 2026-07-09)

- **S1-A — premier plan puis écran verrouillé** : procédure ci-dessus telle quelle. Fonctionne désormais aussi en autorisation `Pendant l'utilisation` (indicateur bleu système attendu — c'est le comportement iOS normal, pas un bug).
- **S1-B — app non ouverte avant le départ** (exige autorisation `Toujours`) : sans lancer Viim, faire un trajet ≥ 5 km, attendre 10 min à l'arrêt, puis ouvrir Viim. Attendu : trajet présent via `location.passiveWakeup.promote` (réveil significatif) ou récupéré du journal (`trip.recorder.recovered`). Si le GPS a été promu à tort sans trajet, le log doit montrer `location.idleFailsafe.stop` ≤ 3 min après la promotion.
- **S1-C — app tuée en plein trajet** : démarrer app ouverte, tuer Viim depuis le sélecteur à mi-trajet, finir le trajet, rouvrir Viim. Attendu : portion pré-kill récupérée (`trip.recorder.recovered`), aucun trajet fantôme, aucun doublon.

### S2A — Preuve d'envoi WhatsApp provider

Avant de tester la collision, prouver que l'endpoint d'envoi sortant remet vraiment un message WhatsApp.

Préparer :

```sh
export VIIM_API_BASE="https://api.burktech-ia.com"
export TEST_PHONE_E164="+22670000000"
```

Préflight backend production :

```sh
npm run migrate --prefix backend
```

Test backend Viim :

```sh
curl -sS -X POST "$VIIM_API_BASE/v1/alerts/test" \
  -H "Content-Type: application/json" \
  -d "{\"driverName\":\"Viim QA\",\"contact\":{\"name\":\"QA\",\"phoneNumber\":\"$TEST_PHONE_E164\"}}"
```

Réponse attendue :

```json
{"status":"sent","alertId":"...","providerMessageId":"...","providerStatus":202}
```

Vérifier le statut interne :

```sh
curl -sS "$VIIM_API_BASE/v1/alerts/{alertId}"
```

Critères de passage S2A :

- Le téléphone consenti reçoit réellement le message WhatsApp.
- La réponse contient `alertId` et `providerMessageId`.
- `GET /v1/alerts/{alertId}` retourne `status: "sent"` avec le même `providerMessageId`.
- Une capture du message reçu et la ligne backend correspondante sont consignées dans `qa/test-results.md`.
- Si le provider répond `2xx` sans `providerMessageId`, le backend doit retourner `503 newagent_unavailable`.

### S2 — Collision simulée (protocole sécurisé)
1. Véhicule à l'arrêt, secousse violente du téléphone après roulage (ou chute contrôlée sur coussin).
2. Attendu : notification 60 s → sans réponse → WhatsApp contact 1 < 90 s après expiration, position exacte, fiche médicale incluse.
3. Répondre OUI dans les 60 s → aucune alerte envoyée, événement loggé.
4. Couper le WiFi/data → SMS fallback proposé.

### S3 — Score immédiat
1. Nouvel utilisateur : effectuer un premier trajet détecté automatiquement.
2. Attendu : le trajet du jour est visible, avec distance, durée et score GPS estimé.
3. Backend futur : les agrégats communautaires restent opt-in et ne doivent jamais bloquer le score personnel.

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
