# Fiabilité des statuts affichés et du score de conduite - 2026-07-06

## Résumé court

Deux catégories de problèmes distinctes expliquent pourquoi les données affichées dans l'app ne sont pas fiables aujourd'hui.

1. **Statuts codés en dur qui affirment qu'une fonctionnalité de sécurité tourne, alors qu'elle n'existe pas dans le code.** C'est le problème le plus grave : ce n'est pas un placeholder honnête, c'est un faux positif de sécurité.
2. **Score de conduite jamais calculé.** Le compteur de calibration (0/5 -> 5/5) fonctionne, mais aucun moteur ne calcule de score ensuite. Les `--` resteront affichés indéfiniment, même après des centaines de trajets. Les textes actuels sont honnêtes ("apparaîtra après calibration") mais deviennent trompeurs si rien n'est fait après le 5e trajet.

Une troisième catégorie (cascade d'alerte incomplète) est déjà trackée sous `ASSIST-003` dans `qa/known-issues.md` ; ce blueprint ne la reprend que pour mémoire au step 5.

## Preuves dans le code

### Statuts codés en dur (TRUST)

- `ios/Viim/Features/Accueil/AccueilView.swift:55-60` : `HomeStatusRow` pour `home.status.collisionDetection` reçoit `detailKey: "status.enabled"` en littéral, avec `tint: ViimColors.success` (vert), sans aucune liaison à un état réel.
- Recherche confirmée : aucun fichier `CollisionDetector` ni classe contenant `Collision` dans `ios/Viim` (`grep -rl "CollisionDetector" ios/Viim` -> vide). `tracking/todo.md:30` liste `[ ] CollisionDetector + fenêtre annulation 60 s` toujours non coché.
- `ios/Viim/Features/Accueil/AccueilView.swift:67-73` : `HomeStatusRow` pour `home.status.network` reçoit `detailKey: "status.offlineReady"` en littéral, avec `tint: ViimColors.warning`, sans lien avec la connectivité réelle.
- Recherche confirmée : aucun `NWPathMonitor` dans `ios/Viim` (`grep -rl "NWPathMonitor" ios/Viim` -> vide). `tracking/todo.md:26` liste `[ ] SyncManager : NWPathMonitor, /trips/batch idempotent` toujours non coché.

### Score de conduite jamais calculé (SCORE)

- `ios/Viim/Persistence/TripStore.swift:93` : à chaque trajet persisté, `object.setValue(nil, forKey: "score")` est écrit explicitement. Idem `scoreVitesse`, `scoreFluidite`, `scoreVigilance`, `scoreEco` (lignes 94-97) : toujours `nil`.
- `ios/Viim/Persistence/TripStore.swift:191-193` : `avgScore` est calculé à partir de `records.compactMap(\.score)` ; comme `score` est toujours `nil`, `scoreValues` est toujours vide et `avgScore` reste toujours `nil`.
- `ios/Viim/Services/TripManager.swift:92-93` : `scoreText(_:)` retourne `format.score.empty` (`"--"`) tant que `score == nil`, donc pour toujours dans l'état actuel.
- `tracking/todo.md:24` : `[ ] ScoreEngine : 5 critères + score global + couleur polyline` — jamais commencé.
- `ios/Viim/Features/Conduite/ConduiteView.swift:63-86` : les trois `DrivingCriterionCard` (vitesse, fluidité, vigilance) ont `progress: 0` codé en dur, cohérent avec l'absence de moteur de score.

## Causes classées

### TRUST-001 - "Détection de collision : Activé" est un faux statut

Statut : bloquant pour la confiance utilisateur, avant tout testeur externe.

L'app affiche une pastille verte "Activé" pour une fonctionnalité de sécurité qui n'a jamais été implémentée. Un utilisateur peut raisonnablement croire qu'un accident déclenchera une alerte automatique, ce qui est faux aujourd'hui.

Fix builder :

1. Ajouter un état réel `collisionDetectionEnabled: Bool` dans `TripManager` ou un futur `CollisionDetector`, initialisé à `false` tant que `CollisionDetector` n'existe pas.
2. Dans `AccueilView.swift`, remplacer le `detailKey` littéral par un binding sur cet état :
   - Si non implémenté/actif : `detailKey: "status.pendingCalibration"` (ou une nouvelle clé `home.status.collisionDetection.pending`), `tint: ViimColors.blue` (pas vert).
   - Ne repasser en `status.enabled` / vert que lorsque `CollisionDetector` détecte réellement un choc et déclenche la cascade d'alerte.
3. Ajouter une chaîne `home.status.collisionDetection.pending` = "Pas encore actif" (ou équivalent honnête) dans `Localizable.strings`.
4. Ne pas livrer `CollisionDetector` dans ce blueprint : ce fix corrige uniquement le mensonge d'affichage. L'implémentation réelle de la détection de collision reste un chantier séparé (cf. `tracking/todo.md` Phase 3).

### TRUST-002 - "Connexion réseau : Prêt hors ligne" ne reflète rien de réel

Statut : majeur, même logique que TRUST-001 mais moins critique en sécurité.

Fix builder :

1. Créer un petit service `NetworkStatusService` basé sur `NWPathMonitor` (`import Network`), exposant `@Published var isOnline: Bool`.
2. Injecter ce service en `@EnvironmentObject` comme les autres services (`LocationService`, `MotionActivityService`).
3. Dans `AccueilView.swift`, binder `detailKey` sur `isOnline` :
   - `true` -> `"status.online"` (nouvelle clé, ex. "Connecté"), `tint: ViimColors.success`.
   - `false` -> garder `"status.offlineReady"` (le texte actuel reste correct dans ce cas précis), `tint: ViimColors.warning`.
4. Ajouter la clé `status.online` = "Connecté" dans `Localizable.strings`.

### SCORE-001 - Les `--` de score ne disparaîtront jamais sans ScoreEngine

Statut : majeur, cohérence produit avant d'annoncer "calibration terminée" à un utilisateur.

Fix builder (portée minimale, pas le ScoreEngine complet à 5 critères de la Phase 2) :

1. Implémenter un `ScoreEngine` minimal qui calcule, à la fin de chaque trajet dans `TripManager.persistCompletedTrip`, au moins :
   - `scoreVitesse` : pénalité si `maxSpeedKmh` dépasse un seuil par type de véhicule.
   - `scoreFluidite` : à défaut de données d'accéléromètre exploitées aujourd'hui, peut rester `nil` explicitement tant que `SensorService` (todo.md ligne 16) n'existe pas — mais alors ne pas l'inclure dans le calcul du score global pour éviter de fausser la moyenne.
   - `score` global : moyenne pondérée des sous-scores disponibles, `nil` uniquement si aucun sous-score n'est calculable.
2. Appeler ce moteur avant `store.insertCompletedTrip` dans `TripManager.swift:44-50`, et passer les scores calculés à `insertCompletedTrip` au lieu des `nil` codés en dur dans `TripStore.swift:93-97`.
3. Si le calcul complet n'est pas possible dans ce cycle (dépendance à `SensorService` non livré), a minima :
   - Documenter clairement dans `qa/known-issues.md` que le score restera `--` tant que `ScoreEngine`/`SensorService` ne sont pas livrés.
   - Ajouter une clé `driving.score.notYetAvailable` plus explicite que l'actuelle "apparaîtra après calibration" si la calibration (5 trajets) est déjà atteinte mais qu'aucun score n'existe encore, pour ne pas laisser croire à un bug après le 5e trajet.

## Ordre de correction recommandé

1. TRUST-001 en premier : c'est le seul mensonge de sécurité actif visible par l'utilisateur dès l'écran d'accueil.
2. TRUST-002 ensuite : même pattern de correction, effort réduit une fois TRUST-001 fait.
3. SCORE-001 : soit le calcul minimal (étape 1-2), soit a minima le correctif de message (étape 3) si le `ScoreEngine` complet n'est pas dans ce cycle.
4. Mettre à jour `qa/known-issues.md` avec trois nouvelles entrées `TRUST-001`, `TRUST-002`, `SCORE-001`, statut et résolution une fois livrées.
5. Rappel : ne pas fermer `ASSIST-003` (cascade d'alerte) dans ce cycle, il reste un chantier séparé déjà tracké.

## Tests pertinents

### Tests automatisés à ajouter

1. XCTest `AccueilViewModelTests` (ou équivalent) :
   - `collisionDetectionEnabled == false` -> le statut affiché n'est jamais `status.enabled` / vert.
2. XCTest `NetworkStatusServiceTests` :
   - Simuler `NWPathMonitor` offline -> `isOnline == false`.
   - Simuler online -> `isOnline == true`, statut affiché passe à `status.online`.
3. Tests `TripManagerTests` / `TripStoreTests` :
   - Un trajet avec `maxSpeedKmh` au-dessus du seuil produit un `scoreVitesse` non nil et inférieur à un trajet sans excès.
   - `avgScore` sur `DrivingSummary` n'est plus systématiquement `nil` une fois qu'au moins un trajet a un score calculé.

### Tests manuels iPhone réel

1. Écran d'accueil, app fraîchement installée sans `CollisionDetector` livré : vérifier que "Détection de collision" n'affiche plus "Activé" en vert.
2. Mode avion : vérifier que "Connexion réseau" affiche "Prêt hors ligne" ; désactiver le mode avion : vérifier que le statut passe à "Connecté" sans redémarrer l'app.
3. Effectuer 5 trajets de calibration réels : vérifier que le score passe de `--` à une valeur numérique (si ScoreEngine minimal livré), ou que le message affiché ne laisse plus croire à un bug (si seul le correctif de message est livré).

## Critères d'acceptation

- Aucun statut affiché en vert "Activé" ne correspond à une fonctionnalité absente du code.
- "Connexion réseau" reflète l'état réel de la connectivité, pas une valeur figée.
- Après calibration (5 trajets), l'app affiche soit un score réel, soit un message qui n'implique pas un bug (plus de "-- après 5 trajets" alors que 5 trajets sont déjà faits).
- `qa/known-issues.md` contient `TRUST-001`, `TRUST-002`, `SCORE-001` avec leur statut à jour.
