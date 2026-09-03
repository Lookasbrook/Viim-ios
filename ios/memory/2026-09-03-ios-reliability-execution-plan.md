# Plan d'execution iOS — fiabilite et protection

Date : 2026-09-03
Perimetre : iOS uniquement

## Principe de livraison

Chaque indicateur doit etre classe comme `mesure`, `calcule`, `estime` ou
`indisponible`. Une fonction de securite n'est annoncee comme active qu'apres
validation de toute sa chaine sur appareil reel, y compris ecran verrouille,
absence de reseau, terminaison de l'app et accuse de reception externe.

Les notes subjectives sur 10 sont abandonnees. Chaque valeur doit exposer quatre
preuves independantes : couverture des echantillons, provenance/fraicheur de la
source, plage d'incertitude et statut de validation terrain. Une valeur derivee
herite au minimum de l'incertitude de ses entrees : le cout ne peut donc jamais
etre presente comme plus fiable que les litres estimes qui le produisent.

## Contrat commun des indicateurs

1. `nature` : mesure GPS/capteur, calcul deterministe, estimation de modele ou
   indisponible.
2. `coverage` : pourcentage de temps/distance effectivement couvert par des points
   conformes, plus le plus grand trou observe.
3. `evidence` : version d'algorithme, profil vehicule exact/partiel, identifiant de
   source, date, localite et unite.
4. `uncertainty` : intervalle bas/central/haut ; jamais une fausse precision a une
   valeur unique lorsque les entrees sont ambigues.
5. `validation` : `unvalidated`, `fieldValidated`, `calibrated` ou `rejected`, avec
   taille d'echantillon et erreur mesuree. Les tests unitaires ne font pas passer
   une metrique a `fieldValidated`.

## P0-A — Retablir et prouver la collecte de trajets

Etat logiciel : implemente dans le build 29 ; validation terrain bloquee par
`authorizedWhenInUse` tant que l'utilisateur n'accorde pas `Toujours`.

1. Accorder `Toujours` et la position precise dans les reglages iOS.
2. Verifier `backgroundRefresh=available`, `auth=authorizedAlways`,
   `passiveWakeupRequested=true` et `state=ready` dans le diagnostic.
3. Effectuer trois trajets consecutifs de plus de 5 min et 2 km, telephone
   verrouille et app non visible.
4. Effectuer un trajet hors ligne, puis separer deux cas : terminaison du processus
   par le systeme et fermeture forcee par l'utilisateur. Pour chacun, mesurer le
   delai de reveil, le trou GPS et l'etat du journal ; ne pas exiger la reconstruction
   de points haute frequence qu'iOS n'a jamais livres.
5. Comparer chaque trajet a une trace de reference et compter les trous GPS.

Porte de sortie : 5/5 trajets persistants dans les scenarios ordinaires, aucun
brouillon orphelin, distance a moins de 5 % de la reference, reprise hors ligne
sans perte et aucune fausse transition de permission. Le scenario de fermeture
forcee possede son propre budget de trou et ne peut pas promettre une trace continue.

## P0-B — Rendre la detection de collision reellement protectrice

Etat : moteur `collision-shadow-v2-impact-gps-uncertainty` local de recherche seulement ; alertes
desactivees. Depuis le build 29, son journal est borne a 512 Ko, valide chaque
observation, rend les reprises idempotentes, ecrit atomiquement avec une protection
compatible apres le premier deverrouillage et met en quarantaine toute preuve
corrompue sans l'ecraser. Ce moteur Core Motion n'est pas une base de securite
continue : iOS ne garantit pas ses callbacks quand le processus est suspendu ou
termine.

Chemin de production retenu : SafetyKit, qui remet a une app autorisee un evenement
de collision routiere grave deja detecte par iOS. Ce chemin exige l'entitlement
restreint Apple `com.apple.developer.severe-vehicular-crash-event`, l'autorisation
utilisateur et la designation de Viim comme app tierce receptrice. SafetyKit ne
garantit ni chaque collision, ni une position, ni la couverture moto/velo.

1. Demander l'entitlement SafetyKit a Apple et ne pas ajouter la capability au
   profil de signature avant approbation.
2. Installer le delegate SafetyKit des le lancement ; gerer appareil non pris en
   charge, refus, designation d'une autre app, evenement duplique et position `nil`.
3. Persister immediatement un inbox minimal, idempotent par date/identifiant, puis
   traiter l'evenement hors ligne avec reprise. La livraison Apple d'urgence garde
   toujours la priorite.
4. Afficher une confirmation plein ecran avec compte a rebours, bouton « Je vais
   bien », demande d'aide et appel manuel. Ne jamais appeler automatiquement un
   numero d'urgence public ; limiter l'escalade aux contacts consentis ou a un
   prestataire formellement integre.
5. Rendre l'alerte backend idempotente, chiffree, avec accuse fournisseur reel,
   retries bornes, retour reseau et kill switch serveur. Un `200` backend sans
   preuve de reception fournisseur ne vaut pas livraison.
6. Tester dans le simulateur SafetyKit : lancement apres terminaison, ecran
   verrouille, doublon inter-lancements, position absente, reseau absent, fenetre
   d'appel expiree et autorisation deplacee par une autre app.
7. Continuer le moteur shadow uniquement pour mesurer les limites locales :
   freinages forts, nid-de-poule et chute du telephone, sans coordonnees ni alerte.
   Ne jamais provoquer de collision reelle.

Lot build 30 : l'ecran Assistance separe explicitement les messages manuels de la
calibration capteur et affiche en permanence « Aucune alerte ». Chaque candidat
est lie a l'identifiant exact du trajet et au type de vehicule. Un changement de
trajet ou de vehicule remet le moteur a zero. L'utilisateur peut classer une
observation dans six categories fermees ; l'annotation est stockee dans un second
journal local et ne reecrit jamais la preuve capteur brute. Cette annotation permet
de calculer la precision parmi les candidats revus, mais ni le rappel ni les faux
negatifs.

Prochaine tranche de mesure : enregistrer, par session et sans coordonnees, la duree
du trajet, la duree effectivement surveillee, les interruptions, le nombre de frames,
la part de frames avec vitesse GPS qualifiee et les erreurs capteur. Ecrire un
checkpoint au demarrage, toutes les 30 secondes, a chaque trou et a l'arret afin
qu'une terminaison laisse une session inachevee auditable. Sans ce denominateur,
un petit nombre de candidats ne constitue aucune preuve de fiabilite.

Porte de sortie : entitlement approuve, tests SafetyKit complets, annulation fiable,
livraison de bout en bout prouvee et taux d'echec publie. Avant cette porte,
l'interface reste « detection automatique indisponible » et l'appel manuel reste
accessible.

## P1-A — Estimation avancee de consommation

Etat logiciel : tranche `vehicle-fuel-catalog-v10-evidence-range-elevation`
implementee dans le build 27. Chaque nouveau trajet conserve une plage prudente
basse/centrale/haute pour les litres et le cout, la resolution de la reference,
les multiplicateurs conduite et montee, leur couverture et la version du calcul.
Le denivele GPS n'accorde aucune economie supposee en descente. La plage reste
`non calibree` tant que des pleins reels ne permettent pas de mesurer son erreur.

1. Versionner un profil vehicule structure : annee, marque, modele, finition,
   moteur, transmission, carburant et provenance.
2. Importer les references officielles via HTTPS depuis Ressources naturelles
   Canada et FuelEconomy.gov ; utiliser NHTSA vPIC seulement pour decoder le VIN,
   jamais pour inventer une consommation.
3. Calculer les facteurs de trajet seulement sur des donnees qualifiees : vitesse,
   accelerations/freinages, arrets, duree, pente, temperature et altitude. Chaque
   facteur doit conserver sa couverture et son incertitude.
4. Produire une plage basse/centrale/haute. Revenir a la reference catalogue si
   la couverture dynamique est inferieure a 80 %.
5. Ajouter la calibration volontaire par pleins : kilometrage, litres, date et
   vehicule. Ne jamais melanger deux vehicules ni recalculer silencieusement un
   ancien trajet.
6. Separarer partout litres estimes, cout calcule et prix constate, avec date,
   localite, devise, source et fraicheur.

Porte de sortie : erreur mediane et P90 mesurees sur plusieurs pleins par profil ;
aucune valeur ponctuelle affichee quand le profil est ambigu ; historique
reproductible a partir des preuves figees au trajet.

## P1-B — Prix publics adaptes a la localite

Etat logiciel : tranche Ontario implementee pour le build 28. L'app telecharge
directement le CSV hebdomadaire du gouvernement de l'Ontario, puis choisit le
marche sur l'iPhone. Aucune coordonnee ni ville n'est transmise a Viim pour cette
source. L'URL initiale et l'hote S3 de redirection sont listes explicitement ;
HTTPS, chemin, type MIME, taille maximale, dates, devise, carburant et plage de
prix sont verifies avant persistance. Sans ville issue du geocodage, la moyenne
provinciale est utilisee et annoncee comme `Ontario`. Le dernier prix officiel
encore frais est conserve si le reseau echoue. Le 2026-09-03, la route de secours
`api.burktech-ia.com/v1/fuel-prices/current` repondait `404 not_found` en
production bien que son implementation soit presente dans le depot ; elle ne
fait donc plus partie du chemin critique Ontario.

1. Selectionner la source par pays/region sans transmettre la trace du trajet :
   pays et subdivision suffisent dans la plupart des cas.
2. Autoriser uniquement des domaines HTTPS explicites, imposer timeout, taille
   maximale, validation stricte du schema et refus des redirections non sures.
3. Conserver source, URL, localite, devise, carburant et date de publication.
4. Mettre en cache et garder le dernier prix prouve ; ne jamais remplacer une
   saisie recente par une reponse reseau ancienne.
5. Afficher « perime » ou « indisponible », jamais un prix par defaut presente
   comme local.

Porte de sortie : tests de concurrence, donnees malformees, panne reseau, cache,
changement de localite et changement de carburant. La tranche Ontario couvre ces
contrats en tests ; restent la verification manuelle sur appareil et l'ajout de
sources officielles propres a chaque autre juridiction.

## P1-C — Catalogue vehicules et photos reelles

Etat logiciel : premiere tranche implementee dans le build 27. Pour les voitures,
le profil peut maintenant conserver une variante FuelEconomy.gov exacte, versionnee
et sourcee. La recherche HTTPS n'envoie que l'annee, la marque et le modele ; elle
refuse un domaine, une redirection, un type MIME, une taille ou une identite non
conformes. L'utilisateur choisit explicitement la variante dans Profil. Une reponse
reseau obsolete ne peut pas ecraser un profil modifie. Les valeurs generiques restent
affichees comme indicatives. Aucune fiche FuelEconomy.gov n'est appliquee aux motos.

Etat photos : les 18 fichiers locaux ont ete verifies le 2026-09-03 via l'API
Wikimedia Commons. Auteur, source HTTPS, licence, URL de licence, empreinte SHA-1,
date de controle, modification et methode `photograph` sont maintenant obligatoires
dans le manifeste executable. Les credits et liens sont visibles dans l'app. Les
alias susceptibles de montrer un trim voisin sont refuses. La couverture reste
partielle : l'illustration neutre est volontaire quand aucune preuve exacte n'existe.
Deux nouvelles photographies reelles ont ete ajoutees : Suzuki GN 125 et Honda
Wave 110 Special Edition 2026. La Wave est bornee a l'annee 2026. Les recherches
TVS HLX 125 et Boxer BM 100 n'ont retourne aucune preuve assez precise : aucun asset
n'a ete ajoute pour elles.

1. Remplacer les libelles libres par des identifiants stables et suggestions
   canoniques, tout en laissant l'utilisateur confirmer son vehicule exact.
2. Lier chaque reference carburant a une ligne source versionnee et a son niveau
   de resolution ; afficher une plage si plusieurs motorisations correspondent.
3. Ajouter uniquement des photographies reelles dont la licence autorise l'usage
   dans l'app : fichier original, auteur, source, licence, modele et generation.
4. Utiliser des API/catalogues publics ou kits presse constructeur apres controle
   de licence. Interdire les images generees par IA et les correspondances par
   simple sous-chaine.
5. Fournir une image neutre quand aucune photo exacte et licite n'existe ; ne pas
   montrer une photo d'un modele voisin.

Porte de sortie : 100 % des images ont une fiche de provenance, aucun test de
modele ambigu ne retourne une photo ou une consommation exacte, controle manuel
des vehicules les plus utilises au Burkina Faso et au Canada.

## P1-D — Persistance et migrations

1. Passer du modele Core Data programme a un modele versionne.
2. Ajouter migrations legeres, tests d'ouverture de copies des stores historiques
   et sauvegarde recuperable avant migration.
3. Remplacer les `precondition` au chargement par un mode de recuperation qui ne
   detruit jamais le store ni le journal actif.
4. Versionner aussi les algorithmes de qualite, score, carburant et collision.

Porte de sortie : ouverture et migration de chaque fixture historique, interruption
simulee pendant migration, aucune suppression automatique de donnees.

## Ordre d'execution recommande

1. Validation terrain P0-A sur le build 30.
2. Demande d'entitlement et prototype SafetyKit P0-B ; collecte shadow uniquement
   comme instrumentation secondaire.
3. Schema vehicule versionne, puis imports officiels et photos P1-C.
4. Modele de consommation/calibration par pleins P1-A.
5. Etendre les connecteurs de prix locaux securises P1-B au-dela de l'Ontario.
6. Core Data versionne P1-D avant toute evolution destructive du schema.
7. Release TestFlight limitee, tableau de sante de collecte, puis ouverture
   progressive seulement si toutes les portes sont franchies.

## Etat d'execution verifie

- Build 30 signe, installe et confirme `0.1.0 (30)` dans le bundle sur l'iPhone 16. Son lancement
  est refuse uniquement parce que l'iPhone est verrouille.
  Avant installation, Application Support a ete sauvegarde et son SQLite controle
  `ok`. Apres installation sans lancement, SQLite, WAL et SHM sont identiques octet
  pour octet, y compris apres l'installation finale du build 27 : la migration du
  store reel attend encore le deverrouillage.
- 259/259 tests iOS reussis ; 0 echec et 0 test ignore. Cela inclut une migration
  SQLite reelle d'un store sans les nouveaux champs de preuve carburant.
- Permission appareil encore `authorizedWhenInUse` : la porte terrain P0-A reste
  ouverte et exige une action utilisateur dans les reglages iOS.
- Collision shadow sans alerte et sans reseau : base de calibration seulement.
- Fiche vehicule officielle FuelEconomy.gov : schema, client securise, provenance,
  selection utilisateur, invalidation et protection contre les courses reseau
  testes. Restent NRCan, la couverture moto licite, les plages multi-variantes et
  l'extension de la couverture photo a de nouveaux modeles.
- Prix Ontario build 28 : lecture directe du CSV officiel, selection locale sans
  transmission de ville, controles de transport et de preuve, moyenne provinciale
  de repli et conservation du dernier prix encore valide. Le CSV reel et sa
  redirection officielle ont ete controles ; les tests complets sont verts.
- Apres installation du build 30, les copies non destructives du store appareil
  avant/apres sont identiques au SHA-256, passent `PRAGMA integrity_check=ok` et
  contiennent toujours 126 trajets. Le demarrage et les ecrans Assistance/prix sur
  appareil restent a verifier apres deverrouillage.
- Collision build 30 : perte de vitesse qualifiee par l'incertitude GPS, profil
  charge au lancement headless, arret fail-closed quand Core Location ne collecte
  plus, journal atomique/protege/borne avec quarantaine et retry en memoire. Les
  observations portent l'UUID exact du trajet et le type de vehicule ; leurs
  etiquettes sont conservees separement. L'interface ne presente plus un contact
  configure comme une detection active et maintient le statut « Aucune alerte ».
  La suite iOS passe 259/259 ; aucune alerte automatique n'est activee.

## References primaires — architecture collision

- Apple SafetyKit et entitlement collision grave :
  https://developer.apple.com/documentation/safetykit
- Apple, delegate livre au lancement et deduplication des evenements :
  https://developer.apple.com/documentation/safetykit/sacrashdetectiondelegate
- Apple DTS, Core Motion ne fournit pas un mode d'execution continue en arriere-plan :
  https://developer.apple.com/forums/thread/841001
- Apple, niveaux de protection de fichiers :
  https://developer.apple.com/documentation/foundation/fileprotectiontype

## Prochaines actions ordonnees et responsables

1. **Utilisateur — aujourd'hui :** deverrouiller l'iPhone, ouvrir le build 30 et
   accorder Position `Toujours` + precise. Sans cela, aucun correctif logiciel ne
   peut prouver la capture ecran verrouille.
2. **Validation terrain — 1 jour :** executer les cinq scenarios P0-A, extraire le
   journal et mesurer completude, trous GPS et ecart de distance. Tout ecart > 5 %
   bloque la suite de diffusion.
3. **Collision shadow — prochaine tranche logicielle puis 2 a 4 semaines de conduite :**
   ajouter d'abord le journal de couverture de session. Collecter ensuite les
   etiquettes volontaires et publier le taux de candidats par 1 000 km, le taux de
   revue et la precision observee parmi les candidats revus. Le rappel et les faux
   negatifs exigent un jeu de verite terrain independant en laboratoire ou les
   evenements de test SafetyKit ; ils ne doivent jamais etre deduits du shadow.
   Aucun SOS automatique avant seuils signes.
4. **Catalogue officiel — prochaine tranche logicielle :** ajouter NRCan avec le
   meme schema de preuve, puis une plage basse/haute quand plusieurs variantes
   restent possibles. NHTSA vPIC reste limite a l'identite VIN.
5. **Photos — en parallele du catalogue, pas d'IA :** etendre le manifeste deja
   obligatoire a chaque nouvelle image (modele, generation, auteur, URL, licence,
   empreinte et date de verification). Une vignette neutre couvre les manques.
6. **Consommation — apres resolution exacte du vehicule :** figer reference et
   version du modele au trajet, ajouter plage d'incertitude et calibration par pleins,
   puis publier erreur mediane et P90.
7. **Persistance — avant tout changement Core Data destructif :** modele versionne,
   fixtures historiques, sauvegarde et recuperation sans suppression.
8. **Diffusion :** TestFlight restreint seulement apres P0-A ; promesse de detection
   collision seulement apres la chaine capteur-confirmation-livraison complete.
