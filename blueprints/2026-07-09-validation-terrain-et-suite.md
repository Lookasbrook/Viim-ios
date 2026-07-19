# Blueprint — Validation terrain DATA-003, WhatsApp production, puis Phases C/D/E - 2026-07-09

## Contexte : ce qui vient d'être corrigé (ne pas refaire)

La Phase A du blueprint 2026-07-08 était livrée mais deux trajets réels du 2026-07-09 ont encore été perdus avec `activeDraftCount=0` : la détection ne démarrait jamais, le journal n'avait donc rien à récupérer. Trois causes racines ont été corrigées en session directe le 2026-07-09 (détail complet : `tracking/in-progress.md` § « Phase A bis » et `qa/known-issues.md` DATA-003) :

1. `LocationService.shouldPromotePassiveWakeup` : la promotion du réveil arrière-plan est maintenant possible à froid (elle était mathématiquement impossible avant), avec failsafe d'arrêt GPS après 3 min sans trajet.
2. `allowsBackgroundLocationUpdates` actif dès `WhenInUse` : le GPS ne se coupe plus au verrouillage d'écran en plein trajet.
3. Détection moto/fallback : CoreMotion n'est plus un point de blocage unique (moto = tout sauf marche/course ; autorisation refusée → détection GPS pure).
4. Câblage headless : `TripRecorder.observe/recover` vit dans `ViimApp.init`, plus dans une vue.
5. Distance : scan par ancre (un glitch = un seul segment rejeté, continuité conservée) partagé entre `distanceAnalysis`, le contrôle de démarrage et `TripQualityEngine`.

Interdiction : ne pas re-modifier `LocationService.shouldPromotePassiveWakeup`, le failsafe d'inactivité, ni `MotionActivityService.phase(for:)` sans données terrain qui prouvent un défaut.

---

## Étape 1 — Validation terrain S1 étendue (bloquant, avant tout le reste)

Objectif : prouver sur iPhone réel que plus aucun trajet n'est perdu. Trois scénarios, chacun consigné dans `qa/test-results.md` avec date, build, distance odomètre/Google Maps vs app, et extraction des logs `ViimDiagnostics`.

| Scénario | Procédure | Critère de succès |
|---|---|---|
| S1-A app au premier plan puis écran verrouillé | Ouvrir Viim, démarrer un trajet ≥ 3 km, verrouiller l'écran après 1 min, finir le trajet, attendre 10 min à l'arrêt | Trajet visible dans l'Accueil, distance à ±5 %, `trip.persisted` dans les logs |
| S1-B app en arrière-plan (non ouverte avant le départ) | Sans ouvrir Viim, faire un trajet ≥ 5 km, attendre 10 min à l'arrêt, ouvrir Viim | Trajet présent (via réveil significatif + promotion, ou récupéré du journal au lancement), logs `location.passiveWakeup.promote` ou `trip.recorder.recovered` |
| S1-C app tuée en plein trajet | Démarrer un trajet app ouverte, tuer Viim depuis le sélecteur d'apps à mi-trajet, finir le trajet, rouvrir Viim | Portion pré-kill récupérée depuis le journal (`trip.recorder.recovered`), aucun trajet fantôme |

Notes d'exécution :
- Vérifier avant S1-B que l'autorisation est bien `Toujours` (bouton « Activer l'arrière-plan » dans l'Accueil). Si le PO ne l'a pas accordée, le noter : c'est la limite iOS assumée, pas un bug.
- En WhenInUse, S1-A doit maintenant fonctionner (l'indicateur bleu système est normal et attendu) ; S1-B ne peut pas fonctionner sans `Toujours` — le documenter tel quel.
- Après chaque scénario : extraire `ViimDiagnostics` + compter `ZTRIP`, `ZACTIVETRIPDRAFT`, `ZACTIVETRIPSAMPLE`.
- Échec d'un scénario = STOP : consigner les logs bruts dans `qa/test-results.md`, rouvrir DATA-003 avec les preuves, ne pas passer à l'étape 2.

Si les trois passent : fermer DATA-003 et GPS-101 avec liens vers les preuves.

## Étape 2 — Test WhatsApp production (WA-103, bloquant)

Le logiciel est prêt (providerMessageId obligatoire, table `alerts`, `alertId` retourné). Reste l'exécution :

1. Appliquer la migration en production : `npm run migrate` sur le déploiement Coolify (vérifier que la table `alerts` existe : `\dt alerts`).
2. Confirmer avec le PO le vrai endpoint d'envoi sortant NEwAGENT (`NEWAGENT_SEND_URL`) distinct de l'inbox conversationnelle, et le documenter dans `architecture/api-endpoints.md` (schéma requête/réponse, champ contenant l'id de message). Si NEwAGENT ne fournit pas d'endpoint d'envoi avec id de message, escalader au PO : brancher Meta WhatsApp Cloud API ou Twilio à la place — ne pas simuler.
3. Test réel : `POST /v1/alerts/test` avec un contact consenti ; exiger la réception effective du message sur le téléphone (capture d'écran), `providerMessageId` non nul dans la réponse ET dans la table `alerts` (statut `sent`).
4. Consigner le tout dans `qa/test-results.md` ; fermer WA-103 seulement avec ces trois preuves.

## Étape 3 — Phase C : score multi-critères niveau assureur

Suivre la Phase C du blueprint `2026-07-08-fiabilite-pro-internationalisation.md` telle quelle (SensorService CMDeviceMotion 10-20 Hz pendant trajet actif uniquement, freinage ≤ −0,35 g soutenu ≥ 1 s, accélération ≥ +0,30 g, virage ≥ 0,4 g latéral, distraction téléphone > 20 km/h, ScoreEngine v2 pondéré 30/25/15/30, sous-score vitesse marqué `partial` avec nouvelle raison `speedLimitUnknown`). Précisions d'intégration avec le code actuel :

- Piloter le démarrage/arrêt de `SensorService` depuis `TripRecorder` (qui observe déjà `LocationService`), pas depuis une vue.
- Journaliser les événements capteur dans le journal actif (nouvelle entité `ActiveTripEvent` sur le modèle d'`ActiveTripSample`) pour qu'un kill d'app ne perde pas les événements ; les recopier dans `TripEvent` à la persistance.
- Événements bruts conservés par trajet pour recalcul rétroactif versionné (pattern `recalculateLegacyQualityReports` existant).
- Critères d'acceptation inchangés : 3 freinages volontaires détectés / 0 faux positif sur 20 min calmes, distraction à l'arrêt non pénalisée — consignés dans `qa/test-results.md`.

## Étape 4 — Phase D : internationalisation

Suivre la Phase D du blueprint 2026-07-08 (locale device, devise choisie avec `fuelCostMinorUnits` + `fuelCurrencyCode`, E.164 iOS + backend, urgences par pays). Rappels d'implémentation :

- Migration CoreData légère : anciens enregistrements `fuelFCFA` → `XOF`.
- Backend : remplacer `/^\+226\d{8}$/` par E.164 générique dans `alerts.js` + tests ; garder la normalisation 8 chiffres → `+226` quand la région device = BF.
- Critères : parcours complet OK en fr_CA (CAD, +1, 911) et fr_BF (XOF, +226, 18/17), testés manuellement et consignés.

## Étape 5 — Phase E : sync et amélioration continue

Suivre la Phase E du blueprint 2026-07-08 : `SyncManager` iOS (upload idempotent des trajets `synced == false` + télémétrie qualité), routes backend `POST /v1/trips/batch` avec auth device token, job résumé WhatsApp 20h00, labels de confirmation utilisateur (conducteur/passager, distance correcte) branchés sur `TripQualityLearningEngine`, et limites de vitesse réelles par map-matching serveur pour un vrai `scoreVitesse`.

## Règles de travail (inchangées, non négociables)

1. Aucune entrée « ✅ Résolu » sans preuve terrain consignée dans `qa/test-results.md` (les fixes GPS/trajet restent « 🟠 En validation » jusqu'au roulage réel).
2. Toute nouvelle métrique passe par `ReliableMetric` (source, formule versionnée, raison d'absence).
3. Une étape à la fois, dans l'ordre : 1 → 2 → 3 → 4 → 5. Les étapes 1 et 2 peuvent être menées en parallèle (terrain vs backend), pas les suivantes.
4. Toute modification de formule incrémente `formulaVersion` + test de non-régression sur données archivées.
