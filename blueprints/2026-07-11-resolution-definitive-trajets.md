# Blueprint - Resolution definitive des trajets absents - 2026-07-11

## Verdict apres execution logicielle

Le candidat `0.1.0 (3)` est installe sur l'iPhone. Les etapes 0 a 7 sont executees et verifiees : suite iOS complete verte, build physique vert, migration CoreData reussie, six trajets historiques conserves et accessibles par la source UI, journal candidat durable et persistance retentable.

Le probleme reste en validation, et non « resolu », jusqu'a l'execution de l'Etape 8 sur de nouveaux trajets reels. Les donnees des trajets deja manques ne peuvent pas etre reconstruites.

Deux defauts distincts doivent etre fermes ensemble :

1. Des trajets ne franchissent pas toute la chaine de capture jusqu'a CoreData.
2. Les trajets deja presents dans CoreData ne sont pas accessibles apres minuit, car l'UI ne charge que les trajets du jour.

Les trajets manques sans brouillon ni samples ne sont pas reconstructibles. Le but de ce plan est qu'aucune nouvelle tentative ne disparaisse silencieusement.

## Objectif mesurable

Une tentative de trajet doit toujours finir dans un etat terminal auditable :

- `persisted` : trajet enregistre et visible ;
- `rejected` : trajet refuse avec une raison explicite ;
- `interrupted` : trajet interrompu puis recupere ou signale ;
- `failedRetryable` : ecriture echouee, brouillon conserve pour nouvelle tentative.

Le ticket DATA-003 ne peut etre ferme qu'apres 10 scenarios terrain consecutifs sans perte silencieuse.

## Architecture cible

```text
CoreMotion / reveil significatif / lancement manuel
                         |
                         v
              TripDetectionCoordinator
                         |
          +--------------+---------------+
          |              |               |
          v              v               v
       passive         arming         recording
                          |               |
                 grace GPS 180 s     stationaryPending
                          |               |
                          +-------+-------+
                                  v
                         ActiveTripJournal
                     candidate puis trajet actif
                                  |
                                  v
                            TripRecorder
                                  |
                    TripPersistenceOutcome
           +--------------+-------+-------------+
           |              |                     |
        persisted      rejected          failedRetryable
           |              |                     |
    supprimer draft  archiver raison       garder draft
           |                                    |
           +----------------+-------------------+
                            v
                 TripManager + historique UI
```

Invariants non negociables :

- Une annonce CoreMotion `stationary` ne peut pas couper le GPS pendant les 180 secondes d'armement.
- `CLBackgroundActivitySession` reste vivante pendant `arming`, `recording` et `stationaryPending` sur iOS 17+.
- Le premier sample candidat est journalise avant d'attendre le deuxieme.
- Un brouillon n'est jamais supprime apres une erreur de sauvegarde.
- Toute session de capture possede un `captureSessionId` et un resultat terminal.
- Le resume du jour reste journalier, mais la liste des trajets recents n'est pas filtree sur la date du jour.

## Etape 0 - Baseline et identite du build

Fichiers : projet Xcode, `ViimDiagnostics.swift`, `tools/qa/s1_trip_report.py`.

1. Archiver l'extraction actuelle comme baseline : 6 trajets, 0 trajet du jour, dernier trajet le 2026-07-08.
2. Incrementer `CFBundleVersion` avant toute nouvelle installation.
3. Journaliser au lancement : version, build, date de compilation et SHA Git court.
4. Ajouter ces informations au rapport S1 afin de prouver quel binaire a produit chaque log.
5. Interdire une validation terrain si le build extrait ne correspond pas au build annonce.

Critere de sortie : le rapport affiche sans ambiguite le build installe et son SHA.

## Etape 1 - Remplacer l'orchestration SwiftUI par une machine d'etat

Fichiers principaux : `ViimApp.swift`, nouveau `TripDetectionCoordinator.swift`, `LocationService.swift`, tests du coordinateur.

1. Deplacer `reconcileAutomaticTracking()` et le timer stationnaire hors de `AppLaunchView`.
2. Creer un coordinateur possede par `ViimApp`, actif meme lorsque l'interface n'est pas affichee.
3. Implementer un reducer testable avec les etats `passive`, `arming`, `recording`, `stationaryPending` et `blocked`.
4. A l'entree en `arming`, demarrer le GPS, la session d'activite arriere-plan et une grace de 180 secondes.
5. Pendant cette grace, ignorer les annonces CoreMotion stationnaires. Seul le timeout sans preuve de mouvement peut revenir a `passive`.
6. En `recording`, une annonce stationnaire ouvre une periode de finalisation ; un nouveau mouvement l'annule.
7. Au relancement iOS en arriere-plan, recreer immediatement les services Core Location requis avant de traiter les points en attente.
8. Sur iOS 16, conserver le fallback `UIBackgroundModes.location` + `allowsBackgroundLocationUpdates`.

Critere de sortie : la sequence observee sur l'iPhone `movement -> start GPS -> stationary a +5 s` ne peut plus produire `location.stop` avant la fin de la grace.

## Etape 2 - Journaliser des le premier candidat

Fichiers principaux : `ActiveTripJournal.swift`, modele CoreData, `LocationService.swift`, tests du journal.

1. Ajouter une phase au brouillon : `candidate` ou `active`.
2. Creer le brouillon et enregistrer le premier sample des qu'un depart plausible est observe.
3. Ajouter les samples suivants au meme `captureSessionId`.
4. Promouvoir le brouillon en `active` lorsque les regles dense ou sparse sont satisfaites.
5. A la recuperation :
   - promouvoir et terminer un candidat devenu suffisamment fiable ;
   - rejeter explicitement un candidat insuffisant ou expire ;
   - recuperer un trajet actif sans doublon.
6. Nettoyer les candidats orphelins uniquement apres avoir enregistre leur resultat terminal.

Critere de sortie : tuer l'app apres le premier point ne laisse plus une absence totale de preuve.

## Etape 3 - Rendre la persistance atomique et retentable

Fichiers principaux : `TripManager.swift`, `TripRecorder.swift`, `TripStore.swift`, tests de persistance.

1. Faire retourner a `persistCompletedTrip` un enum `TripPersistenceOutcome` :
   - `persisted` ;
   - `duplicate` ;
   - `rejected(reason)` ;
   - `failedRetryable(errorCode)`.
2. Supprimer le brouillon seulement pour `persisted`, `duplicate` ou `rejected` correctement journalise.
3. Sur `failedRetryable`, conserver le brouillon et retirer son ID de `processedTripIDs` pour autoriser un nouvel essai.
4. Relancer les brouillons en echec au demarrage et au retour au premier plan.
5. Conserver la protection `tripExists(id:)` pour rendre la reprise sans doublon.
6. Ajouter un test avec un contexte CoreData qui echoue a la sauvegarde, puis reussit au second essai.

Critere de sortie : une erreur CoreData simulee ne supprime jamais le brouillon et la seconde tentative cree exactement un trajet.

## Etape 4 - Supprimer la perte silencieuse

Fichiers principaux : `ViimDiagnostics.swift`, modele de telemetrie locale, `TripManager.swift`, carte de statut Accueil.

1. Journaliser chaque transition avec `captureSessionId`, etat precedent, nouvel etat et raison.
2. Enregistrer localement un resultat terminal pour chaque tentative.
3. Afficher dans l'Accueil le dernier resultat :
   - trajet enregistre ;
   - trajet trop court ;
   - GPS insuffisant ;
   - trajet interrompu ;
   - sauvegarde en attente de nouvel essai.
4. Afficher les prerequis mesurables : autorisation, precision exacte et mode economie d'energie.
5. Etendre le rapport S1 pour detecter automatiquement les sessions sans resultat terminal.

Critere de sortie : `captureSessionsWithoutOutcome` vaut toujours 0 apres une periode de test terminee.

## Etape 5 - Donner acces a tous les trajets enregistres

Fichiers principaux : `TripManager.swift`, `TripStore.swift`, `AccueilView.swift`, tests du store et de presentation.

1. Garder `todayTrips` uniquement pour le resume du jour.
2. Ajouter `recentTrips`, sans filtre de date, pour les trois dernieres lignes de l'Accueil.
3. Remplacer « Tous les trajets du jour » par un historique groupe par date.
4. Charger des lignes legeres sans decoder toutes les polylines ; charger le trajet complet lors de l'ouverture du detail.
5. Afficher la date sur chaque trajet afin d'eviter la confusion entre aujourd'hui et l'historique.
6. L'etat vide global ne s'affiche que si CoreData ne contient reellement aucun trajet.

Critere de sortie : avec la base actuelle, les 6 trajets historiques sont visibles meme si `todayTrips` vaut 0.

## Etape 6 - Couverture de tests obligatoire

```text
CODE PATHS                                      PREUVES UTILISATEUR

Coordinateur                                    Accueil
|- mouvement -> arming                          |- trajet ancien visible
|- stationary a +5 s -> reste arming            |- trajet persiste visible immediatement
|- timeout 180 s sans mouvement -> passive       |- rejet explique
|- mouvement pendant settling -> recording       `- erreur de sauvegarde indiquee
`- relancement background -> services recrees

Journal / persistance                            Terrain iPhone
|- premier sample -> candidate                   |- ecran verrouille
|- recovery candidate                            |- app non ouverte
|- save failure -> draft conserve                |- kill puis reouverture
|- retry -> exactly one trip                     |- trajet long
`- rejection -> terminal outcome                 `- passage de minuit
```

Tests unitaires obligatoires :

1. CoreMotion stationnaire 5 secondes apres le demarrage ne coupe pas le GPS.
2. La grace expire apres 180 secondes sans preuve et ferme la session d'arriere-plan.
3. Un point de mouvement, meme grossier mais coherent, maintient l'armement.
4. Le premier sample cree un candidat persistant.
5. Un candidat survit a une recreation des services.
6. Une sauvegarde echouee garde le brouillon et peut etre retentee.
7. La reprise n'insere aucun doublon.
8. Un rejet qualite produit une raison terminale.
9. `recentTrips` retourne des trajets anterieurs a aujourd'hui.
10. Le resume du jour reste filtre sur aujourd'hui.
11. L'historique ne decode pas la polyline avant l'ouverture du detail.
12. Le rapport QA echoue si une session n'a aucun resultat terminal.

Commandes de validation logicielle :

```bash
xcodebuild test -project ios/Viim.xcodeproj -scheme Viim \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -derivedDataPath /private/tmp/viim-dd-data003-final \
  CODE_SIGNING_ALLOWED=NO

xcodebuild -project ios/Viim.xcodeproj -scheme Viim \
  -destination 'platform=iOS,name=iPhone de Guy' \
  -derivedDataPath /private/tmp/viim-dd-data003-device build
```

Critere de sortie : suite complete verte, build physique vert, aucun test ignore sur la chaine critique.

## Etape 7 - Installation controlee

1. Noter version, build, SHA et heure avant installation.
2. Installer uniquement le produit de l'Etape 6.
3. Lancer une fois l'app et extraire immediatement les logs.
4. Verifier `app.launch`, `authorizedAlways`, `location.passiveWakeups.start` et le build attendu.
5. Verifier sur l'iPhone : Position exacte activee et Mode economie d'energie desactive pendant la validation.

Critere de sortie : l'extraction de l'iPhone prouve que le bon build est installe avant le premier trajet.

## Etape 8 - Matrice terrain bloquante

Executer dans cet ordre, avec extraction apres chaque trajet :

| Scenarios | Repetitions | Succes obligatoire |
|---|---:|---|
| App ouverte puis ecran verrouille | 3 | `backgroundSession.start`, `trip.begin`, `trip.persisted`, visible, distance +/-5 % |
| App non ouverte avant le depart, autorisation Toujours | 3 | reveil significatif, armement, persistance, visible |
| App tuee en plein trajet puis rouverte manuellement | 2 | portion pre-kill recuperee, etat interrompu explicite, aucun doublon |
| Trajet de plus de 30 minutes | 1 | aucune coupure ni fusion incorrecte |
| Trajet traversant minuit | 1 | visible dans l'historique et resume attribue au bon jour |
| Faux reveil sans trajet, telephone immobile | 1 controle | aucun trajet fantome, GPS arrete en 180 s |

Limite iOS explicite : apres une fermeture forcee par l'utilisateur, le plan garantit la recuperation des donnees journalisees lors de la reouverture, pas un suivi continu garanti pendant que l'app reste forcee fermee.

Regle STOP : au premier echec, ne pas modifier plusieurs seuils. Extraire la session concernee, identifier l'etape exacte sans resultat, ajouter le test de regression, corriger une cause, puis reprendre la matrice depuis le debut.

## Definition de « resolu »

DATA-003 et GPS-101 peuvent etre fermes uniquement si toutes ces conditions sont vraies :

- 10/10 scenarios de trajet produisent un resultat terminal attendu ;
- 0 session de capture silencieusement perdue ;
- 0 brouillon supprime apres erreur retentable ;
- 0 doublon apres recuperation ;
- 0 arret GPS pendant la grace d'armement ;
- tous les trajets persistes sont accessibles dans l'UI ;
- chaque preuve mentionne version, build et SHA ;
- suite iOS complete et build physique reussis ;
- preuves brutes archivees dans `qa/artifacts/` et synthesees dans `qa/test-results.md`.

Tant qu'une condition manque, le statut reste « En validation », jamais « Resolu ».

## Ce qui existe deja et sera reutilise

- `LocationService` et ses regles de candidat dense/sparse ;
- `CLBackgroundActivitySession` deja presente dans le code local ;
- `ActiveTripJournal` et les entites CoreData de brouillon ;
- `TripRecorder` et la protection de doublon par identifiant ;
- `TripQualityEngine` et ses raisons de rejet ;
- `tools/qa/s1_trip_report.py` pour l'extraction appareil.

Le plan ne remplace pas ces composants. Il corrige leur orchestration, leurs transactions et leur observabilite.

## Hors perimetre

- Reconstruction des trajets deja manques : aucune donnee locale n'existe pour les recreer.
- WhatsApp WA-103 : independant de la capture GPS.
- Score assureur, internationalisation et synchronisation backend : bloques jusqu'a fermeture de DATA-003.
- Refonte visuelle generale : seule l'accessibilite de l'historique et des erreurs de capture est incluse.

## References Apple

- [Handling location updates in the background](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background) : suspension, session d'activite arriere-plan et recreation des services apres relancement.
- [CLLocationManager.startUpdatingLocation](https://developer.apple.com/documentation/corelocation/cllocationmanager/startupdatinglocation()) : limites de livraison pendant suspension ou terminaison et exigences du mode location en arriere-plan.

## Ordre d'execution

Le travail principal est sequentiel : Etapes 0 -> 1 -> 2 -> 3 -> 4 -> 6 -> 7 -> 8.

L'Etape 5 peut etre developpee en parallele apres stabilisation des contrats `TripManager`/`TripStore`, mais la worktree actuelle contient de nombreux changements non commites. Dans cet etat, une execution sequentielle est plus sure pour eviter les conflits et les installations provenant du mauvais build.
