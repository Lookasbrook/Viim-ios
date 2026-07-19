# CHANGELOG — Viim (yamstack-ios)

Toutes les modifications notables du projet, par date (plus récent en haut).

## 2026-07-19 (polissage fonctionnel)

- **[Données]** Coût carburant sensible au style de conduite : nouveau `DrivingDynamicsAnalyzer` (accélérations franches, freinages brusques, ralenti, vitesse moyenne dérivés des vitesses GPS horodatées) qui module la consommation constructeur dans des bornes crédibles [0,85 ; 1,5] — stop-and-go urbain agressif consomme plus, croisière souple légèrement moins. Formule `vehicle-fuel-catalog-v5-dynamics` ; les trajets historiques sont recalculés automatiquement au lancement à partir de leur tracé enregistré.
- **[Scores]** Fluidité et Éco-conduite activés : `ScoreEngine` v2 calcule `scoreFluidite` (événements brusques normalisés par distance) et `scoreEco` (dérivé du multiplicateur carburant) quand ≥ 60 s de dynamique fiable existe ; le score global devient la moyenne des critères disponibles. L'onglet Conduite affiche les cartes Fluidité et Éco réelles (moyennes 30 jours) au lieu de « À venir » ; Vigilance reste honnêtement « À venir » (pas de source de données).
- **[Assistance]** Jusqu'à 4 contacts d'urgence : stockage trousseau v2 (migration transparente de l'ancien contact unique), écran de gestion liste (ajout, suppression par balayage, limite 4), test WhatsApp et partage de position envoyés à tous les contacts (succès si au moins un envoi passe). Numéros internationaux acceptés (E.164 : +indicatif, 8-15 chiffres) côté iOS **et** backend (`/v1/alerts/*`, limite portée à 4 contacts) — un numéro commençant par 226 doit toujours porter ses 8 chiffres locaux exacts. **Le backend doit être redéployé** pour que les contacts non burkinabè passent.
- **[Onboarding/Profil]** Odomètre : champ « Kilométrage actuel » à l'étape véhicule de l'inscription ; la valeur sert de base et progresse automatiquement avec les km des trajets validés (`TripManager.currentOdometerKm`). Section Odomètre dans Profil (affichage du kilométrage courant + redéclaration).
- **[Prévention]** Rappels d'entretien réels basés sur l'odomètre : vidange, freins, pneus (+ chaîne pour moto/vélo), intervalles par défaut selon le type de véhicule (ex. vidange 5 000 km voiture / 3 000 km moto), bouton « Fait » qui pointe l'entretien à l'odomètre courant, statuts OK / Bientôt / En retard persistés (`MaintenanceStore`). Défi de la semaine activé : 5 derniers trajets sans excès de vitesse (score vitesse ≥ 90), pastilles branchées sur les données réelles.
- **[Prévention]** Zones à risque : l'onglet demande désormais une position fraîche à l'ouverture pour que la classification région (Burkina / hors Burkina / inconnue, livrée au build 12) s'applique réellement — au Canada, les repères ONASER de Ouagadougou sont masqués.
- **[QA]** Suite iOS complète verte (nouveaux tests : DrivingDynamics, MaintenanceStore, catalogue carburant dynamique, numéros internationaux) ; backend 15/15 (dont E.164 international et 4 contacts max).

## 2026-07-18 (soir — build 14)

- **[iOS P0]** Trajet du soir tronqué (4,19 km enregistrés sur ~11 km, trou GPS de 289 s, clôture « inactive » en roulant) : cause racine double prouvée par `s1-20260718-user-reported-partial-trip`. (1) Réveil tardif : l'app terminée n'a été relancée par changement significatif que ~4 min après le départ. (2) Cadence GPS passive : depuis le 14 juillet, la `CLBackgroundActivitySession` était invalidée à l'idle sous `Always` ; recréée depuis l'arrière-plan, elle ne rétablit pas la cadence continue (règle Apple) — tous les trajets depuis le 15 juillet sont `partial:gpsCoverageIncomplete`.
- **[iOS P0]** Correctif : sous `Always`, la session d'activité est créée dès le lancement (avant le premier callback de localisation) et survit à l'idle — elle doit être vivante à la terminaison du processus pour que la relance en arrière-plan retrouve la cadence GPS continue. Elle n'est invalidée que si le suivi automatique est désactivé ou l'autorisation perdue. Sous `When In Use`, comportement inchangé (session limitée au suivi actif).
- **[iOS P0]** Géofence de départ : à l'arrêt idle, une région de sortie de 150 m est armée sur la dernière position connue. La sortie de zone relance l'app (même terminée) dès les premières centaines de mètres, au lieu de 1-3 km avec le seul changement significatif. Désarmée dès que le GPS actif reprend.
- **[Compromis assumé]** L'indicateur de localisation peut réapparaître en veille sous `Always` (la session reste ouverte) : le critère « aucun indicateur en veille » du 17 juillet est incompatible avec la cadence continue après relance arrière-plan — fiabilité des données priorisée, à confirmer par Guy.
- **[QA]** Suite iOS complète verte (dont 3 nouveaux tests : recréation de session au lancement à froid, conservation à travers l'idle, armement/promotion de la géofence). Build `0.1.0 (14)` signé et installé sur l'iPhone de Guy (`devicectl install` OK ; vérification de version et premier lancement à faire sur l'appareil, tunnel CoreDevice coupé après l'installation). Validation terrain : refaire 2 trajets identiques et comparer distances + `gpsCoverage`.

## 2026-07-17 (nuit — build 13)

- **[UI]** Nouveau hero Accueil premium : bannière navy dégradée avec halos de profondeur, salutation selon l'heure (Bonjour/Bonsoir), prénom en grand, date en accent doré, et signature visuelle métier — un tracé de trajet en pointillés qui se dessine à l'ouverture, départ blanc et arrivée dorée pulsante. Remplace le bloc plat clair (« carré ») jugé peu premium.
- **[QA]** Suite iOS 128/128. Build `0.1.0 (13)` signé, installé et lancé sur l'iPhone de Guy. Monorepo poussé sur `main`.

## 2026-07-17 (nuit — build 12)

- **[UI]** Prévention adaptée à la région réelle : `PreventionRegion` classe la dernière position GPS (boîte englobante Burkina). Hors du Burkina (ex. Québec), les repères ONASER de Ouagadougou sont masqués au profit d'une carte « Hors Burkina » honnête ; position inconnue = état explicite. Le conseil harmattan n'apparaît qu'au Burkina ; « Saison des pluies » devient « Conduite sous la pluie » (universel). 5 tests unitaires (Ouagadougou, Bobo-Dioulasso, Québec, position absente/invalide).
- **[UI]** Fin des bugs de couleurs : apparence claire verrouillée (`UIUserInterfaceStyle=Light` + `preferredColorScheme(.light)`) — la palette Viim est claire fixe, iOS n'applique plus de barres/champs sombres par-dessus ; dernier `.secondary` remplacé dans Profil.
- **[UI]** Passage premium : apparition en cascade des cartes (Accueil, Conduite, Prévention), anneau de score circulaire animé avec dégradé angulaire, pastille pulsante sur le trajet actif, retour tactile sur les cartes de trajets, ombres harmonisées.
- **[QA]** Suite iOS 128/128. Build `0.1.0 (12)` signé, installé et lancé sur l'iPhone de Guy.

## 2026-07-17 (soir — build 11)

- **[UI]** Votre conduite branchée sur les données réelles : score 30 jours coloré selon la valeur, critère Vitesse alimenté par le score vitesse moyen réel (barre animée), écoconduite affichant les litres et le coût estimés réels du mois, fluidité/vigilance en état « À venir » honnête sans faux pourcentages ni barres vides.
- **[UI]** Prévention débarrassée de ses données fausses : la zone alertes n'annonce plus des « Alertes » actives inexistantes (chip « Référence », liste ONASER présentée comme repères indicatifs), « Alerte active » saison des pluies et « Pénuries carburant » sans source supprimés au profit de conseils de route, « 3 tâches » inventées remplacées par un entretien adapté au type de véhicule, barre du défi 60 % contredisant « 0/5 » remplacée par 5 pastilles à zéro.
- **[UI]** Polish premium : transitions animées des cartes conditionnelles de l'Accueil, score du jour en couleur adaptative (fini le « -- » vert succès), bouton dégradé avec retour tactile, animations d'apparition (anneau de score, pastilles défi, drapeau montagne).
- **[Fiabilité]** Restauration d'une régression découverte pendant la session : les sources `ios/Viim/**` étaient revenues à l'état du 15 juillet (sessions d'agents concurrentes sur le même clone) alors que les tests du 17 juillet attendaient la double chronologie GPS/réception. Restauré et étendu : `LocationSample.receivedAt`, durée observée des rafales relivrées compressées par iOS, `shouldFinalizeDespiteMotionMovement` (le GPS clôt un trajet quand CoreMotion reste bloqué en « automotive »), double chronologie dans `segmentDistanceMeters` et la fenêtre d'activité qualité, échantillons des trajets rejetés conservés pour audit.
- **[QA]** Suite iOS complète 123/123 après restauration. Build `0.1.0 (11)` signé, installé et lancé sur l'iPhone de Guy (la porte terrain 3 trajets reste à rouler).

## 2026-07-17

- **[iOS P0]** Build correctif enfin installé sur l'iPhone de Guy : `0.1.0 (10)` (le téléphone roulait encore sur le build 6 défectueux ; les builds 7-9 signés n'avaient jamais été installés faute d'appareil disponible). Installation vérifiée par `devicectl device info apps`. Lancement à distance impossible (tunnel CoreDevice en timeout) : premier lancement à faire manuellement, puis dérouler la porte terrain 3 trajets du blueprint 2026-07-14 §14.
- **[QA]** Audit complet du pipeline de capture : tous les correctifs documentés sont présents dans le code (réveil significatif parallèle, journal candidat durable dès le premier point, résultats terminaux par session, `CLBackgroundActivitySession` limitée au suivi actif, `CLServiceSession` Always iOS 18, démarrage rapide 3 points/5 s, anti-fusion 30 min, fallback GPS pur sans CoreMotion). Suite iOS 123/123 ; backend 13/13 (`node --test` par fichier ; l'appel global `npm test` pend dans cet environnement).
- **[Données]** Correction d'une chaîne trompeuse : le détail du coût estimé affirmait utiliser « votre style de conduite » alors que la formule v4 l'exclut volontairement. Nouveau libellé : distance GPS validée × consommation de référence × prix du litre configuré.
- **[Docs]** Notes de fiabilité par donnée affichée (barème /10) ajoutées à `data-reliability.md`, y compris le coût carburant (5/10 tant que les fiches techniques vérifiées et les prix régionaux backend ne sont pas livrés).

## 2026-07-14

- **[iOS P0]** Cause racine des trajets absents confirmée sur le build 6 : le GPS standard arrêtait le réveil par changements significatifs, puis iOS suspendait parfois Viim avant le premier point. Le suivi standard conserve désormais ce réveil en parallèle.
- **[iOS P0]** Cause racine de l'indicateur permanent confirmée : `CLBackgroundActivitySession` restait ouverte sous autorisation `Always`. Elle est maintenant réservée au suivi actif `When In Use` et invalidée au stop ; sous `Always`, la veille passive reste sans session visuelle.
- **[Données]** Formules `trip-metrics-v2` et `trip-quality-v2` : dérive GPS contenue dans l'incertitude neutralisée sans mouvement fiable, durée active séparée de la queue stationnaire et recalcul des trajets historiques au lancement. Le faux trajet réel de 108 m sert de test de régression.
- **[QA]** Suite iOS complète 111/111 ; build privé signé `0.1.0 (7)` prêt. Installation différée car l'iPhone de Guy était indisponible dans CoreDevice ; validation requise sur 3 nouveaux trajets avant clôture P0.
- **[Blueprint]** Nouveau plan maître `2026-07-14-fiabilite-vehicules-couts-internationalisation.md` : causes confirmées des trajets absents et de l'indicateur iOS, catalogue backend voiture/moto essence-diesel, prix régionaux Canada/Burkina, XOF/CAD, coût indicatif versionné, migration, sync, assistance et portes QA.
- **[Décision]** Un seul véhicule actif ; consommation combinée issue d'une fiche vérifiée ; aucun prix ni consommation saisi par l'utilisateur ; hybrides reportés ; trois trajets pour la build privée P0 et dix seulement avant TestFlight.
- **[Qualité]** Contrôle public de confidentialité sans finding et revue d'exécutabilité Codex à 7/10 après ajout des seuils, schémas, contrats API, règles de fraîcheur, idempotence et preuves terrain.

## 2026-07-12

- **[iOS]** DATA-003 cause racine amont prouvée par les logs iPhone : iOS suspendait l'app pendant les trajets écran verrouillé malgré `startUpdatingLocation` + `Toujours` (timer 180 s exécuté à +301 s, un seul point GPS toutes les 300,0 s = cadence des changements significatifs). Ajout de `CLBackgroundActivitySession` tenue pendant tout le monitoring pour empêcher la suspension (logs `location.backgroundSession.start/end`).
- **[iOS]** Anti-flapping GPS : preuve de mouvement calculée sur tous les points reçus (même trop imprécis pour la route) ; le failsafe d'inactivité et l'arrêt stationnaire CoreMotion sont différés tant qu'un déplacement récent est prouvé, au lieu de couper la session en plein trajet.
- **[iOS]** Anti-fusion de trajets : au-delà de 30 min de silence, le point entrant clôt l'ancien trajet actif même s'il est rapide (voiture garée puis nouveau départ).
- **[QA]** Nouveaux tests : preuve de mouvement (vitesse, déplacement imprécis probant, jitter non probant), report du failsafe, plafond dur anti-fusion. Extraction terrain `qa/artifacts/s1-20260711-investigation-fresh`.

## 2026-07-09

- **[iOS]** DATA-003 : correction des trois causes de trajets jamais démarrés — promotion du réveil arrière-plan désormais possible à froid (`shouldPromotePassiveWakeup` testée, promotion systématique sur réveil récent sans position de référence), GPS maintenu écran verrouillé dès l'autorisation `WhenInUse` (indicateur système affiché), et détection moto tolérante (seuls marche/course excluent un départ ; mouvement non classé déclenche pour tous les véhicules).
- **[iOS]** Fallback GPS pur quand CoreMotion est indisponible ou refusé : la détection de trajet et le nouveau failsafe d'inactivité (arrêt GPS après 3 min sans trajet) gèrent seuls le cycle marche/arrêt.
- **[iOS]** Câblage headless : `TripRecorder.observe`/`recoverActiveTrips` et la configuration véhicule vivent dans `ViimApp.init`, actifs même quand iOS relance l'app en arrière-plan sans interface.
- **[iOS]** Distance par scan d'ancre : un point GPS aberrant ne coûte plus qu'un segment rejeté sans casser la continuité ; le contrôle de démarrage de trajet ne s'annule plus au premier segment invalide ; `TripQualityEngine` aligné sur le même parcours.
- **[QA]** Nouveaux tests XCTest : 5 cas de promotion de réveil, glitch isolé au démarrage, marche vs moto, mouvement non classé ; mise à jour du test distance (ancre).
- **[Docs]** Blueprint `2026-07-09-validation-terrain-et-suite.md` : scénarios terrain S1-A/B/C bloquants, test WhatsApp production, puis Phases C/D/E.

## 2026-07-05

- **[iOS]** Ajout d'un normaliseur téléphone Burkina partagé : les saisies `70 00 00 00`, `+226 70 00 00 00` et `00226 70 00 00 00` sont stockées en `+22670000000`.
- **[iOS]** Onboarding et contacts d'urgence refusent désormais tout numéro non normalisable ; un ancien contact Keychain invalide apparaît comme `Contact à corriger` et bloque le test WhatsApp.
- **[iOS]** Le bouton test WhatsApp et le partage de position affichent des erreurs distinctes pour contact invalide, NEwAGENT indisponible, absence réseau et timeout.
- **[iOS]** Assistance demande une position GPS ponctuelle à l'ouverture de `Voir ma localisation`, affiche un état de recherche, puis une erreur après délai si aucune position fraîche n'arrive.
- **[iOS]** Accueil distingue `Position active dans l'app` et détection arrière-plan ; l'escalade `Always` passe par le bouton explicite `Activer l'arrière-plan`.
- **[Backend]** Ajout de logs WhatsApp scrubbed côté dispatch : `kind`, statut/code provider uniquement, sans numéro, token, métadonnées sensibles ni body provider.
- **[QA]** Tests backend `npm test` OK (5 tests), `npm run check` OK, et `xcodebuild test` simulateur iPhone 17 Pro OK (24 tests).

## 2026-07-03

- **[iOS]** Ajout du parcours d'inscription 3 étapes au premier lancement : identité, moyen de déplacement adaptatif, sécurité.
- **[Sécurité]** Contact d'urgence stocké dans le Keychain uniquement ; profil local sauvegardé hors ligne avec `synced=false`.
- **[QA]** Onboarding validé par build simulateur, build signé iPhone réel, installation et lancement de `com.yamstack.viim` sur l'iPhone de Guy.
- **[iOS]** Ajout de `LocationService` : service de position, détection début/fin de trajet, précision normale/économie et état de suivi visible sur l'Accueil.
- **[QA]** Préflight S1 validé sur iPhone réel : build signé, installation et lancement OK ; roulage terrain 20 min écran verrouillé encore à exécuter.
- **[iOS]** Correction de l'affichage plein écran : ajout d'un Launch Screen natif pour supprimer le letterboxing sur iPhone.
- **[Design]** Réalignement des écrans Onboarding et Accueil sur `design/maquettes-ecrans.html` : brand mark, hero, carte véhicule, KPI, statuts et illustration adaptative.
- **[iOS]** Correction de lisibilité en mode sombre : textes explicites sur les cartes des onglets Votre conduite, Assistance et Prévention.
- **[Design]** Ajout du premier visuel système Viim : icône d'application iPhone complète dans `Assets.xcassets`.
- **[Design]** Remplacement des photos génériques par un catalogue local par marque/modèle : Corolla, Hilux, RAV4, Prado, Land Cruiser, Yamaha Crypton/YBR, Bajaj Boxer, TVS Apache et Honda CG125.
- **[QA]** Ajout du target `ViimTests` avec tests XCTest de résolution marque/modèle et vérification que chaque entrée du catalogue pointe vers un asset embarqué.
- **[iOS]** Correction du mode GPS visible après autorisation : Viim ne démarre plus le GPS continu au lancement, ne demande plus `Always` automatiquement et désactive l'indicateur arrière-plan par défaut.
- **[ADR]** Décision `2026-07-03-localisation-discrete-ios` : localisation discrète par défaut, suivi arrière-plan à traiter avec consentement explicite et déclenchement CoreMotion/GPS.
- **[Design]** Réalignement des onglets Votre conduite, Assistance et Prévention sur la maquette HTML : héros, cartes riches, listes d'actions, sections d'urgence, prévention ONASER et entretien.
- **[iOS]** Ajout de la base trajets réelle : modèle CoreData local `Trip`/`TripEvent`/`DailySummary`, `TripStore`, `TripManager`, `synced=false` par défaut et persistance des trajets terminés.
- **[iOS]** Accueil alimenté par les données locales : trajet en cours, résumé du jour, compteur calibration 0/5→5/5 et trajets récents persistés.
- **[iOS]** Onglet Votre conduite : compteurs du héros branchés sur les trajets des 30 derniers jours.
- **[QA]** Ajout de `TripStoreTests` pour valider sauvegarde offline, compteur calibration et protection contre doublons ; `xcodebuild test` simulateur OK, build signé iPhone réel OK, installation et lancement OK.
- **[ADR]** Décision `2026-07-03-coredata-modele-programmatique` : modèle CoreData V1 défini en Swift pour débloquer la persistance locale testable sans `.xcdatamodeld`.
- **[iOS]** Suppression du bouton manuel de suivi : Viim détecte maintenant un déplacement probable via `CoreMotion` et démarre automatiquement la confirmation GPS.
- **[iOS]** Accueil recentré sur les trajets d'aujourd'hui : la liste est filtrée sur la journée en cours et affiche seulement les trajets persistés aujourd'hui.
- **[QA]** Ajout de `MotionActivityServiceTests` pour valider les déclencheurs moto/voiture/vélo, l'immobilité et la faible confiance ; build/test simulateur OK, build signé iPhone réel OK, installation et lancement OK.
- **[ADR]** Décision `2026-07-03-detection-mouvement-sans-bouton` : détection automatique par mouvement, GPS coupé à l'arrêt, pas de friction utilisateur.
- **[iOS]** Correction du parcours du jour absent malgré GPS autorisé : ajout de diagnostics appareil, réveils passifs localisation, promotion GPS continu seulement sur mouvement réel et finalisation de trajet actif après immobilité.
- **[Design]** Accueil : statut `Réveil automatique actif` quand Viim est prêt à démarrer automatiquement un trajet sans suivi GPS continu.
- **[QA]** Diagnostic iPhone réel `TRIP-003` : autorisation `authorizedAlways` confirmée, base appareil vide (`ZTRIP=0`, `ZTRIPEVENT=0`, `ZDAILYSUMMARY=0`), tests simulateur OK, build signé et installation iPhone OK, logs finaux sans démarrage GPS continu à l'arrêt.
- **[ADR]** Décision `2026-07-03-reveils-passifs-localisation` : écoute légère par changements significatifs et impossibilité de reconstruire rétroactivement un trajet non collecté.
- **[Backend]** Ajout des routes Assistance `/v1/alerts/test`, `/v1/alerts/location-share` et `/v1/alerts/collision` avec validation téléphone Burkina, payload position et client NEwAGENT WhatsApp.
- **[iOS]** Onglet Assistance branché : appels `18`/`17`, écran MapKit de localisation, partage de position, contacts d'urgence Keychain, fiche médicale Keychain et bouton test WhatsApp.
- **[iOS]** Suppression du dernier bouton vide dans Votre conduite : `Voir mon style de conduite` ouvre maintenant un écran de portrait détaillé.
- **[QA]** Tests backend Node `alerts.test.js` OK, `npm run check` OK, `xcodebuild test` simulateur OK, build signé iPhone réel OK, installation et lancement iPhone OK.

## 2026-07-02

- **[P0]** Initialisation du repo GitHub cloné `Viim-ios` avec la documentation existante et la structure monorepo `ios/` + `backend/`.
- **[iOS]** Ajout du projet Xcode `Viim` (SwiftUI, iOS 16+, 4 onglets localisés, charte couleurs, background modes, entitlements Push, Team ID `MJJ6A56JHS`).
- **[Backend]** Ajout du squelette `viim-api` Node/Express avec `/health`, migration PostgreSQL initiale et Dockerfile Coolify.
- **[QA]** Build simulateur iOS OK, backend `/health` local OK ; blocages P0 consignés dans `qa/known-issues.md` pour signature iPhone réel, DNS API et SSH Coolify.
- **[QA]** Diagnostic signature iPhone réel affiné : certificat YELIM valide, build de contrôle OK sans APNs, échec normal causé par absence de profil Push `com.yamstack.viim` et par absence de compte Apple visible pour `xcodebuild`.
- **[iOS]** Résolution du build iPhone réel : profil `iOS Team Provisioning Profile: com.yamstack.viim` avec Push activé, build signé OK, installation et lancement confirmés sur l'iPhone de Guy.
- **[iOS]** Correction du packaging app : ajout des clés bundle standard dans `Info.plist` pour permettre l'installation (`CFBundleIdentifier`, version, exécutable, type).
- **[Repo]** Préparation de la publication du monorepo `Viim-ios` vers GitHub afin que Coolify puisse construire `backend/Dockerfile`.
- **[Repo]** Publication effective du monorepo sur `Lookasbrook/Viim-ios`, branche `main`, commit `253ee3a`, pour débloquer la création de l'app Viim dans Coolify.
- **[Backend]** Déploiement Coolify confirmé sur le VPS `178.105.115.6` : app Viim `blqn1beg8ae0dvddmqio6rth`, PostgreSQL Viim `v46pxb68fon91lz66pdyomot`, migrations initiales appliquées, `/health` runtime en `degraded` tant que NEwAGENT-IA n'est pas configuré.
- **[DNS]** Enregistrement `api.burktech-ia.com` corrigé côté authoritative vers `178.105.115.6`; TLS Let's Encrypt confirmé côté infra, mais `/health` reste `degraded` tant que le token NEwAGENT-IA n'est pas configuré.
- **[Backend]** Runtime Viim revérifié : `DATABASE_URL` et `NEWAGENT_URL` sont présents, `NEWAGENT_TOKEN` absent ; `/health` public retourne encore HTTP 503 `degraded`.
- **[Backend]** `NEWAGENT_TOKEN` configuré dans Coolify sans exposition du secret ; `/health` public de Viim retourne HTTP 200 avec `status:"ok"`, DB et WhatsApp OK.
- **[Monitoring]** Uptime Robot reste à configurer : endpoint `/health` prêt et vert, mais aucun accès/API key Uptime Robot disponible dans la session Codex.
- **[Décision]** Report PO de la configuration Uptime Robot : l'exécution Phase 1 peut continuer, mais le monitoring reste obligatoire avant tout testeur externe.

## 2026-07-01 (nuit) — QA pré-handoff builder

- **[ADR]** Les 2 décisions laissées ouvertes dans `blueprints/00-ordre-execution.md` et `02-backend-coolify.md` sont tranchées par Claude (Architecte/QA) pour débloquer le démarrage du builder :
  - Repo Git unique `viim` (monorepo `ios/` + `backend/`) — [décisions/2026-07-01-repo-monorepo.md](decisions/2026-07-01-repo-monorepo.md).
  - API sur sous-domaine dédié `api.burktech-ia.com` (au lieu du domaine racine partagé avec NEwAGENT-IA) — [décisions/2026-07-01-sous-domaine-api.md](decisions/2026-07-01-sous-domaine-api.md).
- **[Sync]** Références mises à jour en conséquence : `blueprints/00-ordre-execution.md`, `01-ios-app.md`, `02-backend-coolify.md`, `architecture/api-endpoints.md`, `architecture/overview.md`, `qa/test-plan.md`.
- **[QA]** Revue complète de la documentation (17 fichiers .md) avant transmission au builder : cohérence vérifiée (branding, seuils capteurs, endpoints, ADRs), aucun bug bloquant (`qa/known-issues.md` vide, projet non démarré).

## 2026-07-01 (soir)

- **[Naming]** L'application s'appelle **Viim** (« la vie » en mooré) — décision de Guy. Règle de marque : YAMSTACK TECHNOLOGIE visible uniquement en pied de l'onglet Assistance + mentions légales (`design/branding-vocabulaire.md`).
- **[Design]** Maquettes v2 (`design/maquettes-ecrans.html`) : écran d'inscription avec véhicule adaptatif et illustration (modèle BNA), onglets alignés (icônes SVG), vocabulaire et typographie français soignés, carte MapKit natif.
- **[Specs]** Nouveau `features/inscription-onboarding.md` (adaptation de l'app au moyen de déplacement) ; `data-models.md` (illustration/photo véhicule), `api-endpoints.md`, `onglet-1-accueil.md` (carte véhicule suivi) réalignés ; notification collision au vouvoiement.
- **[Blueprints]** Création de `blueprints/` : ordre d'exécution, blueprint iOS, blueprint backend Hetzner/Coolify — point d'entrée du builder (Codex).

## 2026-07-01

- **[Design]** Maquettes HTML des 6 écrans clés dans `design/maquettes-ecrans.html` + propositions de nom (LAAFI SIRA / SIRA / BURKINDI) — remplacées le soir même par la décision **Viim**.
- **[Init]** Création de la structure documentaire complète (architecture, features, tracking, qa, decisions) par Claude (Architecte/QA).
- **[Init]** Rédaction des 4 ADRs fondateurs : iOS-first, WhatsApp comme canal d'alerte primaire, Keychain pour données médicales, filtrage capteurs (low-pass + confirmation GPS).
- **[Init]** Spécifications features rédigées à partir du Cahier des Charges v2.0 et des captures d'écran de référence BNA (Banque Nationale Assurances).
- **[Init]** Plan de test MVP avec métriques cibles définies dans `qa/test-plan.md`.
