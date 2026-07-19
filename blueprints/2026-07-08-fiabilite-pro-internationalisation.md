# Blueprint — Fiabilité des données niveau assureur + internationalisation - 2026-07-08

## Objectif produit

Amener Viim au niveau des apps télématiques des assureurs québécois (Intact « Ma conduite », Desjardins « Ajusto », CAA) :

- Détection de trajets ≥ 95 % (aucun trajet réel perdu, aucun faux trajet).
- Distance avec erreur ≤ 5 % vs odomètre sur roulages de validation.
- Score de conduite multi-critères (vitesse, freinage, accélération, distraction) qui s'améliore avec les données collectées.
- App adaptée à la position de l'utilisateur (pas seulement Burkina) : devise choisie par l'utilisateur, téléphone international, limites adaptées.
- Message WhatsApp de test réellement REMIS, pas seulement « accepté » par un agent conversationnel.

**Définition de « fiabilité 9/10 »** (critères de sortie mesurables, section finale) : rien n'est déclaré terminé sans preuve terrain consignée dans `qa/test-results.md`.

---

## Diagnostic — incohérences constatées dans le code actuel

Chaque point ci-dessous est une preuve lue dans le code, pas une hypothèse.

### D1 — La persistance des trajets dépend d'une vue SwiftUI (perte de données structurelle) 🔴

`ios/Viim/App/ViimApp.swift:59-61` : le seul chemin de persistance d'un trajet terminé est
`.onChange(of: locationService.lastCompletedTrip?.id)` dans `AppLaunchView`. Conséquences :

- Si iOS suspend/tue l'app pendant un trajet (cas normal en arrière-plan), le trajet actif n'existe **que en mémoire** (`LocationService.activeTrip`, `routeSamples`) : tout est perdu au kill. Aucun journal disque.
- Si le trajet se termine pendant que l'app est relancée en arrière-plan par un réveil localisation, rien ne garantit que la hiérarchie SwiftUI et son `.onChange` soient vivants au bon moment.
- `routeSamples` est lu au moment du `.onChange` : si un 2e trajet démarre avant que la persistance du 1er ne s'exécute, les échantillons ne correspondent plus au trajet persisté (course condition).

C'est la première cause du « nombre de trajets faux / km manquants ». Les apps assureurs écrivent chaque échantillon sur disque au fil de l'eau (journal write-ahead), jamais en fin de trajet uniquement.

### D2 — Fin de trajet impossible en arrière-plan profond 🔴

- `LocationService.updateActiveTripStopDetection` a besoin de **recevoir des échantillons** sous 3 km/h pendant 5 min. Or, moteur coupé et téléphone immobile, iOS cesse d'envoyer des points (distanceFilter 10 m) : la condition ne se déclenche jamais toute seule.
- Le filet de sécurité est `AppLaunchView.scheduleStationaryTripFinalization` (`ViimApp.swift:115-133`) : un `Task.sleep(90 s)` déclenché par `CMMotionActivityManager`. En arrière-plan suspendu, ni les updates CoreMotion ni ce `Task.sleep` ne s'exécutent. Un trajet réel peut donc rester « actif » des heures, puis être fusionné avec le trajet suivant (distance et durée gonflées) ou perdu.
- `finishActiveTripAfterStationaryMotion` (`LocationService.swift:228-242`) : si le trajet est trop court, il log `ignored` et **ne clôt pas** le trajet actif ; le GPS continue de tourner (batterie) et le mini-trajet zombie contamine le trajet suivant.

### D3 — Un seul segment GPS invalide rejette tout le trajet (contradiction interne) 🟠

- `TripMetricsCalculator.distanceMetric` (`TripReliability.swift:222-234`) : au **premier** segment à vitesse impossible, retour `.missing(.needsReview, .impossibleSpeed)` → `TripManager.persistCompletedTrip` refuse le trajet entier.
- Or `TripQualityEngine` (`TripQualityEngine.swift:105-117`) tolère jusqu'à 20 % de segments rejetés. Cette tolérance ne sert à rien : `persistabilityMetric` échoue avant que le quality engine ne soit consulté.
- Résultat : un seul glitch GPS (fréquent en ville) supprime un trajet réel de 20 km → « nombre de trajets faux, distance douteuse ». Le bon comportement : **sauter** le segment invalide, compter les segments rejetés, et laisser le quality engine décider (≤ 20 % → accepté).

### D4 — Le « score de conduite » est en réalité un score vitesse-max uniquement 🟠

- `ScoreEngine` (`score-speed-v1`) ne calcule que `scoreVitesse` depuis la vitesse max GPS ; `scoreFluidite`, `scoreVigilance`, `scoreEco` sont `nil`, et le score global = score vitesse.
- Les limites sont fixes par type de véhicule (80/100/35 km/h) — pas la limite affichée de la route. Un excès réel à 70 en zone 50 n'est jamais pénalisé ; conduire à 95 sur autoroute à 100 est « parfait ».
- Aucun capteur accéléromètre exploité : pas de freinage brusque, pas d'accélération brusque, pas de virage agressif, pas de distraction téléphone — les 4 critères principaux des scores assureurs. `SensorService` (todo.md) n'a jamais été commencé.
- `ScoreEngine.scoreSpeedMetric` filtre la vitesse par `horizontalAccuracy`, mais ignore `CLLocation.speedAccuracy`, la vraie mesure de confiance de la vitesse iOS.

### D5 — Burkina codé en dur partout (bloque l'internationalisation) 🟠

- `ViimApp.swift:32` : `.environment(\.locale, Locale(identifier: "fr_BF"))` forcé.
- `TripManager.swift` (`DrivingValueFormatter.fcfaText`, `tripDateText`) : FCFA et locale `fr_BF` en dur.
- `VehicleFuelCatalog` : prix carburant en FCFA/L en dur (`defaultGasolinePriceFCFAPerLiter = 850`), champ CoreData `fuelFCFA`.
- `BurkinaPhoneNumber.swift` (iOS) et `backend/src/routes/alerts.js:4` (`/^\+226\d{8}$/`) : seuls les numéros +226 sont acceptés. Un utilisateur au Québec (+1) ne peut ni s'inscrire un contact, ni recevoir d'alerte.
- Numéros d'urgence `18`/`17` en dur dans Assistance.

### D6 — Le message WhatsApp « test » part vers un agent conversationnel, pas vers une API d'envoi 🔴

C'est la cause la plus probable de « l'agent converse, le message test ne fonctionne pas » :

- `backend/src/services/newagent.js:24-39` : le backend POSTe `{source, channel, kind, to, message, metadata}` sur **`NEWAGENT_URL` racine**, la même URL que le health check GET. Il n'existe aucun contrat d'API d'envoi documenté (pas de path `/send`, pas de schéma de réponse).
- Le seul critère de succès est `response.ok` (`newagent.js:41`). Si NEwAGENT-IA est un agent conversationnel, il répond HTTP 200 avec **une réponse de conversation** (il « converse ») sans jamais transmettre le message au numéro `to` sur WhatsApp. Le backend renvoie alors `{"status":"sent"}` et l'app iOS affiche un succès — alors que rien n'a été remis.
- Aucun `messageId` fournisseur n'est exigé ni stocké, aucune alerte n'est persistée en base (tables `trips` existent mais pas `alerts`), aucun accusé de remise, aucun retry. Impossible de distinguer « accepté », « envoyé », « remis », « échoué ».

### D7 — Aucune synchronisation : les données ne peuvent pas s'améliorer 🟠

- Le flag `synced` existe en CoreData mais aucun `SyncManager` n'existe ; le backend a des tables `trips`/`daily_summaries` mais aucune route `/v1/trips`.
- Conséquence : pas de recalcul serveur possible quand les formules de score s'améliorent, pas de télémétrie qualité agrégée, pas de détection de dérive GPS par flotte, pas de résumé WhatsApp quotidien (spec `features/backend-resume-whatsapp.md` non implémentable sans données serveur). La boucle « le produit s'améliore au fur et à mesure » n'a aucun support technique aujourd'hui.

### D8 — Culture de fausses victoires dans la documentation 🟡

Beaucoup d'entrées `✅ Résolu` sont validées uniquement par tests unitaires simulateur, jamais par le scénario terrain S1 (20 min écran verrouillé, `qa/test-plan.md`) qui n'a **jamais été exécuté** (GPS-101 toujours ouvert). Le builder doit cesser de déclarer « résolu » sans preuve terrain. Règle : toute correction du pipeline trajet reste `🟠 en validation` tant qu'un roulage réel documenté dans `qa/test-results.md` ne la confirme pas.

---

## Plan d'exécution pour le builder

Ordre strict : Phase A (arrêter de perdre des données) → B (message test) → C (score pro) → D (international) → E (sync + amélioration continue). Ne pas paralléliser A et C : C dépend des échantillons journalisés par A.

### Phase A — Zéro perte de trajet (crash-safe)

**A1. Journal de trajet sur disque (write-ahead).**
- Nouveau `ios/Viim/Persistence/ActiveTripJournal.swift` : dès `beginTrip`, créer un enregistrement CoreData `ActiveTripDraft` (id, startedAt, vehicleType) ; chaque échantillon accepté est appendé par lots (flush toutes les ~10 s ou 20 échantillons) dans `ActiveTripSample` (timestamp, lat, lon, speedKmh, horizontalAccuracy, speedAccuracy).
- `LocationService` ne garde plus la vérité en mémoire seule : `routeSamples` devient un cache de lecture du journal.
- À chaque lancement de l'app (y compris relance arrière-plan par iOS), `TripManager` vérifie s'il existe un `ActiveTripDraft` orphelin : le finaliser avec `endedAt = dernier échantillon en mouvement`, passer par le pipeline normal (persistabilité + quality + score), puis supprimer le draft. Test : tuer l'app en plein trajet simulé → le trajet est récupéré au lancement suivant.

**A2. Sortir la persistance de la vue SwiftUI.**
- Créer `ios/Viim/Services/TripRecorder.swift` (`@MainActor`, possédé par `ViimApp`, pas par une vue) qui observe `LocationService` (Combine/async sequence) et appelle `TripManager.persistCompletedTrip` avec les échantillons **du journal du trajet concerné** (par tripId, plus jamais `locationService.routeSamples` globaux).
- Supprimer `.onChange(of: lastCompletedTrip?.id)` et `persistLastCompletedTripIfNeeded` de `AppLaunchView`.

**A3. Fin de trajet robuste en arrière-plan.**
- Dans `LocationService`, ajouter un timeout d'inactivité : si aucun échantillon accepté depuis `stopSustainedDuration` (5 min) alors qu'un trajet est actif, clore à `lastMovingAt`. Implémentation : comparer à `lastUpdatedAt` à chaque nouvel événement (échantillon, réveil significatif, retour premier plan, relance d'app) — pas de timer suspendu.
- `finishActiveTripAfterStationaryMotion` : quand le trajet est trop court, **clore quand même l'état** (reset `activeTrip`, arrêt du GPS continu) au lieu de laisser un trajet zombie ; journaliser la décision dans la télémétrie qualité (`liveRejected`).
- Garder `startMonitoringSignificantLocationChanges` armé en permanence quand `authorizedAlways` (déjà fait) : c'est le mécanisme de relance d'app iOS.

**A4. Segments invalides : sauter, pas rejeter.**
- `TripMetricsCalculator.distanceMetric` : remplacer le retour `.missing(.impossibleSpeed)` au premier segment invalide par : ignorer le segment, incrémenter `rejectedSegmentCount`, continuer. Retourner la distance des segments valides + le compte de rejets (nouveau champ dans le retour ou métrique dédiée).
- La décision d'acceptation appartient au `TripQualityEngine` seul (tolérance 20 % déjà codée). `persistabilityMetric` ne doit plus échouer sur `impossibleSpeed`, seulement sur durée/points insuffisants.
- Mettre à jour `TripReliabilityTests` : un trajet de 50 segments avec 2 sauts GPS est persisté avec la distance des 48 segments valides ; un trajet avec 40 % de segments rejetés est refusé par le quality engine.

**A5. Vitesse : utiliser `speedAccuracy`.**
- Ajouter `speedAccuracy` à `LocationSample` (depuis `CLLocation.speedAccuracy`). Une vitesse n'est valide pour score/vitesse-max que si `speedAccuracy >= 0 && speedAccuracy <= 3 m/s` (en plus du filtre horizontalAccuracy actuel). Champ à journaliser (A1) et à persister dans les route points.

**Avancement 2026-07-09/10.**
- A1-A5 sont livrés côté logiciel et couverts par tests simulateur : `ActiveTripJournal`, `TripRecorder`, finalisation inactive, segments GPS invalides sautés, `speedAccuracy`, rapports qualité, réparation des vitesses max historiques.
- S1 terrain après deux trajets réels signalés est **échoué** : extraction iPhone `qa/artifacts/s1-20260709-after-maxspeed-repair-reanalysis`, `tripCount=6`, `localTripsTodayCount=0`, `activeDraftCount=0`, `activeSampleCount=0`, dernier trajet persisté `2026-07-08T23:11:41Z`, âge dernier trajet `25.55 h`.
- Conclusion précise : ces deux trajets ne sont pas dans la base et ne sont pas des drafts non finalisés ; ils ne peuvent pas être reconstruits rétroactivement. L'ancienne build n'avait pas encore de log persistant suffisant pour prouver si la cause exacte était l'absence de réveil iOS, l'absence de démarrage CoreMotion/GPS, ou une interruption avant début de journal.
- Correctif additionnel livré : log persistant `ViimDiagnostics.log`, comptage `activeSampleCount` dans l'outil S1, réparation interne `trip.maxSpeed.repaired count=6`. La build instrumentée est installée sur l'iPhone de Guy ; le prochain S1 doit être refait avec cette build avant de fermer Phase A.

**Critères d'acceptation Phase A**
- Kill de l'app en plein trajet (simulateur + iPhone réel) → trajet récupéré, distance calculée sur les échantillons journalisés.
- Un glitch GPS isolé ne supprime plus un trajet ; il apparaît dans `rejectedSegmentCount`.
- Scénario S1 du test-plan (20 min, écran verrouillé, iPhone réel) exécuté et consigné dans `qa/test-results.md` avec distance comparée à l'odomètre/Google Maps (écart cible ≤ 5 %). GPS-101 ne peut être fermé qu'avec cette preuve.

### Phase B — Message WhatsApp test réellement remis

**Avancement 2026-07-09.**
- Préparation backend livrée : `NEWAGENT_SEND_URL`/`NEWAGENT_HEALTH_URL`, succès conditionné à `providerMessageId`, table `alerts`, runner `npm run migrate`, retour `alertId`, statut consultable par `GET /v1/alerts/{id}`, blocage si `queued` ne peut pas être écrit, tests backend 13/13.
- Reste à faire pour fermer Phase B : configurer l'endpoint réel d'envoi en production, exécuter la migration, déployer, envoyer un vrai message vers un téléphone consenti, puis consigner capture + ligne `alerts.provider_message_id` dans `qa/test-results.md`.

**B1. Clarifier le contrat NEwAGENT (action PO + builder).**
- Documenter dans `architecture/api-endpoints.md` le vrai contrat d'envoi de NEwAGENT-IA : URL exacte de l'endpoint **d'envoi sortant** (distinct de l'inbox conversationnelle), schéma de requête, schéma de réponse avec `messageId`, codes d'erreur. Si NEwAGENT-IA n'expose pas d'endpoint d'envoi sortant vers un numéro arbitraire, le dire explicitement et brancher un provider WhatsApp Business API (Meta Cloud API ou Twilio) à la place — ne pas continuer à espérer qu'un agent conversationnel fasse du dispatch.
- Config : remplacer `NEWAGENT_URL` unique par `NEWAGENT_SEND_URL` + `NEWAGENT_HEALTH_URL` dans `backend/src/config.js`.

**B2. Exiger une preuve d'envoi.**
- `backend/src/services/newagent.js` : le succès exige HTTP 2xx **et** un corps JSON contenant un identifiant de message (`messageId`/`id`). Réponse 200 sans messageId (réponse conversationnelle) = échec `provider_no_message_id`, loggé avec les 500 premiers caractères du corps (scrubbed) pour diagnostic.
- Runbook curl dans `qa/test-plan.md` : commande de test direct de l'endpoint d'envoi avec un numéro consenti, réponse attendue.

**B3. Persister et suivre les alertes.**
- Migration Postgres : table `alerts` (id, kind, to_e164, message, status `queued|sent|delivered|failed`, provider_message_id, provider_error, created_at, updated_at).
- `/v1/alerts/*` : insérer `queued` avant l'appel provider, mettre à jour selon le résultat, retourner `{status, alertId, providerMessageId}`.
- Webhook `/v1/webhooks/whatsapp-status` (si le provider le supporte) pour passer à `delivered`.
- iOS `AssistanceView` : après le test, afficher « Envoyé — en attente de remise » puis confirmer/échouer selon le statut (poll `GET /v1/alerts/:id` simple pour commencer).

**Critères d'acceptation Phase B**
- Un vrai message WhatsApp reçu sur un téléphone consenti, capture d'écran consignée dans `qa/test-results.md`, avec `providerMessageId` correspondant en base.
- Une réponse conversationnelle du provider n'est plus jamais comptée comme envoi réussi (test unitaire backend avec un mock qui renvoie 200 + texte de chat).

### Phase C — Score de conduite niveau assureur

**C1. `SensorService` (accéléromètre).**
- Nouveau `ios/Viim/Services/SensorService.swift` : `CMDeviceMotion` à 10-20 Hz uniquement pendant un trajet actif (piloté par `TripRecorder`), `userAcceleration` projetée sur l'axe de déplacement (via `course` GPS ou attitude).
- Événements détectés, chacun avec seuil ET durée soutenue (jamais un pic isolé, même règle que l'excès de vitesse 10 s existant) :
  - Freinage brusque : décélération longitudinale ≤ −0,35 g pendant ≥ 1 s.
  - Accélération brusque : ≥ +0,30 g pendant ≥ 1 s.
  - Virage agressif : accélération latérale ≥ 0,4 g pendant ≥ 1 s.
- Événements journalisés dans `TripEvent` (table CoreData existante) avec timestamp, type, intensité, vitesse GPS au moment de l'événement.

**C2. Distraction téléphone.**
- Pendant un trajet actif : détecter la manipulation du téléphone (variation d'attitude `CMDeviceMotion` + `UIScreen`/scene active) au-dessus de ~20 km/h. Compter les secondes de manipulation. C'est le critère le plus prédictif chez les assureurs — le livrer avant l'éco-conduite.

**C3. `ScoreEngine` v2 (`score-v2`).**
- Sous-scores 0-100 : vitesse (30 %), freinage (25 %), accélération (15 %), distraction (30 %). `scoreEco` reste hors score global tant que non calculé.
- Score global fiable seulement si tous les sous-scores pondérés existent ; sinon `partial` avec les raisons existantes (`ReliableMetric` déjà en place — le réutiliser tel quel).
- Recalcul rétroactif : conserver les événements bruts par trajet pour pouvoir recalculer les scores quand la formule change (versionnée — champ `formulaVersion` déjà présent, `TripManager.recalculateHistoricalQualityReports` montre le pattern à suivre).
- Vitesse : à court terme, garder les seuils par type de véhicule mais **marquer explicitement le sous-score vitesse `partial` (raison `speedLimitUnknown`, nouvelle)** tant que la limite réelle de la route n'est pas connue. Phase E ajoutera les limites réelles ; ne jamais prétendre mesurer « excès de vitesse » sans limite de référence.

**Critères d'acceptation Phase C**
- Roulage de validation : 3 freinages brusques volontaires (parking vide) → 3 événements détectés, 0 faux positif sur un trajet calme de 20 min. Consigner dans `qa/test-results.md`.
- Un trajet avec téléphone manipulé 2 min à l'arrêt (feu rouge) n'est pas pénalisé ; manipulé en roulant, il l'est.

### Phase D — Internationalisation

**D1. Locale.**
- Supprimer `.environment(\.locale, Locale(identifier: "fr_BF"))` de `ViimApp.swift` ; supprimer les `Locale(identifier: "fr_BF")` de `DrivingValueFormatter`. Utiliser la locale du device partout.

**D2. Devise choisie par l'utilisateur.**
- Onboarding + Paramètres : sélection de la devise pour l'estimation carburant (défaut = devise de la région du device via `Locale.currency`, ex. XOF au Burkina, CAD au Québec) et prix du carburant par litre saisi/éditable par l'utilisateur avec valeur par défaut régionale.
- Modèle : remplacer `fuelFCFA: Int` par `fuelCostMinorUnits: Int` + `fuelCurrencyCode: String` (migration CoreData légère ; les anciens enregistrements deviennent `XOF`). `VehicleFuelCatalog` ne stocke plus de prix : il ne fournit que `litersPer100Km` ; le prix vient du profil utilisateur. Renommer `fcfaText` en `fuelCostText(amount:currency:)` avec `Locale`-aware formatting.
- Le coût reste marqué `partial/estimé` (déjà le cas) tant qu'aucune calibration plein-réel n'existe.

**D3. Téléphones internationaux.**
- iOS : remplacer `BurkinaPhoneNumber` par un validateur E.164 générique (préfixe pays sélectionnable, défaut selon la région du device ; garder la normalisation locale 8 chiffres → +226 quand région = BF).
- Backend `alerts.js` : remplacer `/^\+226\d{8}$/` par une validation E.164 (`/^\+[1-9]\d{6,14}$/`) ; adapter les tests.
- Numéros d'urgence par pays : petit catalogue (BF : 18/17 ; CA/US : 911 ; défaut : 112) selon la région, utilisé par Assistance.

**Critères d'acceptation Phase D**
- Device réglé en fr_CA : montants affichés en CAD, contact +1514… accepté de bout en bout (onboarding → backend 200), urgences affichent 911.
- Device en fr_BF : comportement actuel inchangé (XOF, +226, 18/17).

### Phase E — Sync et amélioration continue

**E1. `SyncManager` iOS.**
- File d'upload : trajets `synced == false` (+ événements + rapports qualité) → `POST /v1/trips/batch` idempotent (clé = tripId UUID), déclenché quand `NetworkStatusService.isOnline` passe à true et après chaque persistance. Marquer `synced = true` uniquement sur 200 avec accusé par tripId.
- Ne jamais afficher de statut de sync sans ce moteur (règle `data-reliability.md` déjà écrite).

**E2. Backend trajets.**
- Routes `POST /v1/trips/batch` (upsert idempotent), `GET /v1/users/:id/summary`. Auth minimale par token device (à définir avec le PO — pas de données trajet sans authentification).
- Job quotidien 20h00 UTC : résumé WhatsApp selon `features/backend-resume-whatsapp.md`, qui devient enfin implémentable.

**E3. Boucle d'amélioration (le « ça s'améliore au fur et à mesure »).**
- La télémétrie qualité (`TripQualityTelemetryRecord`, déjà codée côté iOS) est incluse dans le batch sync. Dashboard/inspection SQL simple : taux de rejet par raison, précision GPS p95 par appareil, dérive dans le temps.
- Confirmation utilisateur : après chaque trajet, permettre « c'était bien vous qui conduisiez ? la distance est-elle correcte ? » (conducteur vs passager vs bus — les assureurs le font tous). Réponses stockées et synchronisées : c'est la vérité terrain qui permet d'ajuster les seuils (`TripQualityLearningEngine` existe déjà — le brancher sur ces labels au lieu des seules auto-évaluations).
- Limites de vitesse réelles : intégrer une source de limites (OSM/`speedLimit` via map-matching serveur sur la polyline synchronisée) et recalculer `scoreVitesse` côté serveur avec la formule versionnée. C'est le chemin vers un vrai score « excès de vitesse » sans rien inventer côté device.

**Critères d'acceptation Phase E**
- Un trajet fait hors ligne apparaît en base Postgres < 1 min après retour réseau ; re-sync du même trajet n'insère pas de doublon.
- Un changement de version de formule de score déclenche un recalcul serveur traçable (ancien et nouveau score conservés).

---

## Règles de travail imposées au builder

1. **Aucune déclaration « Résolu » sans preuve terrain.** Tests unitaires = nécessaire, jamais suffisant pour le pipeline trajet. Chaque fix GPS/trajet reste ouvert tant qu'un roulage réel documenté (date, appareil, distance odomètre vs app) n'est pas dans `qa/test-results.md`.
2. **Jamais de valeur inventée.** Les règles de `data-reliability.md` restent la loi : toute nouvelle métrique passe par `ReliableMetric` avec source, formule versionnée et raison d'absence.
3. **Une phase = un cycle.** Ne pas commencer C avant que les critères d'acceptation de A soient prouvés.
4. **Toute modification de formule** (score, distance, qualité) incrémente `formulaVersion` et ajoute un test de non-régression sur données archivées.
5. Mettre à jour `qa/known-issues.md` : ouvrir `DATA-001` (D1/D2 perte de trajets), `DATA-002` (D3 rejet trajet entier), `WA-103` (D6 agent conversationnel ≠ API d'envoi), `INTL-001` (D5), et lier chaque phase à son entrée.

## Définition de « fiabilité 9/10 » (critères de sortie globaux)

| Mesure | Cible | Preuve exigée |
|---|---|---|
| Trajets réels capturés | ≥ 95 % sur 20 trajets de validation | Journal de roulage vs app, `qa/test-results.md` |
| Faux trajets | 0 sur 7 jours d'usage normal | Revue des trajets avec l'utilisateur |
| Erreur distance | ≤ 5 % vs odomètre | 5 roulages comparés |
| Vitesse max affichée | Jamais > vitesse réelle + 10 % | Roulage à vitesse contrôlée |
| Message test WhatsApp | Remis avec `providerMessageId` | Capture + ligne en base |
| Statuts UI | 0 statut affirmant une capacité absente du code | Audit grep + revue |
| Score | Multi-critères, recalculable, versionné | Recalcul rétroactif démontré |
| International | Parcours complet OK en fr_CA et fr_BF | Test manuel des deux régions |
