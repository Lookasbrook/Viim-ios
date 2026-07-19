# Blueprint — Fiabilité complète, véhicules, coûts et internationalisation

Date : 2026-07-14  
Statut : validé pour exécution  
Marchés initiaux : Canada et Burkina Faso  
Livraison initiale : build privée de fiabilité installée après P0, puis build privée complète après P6

## 1. Résultat attendu

Viim détecte automatiquement les déplacements, conserve chaque tentative de trajet dans un état explicite, calcule un coût indicatif à partir de la navigation, de la fiche technique exacte du véhicule et du prix régional du carburant, puis présente les résultats dans la devise choisie.

L'utilisateur renseigne son véhicule une fois pendant l'inscription puis conduit normalement. Il ne démarre pas le suivi, ne corrige pas les trajets, ne saisit pas la consommation et ne saisit pas le prix du carburant.

La première version prend en charge :

- les voitures essence et diesel ;
- les motos essence et diesel ;
- un seul véhicule actif par compte ;
- le Canada et le Burkina Faso ;
- le franc CFA `XOF` et le dollar canadien `CAD`.

Le suivi existant des vélos peut rester disponible, mais sans calcul de carburant. Les hybrides, véhicules électriques, plusieurs véhicules actifs et la diffusion TestFlight sont hors périmètre de cette livraison.

## 2. Causes racines confirmées

### 2.1 Trajets absents

Les extractions de la build installée montrent des trajets signalés par l'utilisateur sans ligne `Trip`, sans brouillon actif et sans échantillon GPS récupérable. Les journaux prouvent la séquence suivante :

1. CoreMotion détecte le déplacement et demande le GPS continu.
2. Le service de changements significatifs n'est pas conservé comme mécanisme de réveil parallèle dans la build concernée.
3. iOS suspend le processus avant les premiers rappels du GPS continu.
4. Aucun premier échantillon n'atteint le journal local ; le trajet ne peut donc ni être persisté ni être récupéré.

Les trajets déjà manqués sans brouillon ni échantillon ne peuvent pas être reconstruits. Le correctif doit conserver le réveil par changements significatifs pendant le suivi standard et journaliser dès le premier point reçu.

Références :

- `ios/Viim/Services/LocationService.swift`
- `ios/Viim/Persistence/ActiveTripJournal.swift`
- `qa/artifacts/s1-20260714-user-reported-missing-trips/`

### 2.2 Indicateur de navigation iOS persistant

La build installée créait et retenait une `CLBackgroundActivitySession` alors que Viim était passif. Cette session est la cause de l'indicateur iOS qui rouvre Viim lorsqu'on le touche.

Le comportement cible est :

- avec l'autorisation « Toujours », utiliser `UIBackgroundModes.location` et le réveil par changements significatifs sans session visuelle passive ;
- n'utiliser une `CLBackgroundActivitySession` que pour un suivi actif compatible avec l'autorisation « Lorsque l'app est utilisée » ;
- invalider toute session dès l'arrêt du suivi ;
- ne jamais afficher durablement l'indicateur lorsque l'utilisateur ne conduit pas.

Référence : `ios/Viim/Services/LocationService.swift`.

### 2.3 Coût de carburant incorrect

Le code courant ne peut pas produire un coût fiable parce que :

- l'étape véhicule de l'inscription accepte actuellement des champs vides ;
- le catalogue local associe surtout marque et modèle à une seule valeur en L/100 km ;
- il ne distingue pas systématiquement année, carburant, moteur, version ou transmission ;
- le profil permet un prix par litre local ou modifiable ;
- le backend n'expose ni fiches techniques, ni prix régionaux, ni taux de change ;
- la migration initiale conserve encore un champ `fuel_fcfa`, incompatible avec plusieurs devises et une traçabilité historique.

Références :

- `ios/Viim/Onboarding/OnboardingView.swift`
- `ios/Viim/Onboarding/OnboardingStore.swift`
- `ios/Viim/Services/VehicleFuelCatalog.swift`
- `ios/Viim/Features/Profil/ProfilView.swift`
- `backend/src/server.js`
- `backend/src/db/migrations/001_initial.sql`

## 3. Principes non négociables

1. Détection automatique : aucun bouton de démarrage ou d'arrêt de trajet.
2. Zéro perte silencieuse : chaque tentative possède un identifiant et un résultat terminal.
3. Offline-first : la conduite est enregistrée sans réseau ; le coût peut rester en attente.
4. Source de vérité backend : fiches techniques, prix de carburant et taux de change.
5. Aucune valeur inventée : une donnée absente produit « estimation indisponible » ou « en attente ».
6. Consommation indicative : cette mention apparaît partout où une consommation ou un coût est affiché.
7. Historique stable : une modification future de prix, de taux ou de fiche ne modifie pas un ancien trajet.
8. Internationalisation réelle : pays, téléphones, urgences, devises et contenus ne sont pas déduits d'hypothèses Burkina-only.
9. Données réelles dans l'interface : aucun score, badge, classement ou conseil présenté comme réel s'il reste statique.

## 4. Parcours d'inscription cible

### 4.1 Identité et marché

Champs obligatoires :

- pays : Canada ou Burkina Faso ;
- prénom ;
- téléphone normalisé au format E.164 ;
- autorisations Localisation et Mouvement expliquées séparément.

Le pays est choisi explicitement. Le téléphone, la locale ou le GPS peuvent préremplir une proposition, mais ne remplacent pas la confirmation de l'utilisateur.

### 4.2 Véhicule actif

Tous les choix proviennent du backend et sont dépendants :

1. voiture ou moto ;
2. marque ;
3. modèle ;
4. année ;
5. essence ou diesel ;
6. motorisation ou cylindrée ;
7. version et transmission lorsqu'elles modifient la consommation ;
8. confirmation de la fiche technique.

Le profil conserve un `vehicleSpecId` stable. La marque, le modèle et les autres libellés sont des instantanés d'affichage, pas l'identité technique du véhicule.

La sélection d'une fiche vérifiée est obligatoire pour terminer l'inscription d'un véhicule motorisé. Si le modèle manque, l'app crée une demande de couverture de catalogue et explique que l'estimation de carburant restera indisponible jusqu'à vérification. Pour la build privée, la fiche exacte du véhicule de test est ajoutée avant installation.

### 4.3 Autorisation dégradée

Si l'autorisation « Toujours » est refusée :

- l'app reste utilisable ;
- elle explique que les départs écran verrouillé peuvent être manqués ;
- elle propose un lien vers Réglages ;
- elle n'affirme jamais que la détection automatique complète est active.

## 5. Catalogue technique backend

### 5.1 Modèle de données

Ajouter au minimum :

- `vehicle_makes`
- `vehicle_models`
- `vehicle_specs`
- `vehicle_spec_sources`
- `user_vehicles`
- `vehicle_catalog_requests`
- `catalog_import_runs`

Une `vehicle_spec` contient :

- identifiant stable ;
- type `car` ou `motorcycle` ;
- marque et modèle canoniques ;
- année de début et de fin ;
- carburant `gasoline` ou `diesel` ;
- cylindrée, moteur, version et transmission ;
- consommation urbaine, route et combinée lorsqu'elles existent ;
- unité et protocole de mesure ;
- marché concerné ;
- source, URL ou document justificatif ;
- date de publication, date de vérification et version ;
- statut `verified`, `needs_review` ou `archived`.

### 5.2 Sources

Priorité :

1. données gouvernementales ou d'homologation ;
2. fiche officielle du constructeur ;
3. documentation technique d'importateur vérifiée ;
4. aucune estimation si aucune source acceptable n'existe.

Le jeu de données de Ressources naturelles Canada peut alimenter les voitures et camions légers vendus au Canada. Il ne constitue pas une couverture moto complète. Les motos sont donc alimentées par des fiches constructeur ou d'homologation, avec provenance et date de vérification.

Source Canada : https://open.canada.ca/data/en/dataset/98f1a129-f628-4ce4-b24d-6f16bf24dd64

### 5.3 API

- `GET /v1/markets`
- `GET /v1/vehicles/makes?market=&type=`
- `GET /v1/vehicles/models?makeId=&year=`
- `GET /v1/vehicle-specs?...`
- `GET /v1/vehicle-specs/:id`
- `POST /v1/vehicle-catalog-requests`
- `PUT /v1/profile/active-vehicle`

Les listes doivent être paginées, cacheables et versionnées. Le client iOS conserve la fiche active hors ligne.

## 6. Prix régional du carburant

### 6.1 Modèle de données

Ajouter `fuel_prices` avec :

- pays, province/région, ville ou localité ;
- carburant ;
- prix en unités mineures par litre ;
- devise ;
- source et document source ;
- date d'effet, date de récupération et date d'expiration ;
- niveau géographique ;
- statut de fraîcheur et de vérification.

Chaque ingestion est historisée. Un prix corrigé crée une nouvelle version et n'écrase pas l'ancien.

### 6.2 Règle géographique

La localisation de départ du trajet détermine le prix :

1. prix de la ville ou localité ;
2. prix de la province ou région ;
3. prix national ;
4. coût en attente si aucune donnée valide n'est disponible.

Le backend renvoie le niveau de repli utilisé. L'app l'affiche dans le détail du calcul.

### 6.3 Canada

Ingestion hebdomadaire des prix moyens de Ressources naturelles Canada, par ville ou province selon les données disponibles. Ces prix sont des valeurs de référence ; Viim les présente donc comme prix moyens indicatifs, jamais comme prix exact d'une station.

Source : https://natural-resources.canada.ca/domestic-international-markets/transportation-fuel-prices

### 6.4 Burkina Faso

Ingestion des arrêtés et barèmes officiels du ministère chargé du Commerce ou de la SONABHY. Les localités et dates d'effet sont conservées. Un document ancien téléchargé récemment ne devient pas automatiquement un prix actuel : sa date juridique d'effet prévaut.

Sources :

- https://www.sonabhy.bf/tarif-hydrocarbures/
- https://www.commerce.gov.bf/fileadmin/user_upload/storage/fichiers/Arrete___Conjoint_11.pdf

### 6.5 API

- `GET /v1/fuel-prices/quote?lat=&lon=&fuelType=&at=`
- `GET /v1/fuel-prices/:id`
- tâche d'ingestion Canada hebdomadaire ;
- tâche de vérification Burkina quotidienne ;
- alerte d'exploitation lorsqu'une source devient périmée.

Le prix n'est jamais saisi dans l'application iOS.

## 7. Devises XOF et CAD

Le coût natif est conservé dans la devise du prix régional. Le profil possède une devise d'affichage `XOF` ou `CAD`.

Ajouter `fx_rates` avec :

- devise source et devise cible ;
- valeur décimale précise ;
- date d'effet ;
- source ;
- date de récupération.

La BCEAO publie quotidiennement le cours du dollar canadien contre le franc CFA et constitue la source principale CAD/XOF. La Banque du Canada peut servir de contrôle ou de repli via EUR/CAD, sans remplacer silencieusement une donnée absente.

Sources :

- https://downloads.bceao.int/index.php/fr/cours/cours-de-reference-des-principales-devises-contre-Franc-CFA
- https://www.bankofcanada.ca/valet-api-how-to/

Le changement de devise d'affichage ne recalcule jamais le montant natif d'un trajet et ne modifie pas son taux historique.

## 8. Calcul indicatif des litres et du coût

### 8.1 Entrées autorisées

- distance GPS validée ;
- consommation combinée de la fiche active ;
- prix régional correspondant au carburant et à la date du trajet ;
- taux historique si la devise d'affichage diffère.

Les accélérations, freinages et le score de vitesse ne modifient pas arbitrairement la consommation dans cette version. Ils restent des métriques de conduite séparées tant qu'un modèle de surconsommation n'a pas été validé.

Les consommations urbaine et route restent stockées dans la fiche mais ne sont pas utilisées par la première build. Viim ne possède pas encore de classification urbaine/route suffisamment validée ; employer la cote combinée évite d'introduire un multiplicateur non prouvé.

### 8.2 Formule

```text
litres_estimes = distance_validee_km × consommation_combinee_L100 / 100
cout_natif = litres_estimes × prix_regional_par_litre
cout_affiche = cout_natif × taux_historique
```

Tous les calculs monétaires backend utilisent des unités mineures ou des décimaux exacts, jamais des flottants binaires. Les règles d'arrondi dépendent de la devise : zéro décimale pour XOF, deux pour CAD.

### 8.3 Instantané historique

Chaque trajet conserve :

- `calculationVersion` ;
- distance GPS validée ;
- `vehicleSpecId` et version de fiche ;
- consommation utilisée ;
- litres estimés ;
- `fuelPriceId`, valeur, niveau régional, source et date ;
- coût et devise natifs ;
- taux, date du taux et coût d'affichage.

La mention suivante apparaît sur l'Accueil, le détail du trajet et les résumés :

> Estimation indicative basée sur la fiche technique du véhicule, le trajet détecté et le prix moyen du carburant dans la région.

## 9. Pipeline de navigation fiable

### 9.1 États

Le coordinateur possède les états :

- `passive`
- `arming`
- `recording`
- `stationaryPending`
- `blocked`

Chaque tentative reçoit un `captureSessionId` et termine par :

- `persisted`
- `duplicate`
- `rejected(reason)`
- `interrupted(recoveryState)`
- `failedRetryable(errorCode)`

### 9.2 Invariants

- Le réveil par changements significatifs reste actif avec l'autorisation « Toujours ».
- Le GPS continu s'ajoute au réveil passif lors d'un mouvement probable.
- Le premier point exploitable crée un journal `candidate` durable.
- Les échantillons sont ajoutés au journal avant les calculs dérivés.
- Une erreur de sauvegarde conserve le brouillon.
- La reprise est idempotente et ne crée aucun doublon.
- Un arrêt prolongé finalise automatiquement le trajet.
- Un long silence sépare deux trajets au lieu de les fusionner.
- Chaque session possède un résultat terminal visible dans les diagnostics.
- L'historique affiche les trajets au-delà du jour courant.

### 9.3 Synchronisation

Ajouter :

- `POST /v1/trips/batch` avec clés d'idempotence ;
- `GET /v1/sync?cursor=` pour réconciliation ;
- reprise avec backoff ;
- état local `pending`, `syncing`, `synced` ou `failedRetryable` ;
- compression de la route et minimisation des données envoyées.

Un échec réseau ne bloque jamais la persistance locale.

## 10. Réalignement fonctionnel des écrans

### Accueil

- véhicule actif et fiche technique ;
- état réel des permissions et de la détection ;
- trajet actif ;
- résultat de la dernière tentative ;
- résumé du jour ;
- litres et coût indicatifs ou état « en attente » ;
- trois derniers trajets, quelle que soit leur date.

### Votre conduite

- métriques calculées uniquement ;
- vitesse, fluidité, accélérations, freinages et vigilance ;
- aucune moyenne communautaire, badge ou économie simulée ;
- séparation explicite entre score de conduite et coût indicatif.

### Assistance

- téléphones E.164 internationaux ;
- numéros d'urgence configurés par pays ;
- collision avec compte à rebours d'annulation ;
- envoi WhatsApp traçable jusqu'au statut fournisseur ;
- cascade de contacts et repli SMS ;
- données médicales envoyées uniquement après une collision confirmée.

### Prévention

- contenus et zones adaptés au pays et à la position ;
- entretien adapté au type et à la fiche du véhicule ;
- aucune recommandation moto appliquée à une voiture ;
- aucune donnée de Ouagadougou présentée comme locale au Canada.

### Profil

- consultation de la fiche active et de sa source ;
- remplacement du véhicule via le parcours catalogue ;
- choix XOF ou CAD ;
- source et date du prix et du taux ;
- aucun champ de prix ou de consommation modifiable.

## 11. Internationalisation et sécurité

- Remplacer `BurkinaPhoneNumber` par une normalisation E.164 pilotée par le pays.
- Stocker les contacts d'urgence et la fiche médicale dans le Keychain.
- Conserver des configurations pays backend pour les numéros d'urgence et textes légaux.
- Ne jamais inscrire de donnée médicale, téléphone complet, token ou route précise dans les logs.
- Authentifier les API profil, trajet et prix ; limiter les taux et valider tous les payloads.
- Séparer les droits d'administration du catalogue et des prix des droits utilisateur.
- Journaliser les imports et modifications de fiches/prix sans secret.

## 12. Phases d'exécution

### P0 — Capture GPS et indicateur iOS

1. Conserver le service de changements significatifs en parallèle du GPS standard.
2. Finaliser le journal dès le premier point et les résultats terminaux.
3. Limiter `CLBackgroundActivitySession` aux cas nécessaires et l'invalider à l'arrêt.
4. Construire, signer et installer la nouvelle build privée.
5. Exécuter les trois trajets terrain définis en section 14.

Sortie : aucun trajet silencieusement perdu et aucun indicateur persistant en veille.

### P1 — Catalogue technique

1. Migrations PostgreSQL.
2. API de recherche.
3. import Canada voitures ;
4. pipeline vérifié pour motos ;
5. ajout de la fiche exacte du véhicule privé ;
6. cache iOS et tests de contrat.

Sortie : l'inscription retourne toujours un `vehicleSpecId` vérifié pour le véhicule de test.

### P2 — Prix et devises

1. Modèles prix et taux ;
2. ingestion Canada ;
3. ingestion Burkina ;
4. récupération BCEAO CAD/XOF ;
5. endpoints de cotation ;
6. alertes de fraîcheur.

Sortie : une cotation reproductible existe pour les deux marchés et les deux carburants.

### P3 — Inscription et migration

1. Ajouter pays, carburant, moteur, version et transmission.
2. Rendre la sélection véhicule obligatoire.
3. Migrer le profil local vers `vehicleSpecId`.
4. Supprimer les valeurs de consommation et prix modifiables.

Sortie : aucune voiture ou moto motorisée ne peut être enregistrée sans fiche identifiée.

### P4 — Calcul et historique

1. Réutiliser la distance filtrée par `TripMetricsCalculator`.
2. Implémenter la formule versionnée.
3. Créer l'instantané de coût.
4. Gérer coût en attente et recalcul unique après arrivée du prix.
5. Ajouter l'affichage XOF/CAD et la mention indicative.

Sortie : les tests de référence reproduisent exactement litres, coût natif et conversion.

### P5 — Sync et écrans réels

1. Synchronisation idempotente profil/trajets/coûts.
2. Accueil et historique.
3. Votre conduite sans données simulées.
4. Prévention adaptée au véhicule et au marché.

Sortie : toute valeur présentée comme réelle possède une source locale ou backend identifiable.

### P6 — Assistance internationale

1. Téléphone international et numéros d'urgence.
2. Collision et annulation.
3. preuve de livraison WhatsApp ;
4. cascade contacts et SMS ;
5. tests Canada/Burkina.

Sortie : un scénario consenti de bout en bout aboutit ou expose une erreur terminale actionnable.

### P7 — Validation avant diffusion externe

1. Dix trajets consécutifs sans perte silencieuse.
2. Matrice sécurité et internationalisation.
3. monitoring backend actif.
4. revue confidentialité et batterie.

Sortie : critères de `qa/test-plan.md` atteints avant TestFlight.

## 13. Stratégie de tests

### iOS unitaires

- transitions du coordinateur ;
- conservation du réveil passif ;
- premier point vers journal candidat ;
- reprise après suspension ;
- fin automatique ;
- sauvegarde échouée puis reprise ;
- déduplication ;
- calcul combiné ;
- arrondis XOF/CAD ;
- coût en attente ;
- migration du profil et du modèle CoreData.

### Backend

- migrations aller et compatibilité avec les données existantes ;
- filtrage du catalogue par type, année, carburant et moteur ;
- résolution géographique ville/région/pays ;
- prix périmé ;
- taux historique ;
- idempotence des trajets ;
- autorisation administrateur ;
- validation et limitation des payloads.

### Contrats et intégration

- mêmes enums et unités iOS/backend ;
- catalogue disponible hors ligne après synchronisation ;
- ancien trajet stable après changement de prix ;
- changement de devise sans altération du montant natif ;
- véhicule moto et voiture avec noms proches sans collision de fiche.

### Non-régression

- historique existant conservé ;
- contacts et fiche médicale conservés ;
- routes Assistance existantes fonctionnelles ;
- aucun secret ou téléphone complet dans les logs ;
- suite iOS et backend entièrement verte.

## 14. Validation privée sur iPhone

Les trajets déjà réalisés prouvent le défaut de l'ancienne build, mais ne peuvent pas valider un correctif non installé. La validation privée demande trois nouveaux trajets seulement :

1. Viim ouverte au départ, puis écran verrouillé.
2. iPhone verrouillé et Viim non ouverte au premier plan avant le départ.
3. Trajet, arrêt complet, attente de finalisation puis réouverture de Viim.

Après chaque trajet, extraire la base et les diagnostics avant toute modification de seuil.

Critères obligatoires :

- 3/3 trajets visibles ;
- 3/3 sessions avec résultat terminal ;
- aucun doublon ;
- aucun brouillon supprimé après erreur ;
- distance cohérente avec une référence indépendante ;
- fin automatique ;
- ancien historique toujours visible ;
- indicateur iOS absent pendant au moins dix minutes de veille hors trajet ;

Ces critères forment la porte terrain P0 et autorisent la poursuite de P1. Après P4, un trajet de contrôle supplémentaire vérifie :

- coût relié à la fiche, au prix régional et à leurs versions ;
- mention indicative visible ;
- conversion XOF/CAD reproductible ;
- instantané historique inchangé après rafraîchissement des sources.

Au premier échec, arrêter la matrice, extraire la session, identifier l'étape exacte, ajouter un test de régression, corriger une seule cause puis recommencer le scénario concerné.

Les dix trajets consécutifs restent une condition avant TestFlight, pas avant la build privée.

## 15. Critères d'acceptation globaux

Le blueprint est terminé uniquement si :

- aucune tentative de trajet ne disparaît silencieusement ;
- le logo de navigation ne reste pas affiché en veille ;
- l'utilisateur ne saisit ni consommation ni prix ;
- le véhicule actif correspond à une fiche vérifiée voiture ou moto ;
- le coût utilise la distance validée et un prix régional backend ;
- toute consommation et tout coût sont marqués indicatifs ;
- les montants XOF et CAD citent taux et date ;
- les anciens coûts ne changent pas après une mise à jour ;
- les quatre onglets n'affichent aucune donnée simulée comme réelle ;
- les règles Canada et Burkina sont testées ;
- la suite automatisée, le build physique et la matrice terrain sont verts ;
- les preuves sont archivées dans `qa/artifacts/` et synthétisées dans `qa/test-results.md`.

## 16. Non-objectifs

- reconstruire les trajets dont aucun échantillon n'a été enregistré ;
- permettre la modification, fusion, séparation ou création manuelle de trajets ;
- permettre la saisie du prix ou de la consommation ;
- apprendre une consommation personnelle à partir d'un nombre arbitraire de trajets ;
- prendre en charge les hybrides ou électriques dans cette livraison ;
- gérer plusieurs véhicules actifs ;
- garantir un suivi continu après une fermeture forcée explicite de l'app par l'utilisateur ;
- ouvrir TestFlight avant les dix trajets et les contrôles de sécurité.

## 17. Fichiers principaux concernés

### iOS

- `ios/Viim/App/ViimApp.swift`
- `ios/Viim/Services/LocationService.swift`
- `ios/Viim/Services/MotionActivityService.swift`
- `ios/Viim/Services/TripRecorder.swift`
- `ios/Viim/Services/TripManager.swift`
- `ios/Viim/Persistence/ActiveTripJournal.swift`
- `ios/Viim/Persistence/TripStore.swift`
- `ios/Viim/Onboarding/OnboardingView.swift`
- `ios/Viim/Onboarding/OnboardingStore.swift`
- `ios/Viim/Services/VehicleFuelCatalog.swift`
- `ios/Viim/Features/Accueil/AccueilView.swift`
- `ios/Viim/Features/Conduite/ConduiteView.swift`
- `ios/Viim/Features/Assistance/AssistanceView.swift`
- `ios/Viim/Features/Prevention/PreventionView.swift`
- `ios/Viim/Features/Profil/ProfilView.swift`

### Backend

- `backend/src/server.js`
- `backend/src/routes/`
- `backend/src/services/`
- `backend/src/db/migrations/`
- `backend/test/`

### QA et documentation

- `qa/test-plan.md`
- `qa/test-results.md`
- `qa/known-issues.md`
- `architecture/data-models.md`
- `architecture/api-endpoints.md`
- `features/inscription-onboarding.md`
- `features/profil-parametres.md`

## 18. Socle technique et responsabilité d'exécution

Le dépôt est un monorepo existant ; tous les chemins de la section 17 ont été vérifiés le 2026-07-14.

- iOS : SwiftUI, Swift 5, cible minimale iOS 16, bundle `com.yamstack.viim`.
- Backend : Node.js 22+, Express 5, PostgreSQL, base API `https://api.burktech-ia.com/v1`.
- Stockage iOS : CoreData pour trajets/journaux, Keychain pour token, contacts et fiche médicale.
- Build de départ : `0.1.0 (3)` ; toute installation de validation incrémente `CURRENT_PROJECT_VERSION` et journalise version, build, SHA Git et date de compilation.
- Matériel privé : iPhone 16 appairé. La version exacte d'iOS est capturée dans le préflight du rapport terrain, car l'appareil était indisponible lors de la rédaction.

Rôles :

- builder : code, migrations, tests, build et diagnostics ;
- propriétaire produit/testeur : confirmation de la fiche véhicule, consentement au test d'alerte et conduite des scénarios terrain ;
- exploitation backend : validation des licences de données, imports signés, secrets Coolify et monitoring.

Les phases sont séquentielles `P0 → P1 → P2 → P3 → P4 → P5 → P6 → P7`. Une phase n'est commencée qu'après son critère de sortie. Chaque phase est déclarée dans `tracking/in-progress.md`; toute décision qui change un contrat ci-dessous exige un ADR.

## 19. Seuils exacts de capture et de qualité

La première livraison conserve les seuils déjà testés dans le code. Toute modification exige un test de régression et une preuve terrain ciblée.

### Point exploitable

- coordonnées valides ;
- âge du point `≤ 120 s` pour la route ;
- précision horizontale `0...100 m` ;
- temps strictement croissant ;
- segment rejeté si sa vitesse calculée dépasse `160 km/h` pour une moto ou `220 km/h` pour une voiture.

### Départ

- preuve de mouvement : vitesse GPS `≥ 10 km/h` ou déplacement `≥ max(250 m, marge de précision)` ;
- fenêtre candidat : `15 min` ;
- chemin dense : au moins 3 points, `≥ 30 s` et `≥ 60 m` ;
- chemin sparse arrière-plan : au moins 2 points, `≥ 60 s` et `≥ 250 m` ;
- le premier point exploitable crée immédiatement le journal `candidate`, avant la satisfaction du chemin dense ou sparse.

### Fin et séparation

- arrêt : vitesse `≤ 3 km/h` maintenue pendant `5 min` ;
- armement sans trajet ni mouvement récent : arrêt du GPS après `180 s` ;
- silence `≥ 30 min` : finalisation de l'ancien trajet avant ingestion du nouveau point ;
- trajet persistable : durée `≥ 60 s`, distance `≥ 80 m`, au moins 2 points de route valides.

### Qualité

- au moins 5 points valides pour accepter le rapport qualité ;
- précision moyenne `≤ 50 m` ;
- précision P95 `≤ 100 m` ;
- segments rejetés `≤ 20 %` ;
- score qualité `< 50` : rejet ; `50...64` : à vérifier ; `65...84` : partiel ; `≥ 85` : fiable ;
- distance terrain : écart `≤ 5 %` contre odomètre ou parcours Google Maps documenté ;
- batterie : consommation `< 20 %` sur un trajet continu de 2 heures en mode normal.

### Définition mesurable de « zéro perte silencieuse »

Le rapport QA regroupe les diagnostics par `captureSessionId`. Après expiration de toutes les fenêtres de finalisation :

```text
sessions_sans_resultat = sessions_demarrees - sessions_avec_resultat_terminal
```

Le passage exige `sessions_sans_resultat == 0`, `activeDraftCount == 0` et aucun `failedRetryable` non retenté. Un faux réveil possède aussi un résultat `rejected(armingTimeout)` ; il n'est pas ignoré silencieusement.

### Définition mesurable de l'indicateur corrigé

Avec autorisation « Toujours », téléphone immobile et aucun trajet actif pendant 10 minutes :

- `isMonitoring == false` ;
- `isPassiveWakeupMonitoring == true` ;
- `hasBackgroundActivitySession == false` ;
- aucun événement `location.backgroundSession.start` sans événement de fin correspondant ;
- aucune pastille ou bannière de navigation Viim visible sur l'iPhone, preuve vidéo ou capture horodatée.

## 20. Schéma de données contractuel

Ne jamais modifier `001_initial.sql`. Ajouter des migrations incrémentales et testables.

### Catalogue

```text
vehicle_makes(
  id uuid PK, vehicle_type text CHECK car|motorcycle,
  canonical_name text, normalized_name text,
  created_at timestamptz,
  UNIQUE(vehicle_type, normalized_name)
)

vehicle_models(
  id uuid PK, make_id uuid FK, canonical_name text, normalized_name text,
  created_at timestamptz,
  UNIQUE(make_id, normalized_name)
)

vehicle_specs(
  id uuid PK, model_id uuid FK,
  market_country char(2), year_from smallint, year_to smallint,
  fuel_type text CHECK gasoline|diesel,
  engine_label text, displacement_cc integer NULL,
  trim text, transmission text,
  city_l100 numeric(7,3) NULL, highway_l100 numeric(7,3) NULL,
  combined_l100 numeric(7,3) NOT NULL CHECK combined_l100 > 0,
  test_protocol text, version integer NOT NULL,
  status text CHECK verified|needs_review|archived,
  verified_at timestamptz, created_at timestamptz, updated_at timestamptz
)

vehicle_spec_sources(
  id uuid PK, vehicle_spec_id uuid FK,
  source_name text, source_url text, source_document_hash text,
  licence_name text, published_at timestamptz NULL,
  checked_at timestamptz, is_primary boolean
)
```

La clé métier de déduplication d'une fiche est :

```text
market + vehicle_type + normalized_make + normalized_model +
year_from + year_to + fuel_type + normalized_engine +
normalized_trim + normalized_transmission
```

La normalisation applique Unicode NFKD, minuscules, suppression des accents, espaces et ponctuation. Deux imports portant la même clé créent une nouvelle `version` uniquement si les valeurs ou la source changent.

### Véhicule actif

```text
user_vehicles(
  id uuid PK, user_id uuid FK, vehicle_spec_id uuid FK,
  spec_snapshot jsonb NOT NULL, is_active boolean,
  created_at timestamptz, deactivated_at timestamptz NULL
)
```

Un index unique partiel garantit un seul `is_active=true` par utilisateur.

### Prix et régions

```text
price_regions(
  id uuid PK, country_code char(2), region_code text,
  admin_level smallint, name text, timezone text,
  geometry geometry(MultiPolygon, 4326), source_url text,
  UNIQUE(country_code, region_code)
)

fuel_prices(
  id uuid PK, price_region_id uuid FK,
  fuel_type text CHECK gasoline|diesel,
  price_minor_per_liter bigint CHECK price_minor_per_liter > 0,
  currency char(3) CHECK XOF|CAD,
  effective_at timestamptz, expires_at timestamptz NULL,
  source_name text, source_url text, source_document_hash text,
  verified_at timestamptz, imported_at timestamptz,
  UNIQUE(price_region_id, fuel_type, effective_at, source_document_hash)
)

fx_rates(
  id uuid PK, base_currency char(3), quote_currency char(3),
  rate numeric(20,8) CHECK rate > 0,
  effective_date date, source_name text, source_url text,
  imported_at timestamptz,
  UNIQUE(base_currency, quote_currency, effective_date, source_name)
)
```

La migration vérifie `CREATE EXTENSION IF NOT EXISTS postgis`. Si l'extension n'est pas disponible sur l'instance cible, P2 est bloquée : aucune géolocalisation approximative ou API non licenciée n'est substituée silencieusement.

### Instantané de coût

```text
trip_cost_snapshots(
  trip_id uuid PK FK,
  calculation_version text,
  vehicle_spec_id uuid FK, vehicle_spec_version integer,
  distance_m integer, combined_l100 numeric(7,3),
  estimated_liters numeric(12,5),
  fuel_price_id uuid FK, native_cost_minor bigint,
  native_currency char(3),
  fx_rate_id uuid NULL FK, display_cost_minor bigint NULL,
  display_currency char(3), calculated_at timestamptz
)
```

Les prix et taux référencés sont immuables. Une correction crée une nouvelle ligne source. Un snapshot existant n'est jamais recalculé automatiquement.

## 21. Migration des données existantes

### Backend

- Conserver `daily_summaries.fuel_fcfa` comme champ legacy en lecture seule pendant une version de compatibilité.
- Ajouter aux trajets `vehicle_spec_id`, `fuel_liters`, `cost_minor`, `cost_currency`, `calculation_version` en nullable.
- Ne pas convertir automatiquement les anciens `fuel_fcfa`, car leur prix et leur fiche source ne sont pas prouvés.
- Les anciens trajets affichent « Ancienne estimation non vérifiable » et gardent leur valeur historique uniquement dans le détail legacy.

### iOS

- Décoder `UserProfile.v1`, préserver identité, type, marque, modèle, année et contact Keychain.
- Tenter une correspondance exacte avec le catalogue backend.
- Si une seule fiche vérifiée correspond, enregistrer son ID après confirmation visible.
- Si zéro ou plusieurs fiches correspondent, marquer `needsVehicleSelection=true` et ouvrir le sélecteur au prochain lancement.
- La collecte des trajets continue pendant cette remédiation, mais le coût reste en attente.
- Supprimer l'éditeur local de prix après migration ; ne pas effacer sa valeur avant d'avoir conservé les anciens affichages legacy.

La contradiction « fiche obligatoire/modèle manquant » est résolue ainsi : un nouveau compte motorisé ne termine pas l'inscription sans fiche vérifiée ; un ancien compte peut continuer à enregistrer des trajets, mais ne reçoit aucun nouveau coût avant sélection.

## 22. Contrats API

### Règles communes

- Authentification : `Authorization: Bearer <deviceToken>` ; token aléatoire 256 bits émis à l'inscription, haché en base et stocké dans le Keychain.
- Le backend déduit `userId` du token ; aucun `userId` fourni par le client n'est accepté comme autorité.
- Dates ISO-8601 UTC ; pays ISO 3166-1 alpha-2 ; devises ISO 4217.
- Listes : `limit` par défaut 50, minimum 1, maximum 100 ; `cursor` opaque.
- Réponse liste : `{ "data": [...], "nextCursor": null, "catalogVersion": "..." }`.
- Erreur : `{ "error": { "code": "machine_code", "message": "localized-safe-message", "requestId": "uuid" } }`.
- `400` syntaxe, `401` auth, `404` absent, `409` conflit, `422` validation, `429` limite, `503` dépendance indisponible.
- Catalogue : `ETag` égal à `catalogVersion`, `Cache-Control: private, max-age=86400`, support `If-None-Match`/`304`.

### Fiche véhicule

`PUT /v1/profile/active-vehicle`

```json
{ "vehicleSpecId": "uuid" }
```

Succès `200` :

```json
{
  "data": {
    "activeVehicleId": "uuid",
    "vehicleSpecId": "uuid",
    "vehicleSpecVersion": 1,
    "displayName": "Make Model 2022 1.6L",
    "fuelType": "gasoline",
    "combinedL100": "6.800",
    "source": { "name": "...", "checkedAt": "2026-07-14T00:00:00Z" }
  }
}
```

Une fiche non `verified` retourne `422 vehicle_spec_not_verified`.

### Cotation carburant

`GET /v1/fuel-prices/quote?lat=&lon=&fuelType=&at=&displayCurrency=`

Le backend effectue un point-dans-polygone et choisit la plus petite région contenant le départ. Repli : localité → province/région → pays, sans jamais changer de carburant.

Succès `200` :

```json
{
  "data": {
    "fuelPriceId": "uuid",
    "fuelType": "gasoline",
    "priceMinorPerLiter": 170,
    "currency": "CAD",
    "region": { "code": "CA-ON-TORONTO", "name": "Toronto", "level": "city" },
    "effectiveAt": "2026-07-13T00:00:00Z",
    "verifiedAt": "2026-07-13T12:00:00Z",
    "source": "NRCan",
    "fx": null
  }
}
```

Si aucun prix utilisable n'existe : `404 fuel_price_unavailable`. Si la région n'est pas résolue : `422 region_unresolved`.

### Sync trajet

`POST /v1/trips/batch`, maximum 50 trajets et 512 Ko décompressés :

```json
{
  "deviceId": "uuid",
  "trips": [{
    "id": "uuid",
    "startedAt": "2026-07-14T12:00:00Z",
    "endedAt": "2026-07-14T12:20:00Z",
    "distanceM": 12340,
    "durationSec": 1200,
    "vehicleSpecId": "uuid",
    "vehicleSpecVersion": 1,
    "quality": { "score": 90, "formulaVersion": "trip-quality-v1" },
    "start": { "latRounded3": 43.653, "lonRounded3": -79.383 },
    "costSnapshot": null,
    "payloadHash": "sha256-hex"
  }]
}
```

Réponse `200` avec un résultat par ID : `inserted`, `duplicate` ou `conflict`. Même `id` et même hash = `duplicate` succès logique ; même `id` et hash différent = `conflict`, aucune écriture. Les trajets sont immuables après insertion, sauf ajout unique d'un `costSnapshot` précédemment nul.

La route détaillée reste locale dans cette version. Le backend reçoit uniquement le résumé, la qualité et les coordonnées de départ arrondies à 3 décimales. Le curseur de `GET /v1/sync?cursor=` encode de manière opaque `(received_at,id)` et renvoie les mises à jour dans un ordre stable.

## 23. Fraîcheur, temps et calcul différé

### Prix

- Canada : utilisable si `at - effectiveAt ≤ 10 jours` et `verifiedAt ≤ 10 jours` ; sinon coût en attente.
- Burkina : un arrêté reste juridiquement effectif jusqu'à remplacement, mais Viim exige une vérification de source datant de `≤ 7 jours` ; sinon coût en attente.
- La sélection prend le dernier prix dont `effectiveAt ≤ startedAt`, dans le fuseau IANA de la région.
- Un prix diesel manquant ne se replie jamais sur l'essence, et inversement.

### Taux

- Source principale : taux direct CAD/XOF de la BCEAO.
- Choisir le dernier `effective_date` inférieur ou égal à la date locale du départ, âge maximal 7 jours calendaires.
- Conserver le taux en `numeric(20,8)` et calculer en décimal exact.
- Arrondir une seule fois, à la fin, en mode demi-supérieur : 0 décimale XOF, 2 décimales CAD.
- Si le taux manque, afficher le coût natif et laisser la conversion en attente.
- La Banque du Canada est un contrôle d'exploitation ; aucun taux croisé n'est utilisé par la première build.

### Coût différé

Un trajet sans prix reçoit `costState=pending`. Au retour réseau, le client demande la cotation correspondant au `startedAt`, calcule le snapshot avec `vehicleSpecVersion` du trajet et l'enregistre par transaction compare-and-set uniquement si aucun snapshot n'existe. Un second calcul retourne l'instantané existant. Une correction administrative future ne déclenche aucun recalcul automatique.

Le calcul local est provisoire et utilise uniquement des fiches, prix et taux backend déjà signés par identifiant/version. Lors de `POST /v1/trips/batch`, le backend recalcule avec les mêmes entrées et la même `calculationVersion` :

- résultat identique à l'unité mineure près : le snapshot devient canonique ;
- écart supérieur à une unité mineure : résultat `cost_conflict`, aucun snapshot serveur, diagnostic local et nouvelle tentative après resynchronisation des références ;
- le backend ne remplace jamais silencieusement le coût provisoire.

Les mêmes fixtures JSON de calcul sont exécutées par XCTest et par les tests Node afin d'empêcher une divergence iOS/backend.

## 24. Synchronisation, reprise et rétention

- Déclencheurs : lancement, retour réseau, retour premier plan et tâche arrière-plan opportuniste.
- Backoff : 5 s, 30 s, 2 min, 10 min, puis 1 h maximum avec jitter ±20 %.
- Une erreur `4xx` de validation devient terminale et visible ; `408`, `429` et `5xx` restent retentables.
- Le client ne possède qu'un upload par trip ID à la fois.
- Le serveur est autoritaire sur les fiches, prix et taux ; le client est autoritaire sur le trajet brut local avant première sync.
- Le backend conserve les résumés tant que le compte existe ; `DELETE /v1/users/me/history` supprime trajets et coûts. Les routes détaillées ne quittent pas l'iPhone dans cette version.
- La suppression locale ou l'export doivent rester accessibles depuis le Profil avant toute diffusion externe.

## 25. Assistance : limites et critères exacts

La build privée de fiabilité ne prétend pas livrer la détection de collision tant que P6 n'est pas passée. L'Accueil continue d'afficher « Pas encore actif ».

P6 conserve les contrats existants :

- buffer capteurs pré-impact de 30 s ;
- confirmation GPS dans une fenêtre de 5 s ;
- notification avec délai d'annulation de 60 s ;
- « Je suis en sécurité » annule tout envoi ;
- absence de réponse ou « J'ai besoin d'aide » lance l'alerte ;
- contact 1 immédiat ; contact suivant si aucun statut `delivered` n'arrive sous 5 min ; maximum 3 contacts ;
- `queued`, `sent`, `delivered`, `failed` comme états fournisseur ;
- réponse backend avec `providerMessageId` obligatoire ;
- message reçu par le premier contact moins de 90 s après expiration du délai d'annulation ;
- si le backend retourne `503` ou si le réseau manque, l'app propose un SMS prérempli via MessageUI ; iOS n'autorise pas un envoi SMS silencieux ;
- fiche médicale absente du réseau hors collision confirmée.

Les seuils d'accélération de collision ne sont volontairement pas déclarés valides aujourd'hui. P6 commence par un sous-plan de calibration et la fonction reste désactivée jusqu'à : 20 trajets sans collision sur routes dégradées, faux positifs `< 10 %`, puis test contrôlé sur coussin. Aucun seuil provisoire n'est activé en production.

Les numéros d'urgence proviennent d'une table backend versionnée par pays. Valeurs initiales vérifiées avant livraison : Canada `911`; Burkina police `17`, pompiers `18`. Un numéro non vérifié n'est pas affiché.

## 26. États UI, localisation et accessibilité

La première livraison est en français pour les deux marchés. Toutes les chaînes passent par `Localizable.strings`; l'anglais canadien est une phase ultérieure.

Chaque surface asynchrone possède quatre états :

- chargement avec contenu squelette ou indicateur accessible ;
- données disponibles avec source et date ;
- vide avec explication et prochaine action automatique ou lien Réglages ;
- erreur avec code sûr, bouton Réessayer et conservation des données locales.

Règles :

- Dynamic Type jusqu'aux tailles d'accessibilité sans texte tronqué critique ;
- labels et valeurs VoiceOver ;
- cibles tactiles `≥ 44 × 44 pt` ;
- contraste texte normal `≥ 4,5:1` ;
- devise affichée avec code `XOF` ou `CAD`, jamais symbole ambigu seul ;
- consommation et coût accompagnés de « Estimation indicative » et d'un détail source/date ;
- aucune valeur `0` utilisée pour masquer une donnée absente.

## 27. Preuves et commandes de passage

### Automatisation

```sh
npm run check --prefix backend
npm test --prefix backend
xcodebuild test -project ios/Viim.xcodeproj -scheme Viim \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -derivedDataPath /private/tmp/viim-blueprint-tests \
  CODE_SIGNING_ALLOWED=NO
```

Les migrations sont testées sur base vide puis sur une copie de schéma `001_initial.sql` contenant des utilisateurs, trajets et résumés legacy.

### Build physique

```sh
xcodebuild -project ios/Viim.xcodeproj -scheme Viim \
  -destination 'platform=iOS,name=iPhone de Guy' \
  -derivedDataPath /private/tmp/viim-blueprint-device build
```

L'installation ne commence que lorsque `xcrun devicectl list devices` indique l'iPhone 16 `available`. Le rapport préflight archive modèle, version iOS, build Viim, SHA et heure, sans publier l'identifiant matériel dans ce blueprint.

La fiche privée à semer est dérivée du `UserProfile` déjà présent dans le conteneur installé (type, marque, modèle, année), puis complétée par la sélection moteur/version proposée au propriétaire. Si le profil extrait ne contient pas ces champs, P1 s'arrête avec `vehicle_seed_identity_missing` ; aucune marque ou consommation par défaut n'est créée.

### Distance de référence

Priorité : odomètre du véhicule photographié au départ et à l'arrivée. À défaut, parcours Google Maps fixé avant le départ. Le rapport `tools/qa/s1_trip_report.py --reference-km` calcule l'écart ; passage `≤ 5 %`.

### Artefacts

Pour chaque trajet :

- `qa/artifacts/<scenario>-<date>/s1-trip-report.json` ;
- rapport Markdown associé ;
- base extraite et diagnostics ;
- build/SHA ;
- distance de référence ;
- preuve de l'état de l'indicateur iOS.

`qa/test-results.md` contient le verdict et les liens. « Suite verte » signifie : code de sortie 0 pour `npm run check`, `npm test`, `xcodebuild test` et build physique, puis critères terrain de la section 14 tous satisfaits.
