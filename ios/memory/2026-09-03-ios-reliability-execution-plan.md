# Plan d'execution iOS — fiabilite et protection

Date : 2026-09-03
Perimetre : iOS uniquement

## Principe de livraison

Chaque indicateur doit etre classe comme `mesure`, `calcule`, `estime` ou
`indisponible`. Une fonction de securite n'est annoncee comme active qu'apres
validation de toute sa chaine sur appareil reel, y compris ecran verrouille,
absence de reseau, terminaison de l'app et accuse de reception externe.

## Critique du rapport initial

Le diagnostic est utile, mais plusieurs conclusions devaient etre resserrees avant
de piloter une fonction de protection :

1. `authorizedWhenInUse` ne signifie pas structurellement « aucune collecte ».
   Apple autorise une collecte en arriere-plan tant qu'une activite de localisation
   When-In-Use reste active et visible. En revanche, une app terminee n'est pas
   relancee pour les changements significatifs, visites ou regions sans `Always`.
   Dans cet incident, la panne vient donc du cumul entre la politique Viim qui
   invalidait/desactivait ses sessions et l'absence de `Always`, pas du statut seul.
2. L'absence de lignes dans `ViimDiagnostics.log` est un indice, pas une preuve de
   non-execution : le fichier est asynchrone et rotatif. Une preuve de sante doit etre
   synchrone, bornee, atomique et independante du journal de debogage.
3. `196/196` ou `272/272` prouve une regression logicielle evitee, pas la capture
   ecran verrouille. La validation terrain reste une porte distincte.
4. Conserver `CLBackgroundActivitySession` augmente les chances de continuite mais
   ne garantit ni l'absence de suspension, ni la relance apres fermeture forcee.
5. Un cout derive de litres estimes ne peut pas etre annonce plus fiable que les
   litres. Il doit heriter de leur intervalle d'incertitude, puis ajouter celle du prix.
6. Une recuperation tardive ne doit jamais rafraichir artificiellement la date de
   derniere collecte. Il faut separer date d'enregistrement et date de la preuve.
7. SafetyKit couvre les collisions routieres graves detectees par Apple sur appareil
   compatible. Il ne constitue ni une detection universelle, ni une couverture moto
   ou velo garantie, et exige un entitlement restreint.

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

Etat logiciel : implemente depuis le build 31 et conserve dans le build 32 ; validation terrain bloquee par
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

Lot build 31 : un journal de couverture borne et protege enregistre, par session et
sans coordonnees, le trajet exact, l'algorithme, les frames Core Motion, la part de
frames avec vitesse GPS qualifiee, les interruptions, les erreurs capteur et les
candidats. Il ecrit un checkpoint au demarrage, toutes les 30 secondes, a chaque
trou, erreur, candidat et arret. Une terminaison laisse ainsi une session non cloturee
auditable. Les compteurs ne peuvent que progresser et une session terminee ne peut
pas etre rouverte. L'ecran de revue affiche uniquement le resume de la version
d'algorithme courante et rappelle que ces chiffres mesurent la collecte, pas la
detection des collisions.

Prochaine tranche de mesure : joindre ces sessions aux trajets finalises pour publier
le ratio duree surveillee/duree conduite et les candidats par 1 000 km. Definir avant
la collecte les seuils de validation, puis exporter un rapport agrege sans trace GPS.

Porte de sortie : entitlement approuve, tests SafetyKit complets, annulation fiable,
livraison de bout en bout prouvee et taux d'echec publie. Avant cette porte,
l'interface reste « detection automatique indisponible » et l'appel manuel reste
accessible.

## P0-C — Unifier l'etat de protection et la preuve de livraison

Le rapport confond encore par endroits « suivi active », « capteurs disponibles » et
« protection operationnelle ». Un seul etat calcule doit alimenter Accueil,
Assistance et les diagnostics. Aucune vue ne doit reconstruire sa propre notion de
disponibilite a partir d'un sous-ensemble de permissions.

1. Definir un `ProtectionReadinessSnapshot` sans donnee de position : autorisation
   localisation, position precise, actualisation en arriere-plan, reveils passifs,
   collecte recente, disponibilite/autorisation SafetyKit, etat du canal backend et
   derniere preuve de livraison fournisseur.
2. Distinguer `indisponible`, `configuration requise`, `surveillance des trajets`,
   `evenement detecte`, `alerte envoyee` et `alerte recue`. Un contact configure ne
   constitue jamais une detection active ; un `HTTP 200` ne constitue jamais un
   message recu.
3. Afficher une sante de collecte sur 7 jours : dernier reveil, dernier echantillon,
   trajets persistants/rejetes/recuperes, sessions shadow non cloturees et principale
   cause de perte. Les logs restent locaux, bornes et sans trace GPS exportee par
   defaut.
4. Ajouter un test d'interface pour chaque combinaison P0 : `WhenInUse`, `Always`,
   position approximative, actualisation desactivee, capteur indisponible, backend
   en panne et livraison non accusee.

Lot build 32 : `ProtectionReadinessSnapshot` devient l'unique contrat consomme par
Accueil et Assistance pour le suivi de trajet, la collision automatique, les
contacts et le reseau. Le snapshot distingue configuration requise, veille passive
et collecte active. Il maintient la collision automatique a `unavailable` et refuse
de transformer des contacts valides en livraison prouvee : ils restent
`configuredUnverified` sans accuse fournisseur. Une configuration melant contacts
valides et invalides est maintenant signalee. Chaque changement semantique produit
une ligne locale `protection.readiness` sans position ni numero de telephone.
Les echecs de lecture Keychain sont maintenant `unavailable` au lieu d'etre
confondus avec une liste vide, une configuration mixte bloque le test manuel et
les reponses HTTP positives sont presentees comme des demandes acceptees par le
serveur, jamais comme une preuve de reception WhatsApp.

Restent dans P0-C : la sante persistante sur 7 jours, la preuve fournisseur et les
tests d'interface sur appareil. Le snapshot est le socle de ces ajouts, pas leur
substitut.

Lot build 33 : journal de sante JSON local, synchrone, atomique et protege. Le
detail est borne a 7 jours ; au plus deux ancres historiques non sensibles
(debut d'observation et derniere preuve) sont conservees afin qu'une relance apres
8 jours sans donnees ne ressemble pas a une premiere installation. Il ne contient
ni coordonnee, ni vitesse, ni contact, ni identifiant de
trajet. Les preuves proviennent de la reception GPS, des echantillons acceptes, du
signal Core Motion explicitement classe, des demarrages de trajet et des resultats
de persistance. Une recuperation conserve separement l'heure de recuperation et
l'heure du trajet et ne rend jamais la collecte « fraiche ». Les dates futures,
reboots et divergences entre horloge murale et uptime ne peuvent pas produire un
etat vert. Accueil et Assistance consomment le meme snapshot ; la veille passive
reste neutre tant qu'aucun echantillon recent n'est prouve. Les alertes manuelles
sont bloquees hors ligne au lieu d'afficher « Pret hors ligne ».

Porte de sortie : le meme snapshot produit le meme statut sur tous les ecrans ; tout
etat rassurant possede une preuve fraiche ; une panne silencieuse de plus de 24 h
devient visible lors de la prochaine ouverture.

## P1-A — Estimation avancee de consommation

Etat logiciel : tranche `vehicle-fuel-catalog-v11-fill-up-calibration`
implementee jusqu'au build 41. Chaque nouveau trajet conserve une plage prudente
basse/centrale/haute pour les litres et le cout, la resolution de la reference,
les multiplicateurs conduite et montee, leur couverture et la version du calcul.
Le denivele GPS n'accorde aucune economie supposee en descente.

Lot build 41 : saisie volontaire de pleins complets dans Profil, persistance locale
Core Data `ViimBuild41` et migration testee depuis l'immuable `ViimBuild33`. Une
calibration exige au moins trois pleins pour former deux intervalles valides. Les
dates et odometres doivent progresser, les bornes voiture/moto sont distinctes,
les aberrations sont exclues et une calibration trop eloignee de la reference de
depart est refusee. L'identite comprend type, marque, modele, annee, carburant et
variante officielle : aucune preuve ne traverse un changement de vehicule. Chaque
futur trajet fige la consommation calibree, le nombre d'intervalles, la distance
couverte et la date de la derniere preuve dans son identifiant de source ; aucun
trajet historique n'est reecrit.

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
5. [Livre build 41] Ajouter la calibration volontaire par pleins : kilometrage,
   litres, date et vehicule. Ne jamais melanger deux vehicules ni recalculer
   silencieusement un ancien trajet.
6. Separarer partout litres estimes, cout calcule et prix constate, avec date,
   localite, devise, source et fraicheur.

Porte de sortie restante : erreur mediane et P90 mesurees sur plusieurs pleins par profil ;
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

Etat logiciel : le build 40 remplace le modèle d’exécution programmatique par un
`Viim.xcdatamodeld` versionné. Sa version initiale immuable `ViimBuild33` est
bloquée par un test d’égalité exacte des empreintes des sept entités avec le
schéma déjà installé. Une sauvegarde brute SQLite/WAL/SHM précède toute migration
future ; son échec bloque l’ouverture migrante. En mode récupération, l’utilisateur
peut exporter ces fichiers sans modification du store source.

1. Passer du modele Core Data programme a un modele versionne.
2. Ajouter migrations legeres, tests d'ouverture de copies des stores historiques
   et sauvegarde recuperable avant migration.
3. Remplacer les `precondition` au chargement par un mode de recuperation qui ne
   detruit jamais le store ni le journal actif.
4. Versionner aussi les algorithmes de qualite, score, carburant et collision.

Porte de sortie : ouverture et migration de chaque fixture historique, interruption
simulee pendant migration, aucune suppression automatique de donnees.

Reste à franchir : ajouter une fixture de chaque futur schéma dès sa livraison et
tester explicitement les migrations interrompues dès qu’une deuxième version du
modèle existera. Avec une seule version historique aujourd’hui, aucune chaîne
multi-étapes ne peut encore être exercée honnêtement.

## P1-E — Rendre tous les indicateurs coherents et auditables

1. Appliquer le contrat commun a Distance, Duree, Vitesses, Dynamique, Arrets,
   Denivele, Consommation, Cout et Scores. Chaque carte affiche nature, couverture,
   provenance, fraicheur et plage d'incertitude quand elle influence une decision.
2. Renommer le « ralenti » en « temps a tres basse vitesse » : le GPS ne connait pas
   l'etat du moteur. Ne parler de ralenti moteur qu'avec une source vehicule directe
   telle qu'OBD, explicitement consentie et qualifiee.
3. Conserver accelerations/freinages issus de la vitesse GPS comme estimation. Core
   Motion peut confirmer un transitoire, mais ne devient une mesure longitudinale du
   vehicule qu'apres qualification de l'orientation et de la fixation du telephone.
4. Pour le score 30 jours, ignorer les trajets non eligibles et publier le nombre et
   la part de trajets couverts ; ne pas rendre tout l'agregat indisponible parce qu'un
   seul trajet manque une composante.
5. Pour les couts, afficher un sous-total prouve et son taux de couverture plutot
   qu'un faux total ou un ecran vide. Ne jamais imputer un prix absent a un trajet
   historique.
6. Construire un corpus terrain versionne avec distance de reference, pleins reels,
   conditions meteo, profil vehicule et annotations. Publier biais median, erreur
   absolue mediane et P90 par version d'algorithme et segment de vehicule.

Porte de sortie : aucune unite ou nature ambigue, aucun proxy nomme comme une mesure,
agregats accompagnes de leur denominateur, et regression detectee avant diffusion.

## Ordre d'execution recommande

1. Deverrouillage puis validation terrain P0-A sur le build 33.
2. Valider sur appareil la sante persistante P0-C livree dans le build 33,
   sans activer d'alerte.
3. Demande d'entitlement et prototype SafetyKit P0-B ; collecte shadow uniquement
   comme instrumentation secondaire.
4. Socle Core Data versionne P1-D avant d'ajouter de nouvelles entites persistantes.
5. Schema vehicule versionne, puis imports officiels et photos P1-C.
6. Integrite transversale des indicateurs P1-E.
7. Modele de consommation/calibration par pleins P1-A.
8. Etendre les connecteurs de prix locaux securises P1-B au-dela de l'Ontario.
9. Release TestFlight limitee, tableau de sante de collecte, puis ouverture
   progressive seulement si toutes les portes sont franchies.

## Lots precis, dependances et portes de sortie

| Lot | Delivrable | Depend de | Verification exigee | Bloque la diffusion si |
|---|---|---|---|---|
| P0.1 | Permission et collecte build 33 | action utilisateur `Toujours` | 3 trajets verrouilles + hors ligne + terminaison systeme | un trajet ordinaire manque ou ecart distance > 5 % |
| P0.2 | Sante de collecte 7 j | P0.1 pour preuve terrain | journal present, pas de PII, panne mouvement/GPS visible en < 10 min a la reouverture | un etat vert existe sans sample recent |
| P0.3 | Persistance versionnee | fixtures des stores historiques | migration interrompue/reprise, sauvegarde intacte, aucune suppression | un store historique ne s'ouvre pas |
| P0.4 | SafetyKit + livraison | entitlement Apple + fournisseur configure | simulateur SafetyKit, idempotence, offline/retry, accuse fournisseur | collision ou reception affichee sans preuve bout en bout |
| P1.1 | Contrat commun des indicateurs | P0.1 + P0.3 | nature, couverture, provenance, intervalle et version sur chaque metrique | proxy presente comme mesure |
| P1.2 | Profil vehicule et consommation | P1.1 | variante exacte, NRCan/FuelEconomy.gov, calibration par pleins, mediane/P90 | valeur unique sur profil ambigu |
| P1.3 | Prix local securise | P1.2 | source officielle par juridiction, cache/fraicheur/schema/redirect tests | prix par defaut presente comme local |
| P1.4 | Photos reelles | identifiants vehicule stables | auteur, URL, licence, hash, modele/generation verifies pour chaque asset | photo voisine ou licence absente |

## Etat d'execution verifie

- Build 33 signe, installe et confirme `0.1.0 (33)` sur l'iPhone 16. La commande de
  lancement n'a produit aucun nouveau `app.launch build=33` dans le diagnostic :
  le demarrage reel et le rendu UI restent donc non prouves tant que l'iPhone n'est
  pas deverrouille.
  Avant installation, le SQLite appareil a ete sauvegarde et controle `ok`. Apres
  l'installation du build 33, sa copie est identique octet pour octet au SHA-256
  `9b26ce5bcf54778ba64268f460ecf0dedbde3d69dbd3308a5f76b48675fc01fc`
  et contient toujours 126 trajets.
- 314/314 tests iOS reussis ; 0 echec et 0 test ignore. Cela inclut une migration
  SQLite reelle d'un store sans les nouveaux champs de preuve carburant.
- Le build 33 ajoute un journal local de sante de collecte sur 7 jours, atomique,
  protege et borne, avec au plus deux ancres historiques non sensibles, sans
  coordonnees ni identifiant de trajet. L'etat vert exige
  des echantillons GPS acceptes recents ; mouvement fort sans GPS, timestamps futurs,
  redemarrage et corruption du journal restent fail-closed. Son ecriture sur l'iPhone
  n'est pas encore prouvee, car aucun lancement build 33 n'a ete observe.
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
- Apres installation du build 33, les copies non destructives du store appareil
  avant/apres sont identiques au SHA-256, passent `PRAGMA integrity_check=ok` et
  contiennent toujours 126 trajets. Le demarrage et les ecrans Assistance/prix sur
  appareil restent a verifier apres deverrouillage.
- Collision builds 30-31 : perte de vitesse qualifiee par l'incertitude GPS, profil
  charge au lancement headless, arret fail-closed quand Core Location ne collecte
  plus, journal atomique/protege/borne avec quarantaine et retry en memoire. Les
  observations portent l'UUID exact du trajet et le type de vehicule ; leurs
  etiquettes sont conservees separement. Le journal de couverture build 31 mesure
  les frames Core Motion, la couverture GPS qualifiee, les interruptions, erreurs,
  candidats et sessions non cloturees, sans coordonnees. L'interface ne presente plus un contact
  configure comme une detection active et maintient le statut « Aucune alerte ».
  La suite iOS passe 314/314 ; aucune alerte automatique n'est activee.

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

1. **Utilisateur — aujourd'hui :** deverrouiller l'iPhone, ouvrir le build 33 et
   accorder Position `Toujours` + precise. Sans cela, aucun correctif logiciel ne
   peut prouver la capture ecran verrouille.
2. **Validation terrain — 1 jour :** executer les cinq scenarios P0-A, extraire le
   journal et mesurer completude, trous GPS et ecart de distance. Tout ecart > 5 %
   bloque la suite de diffusion.
3. **Collision shadow — prochaine tranche logicielle puis 2 a 4 semaines de conduite :**
   joindre le journal de couverture deja livre aux trajets finalises. Collecter ensuite
   les etiquettes volontaires et publier la duree surveillee/duree conduite, le taux de candidats par 1 000 km, le taux de
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

## Execution build 42 — photos reelles et exactitude visuelle

- Quatre photographies Wikimedia Commons inspectees et embarquees : Toyota
  Fortuner AN160, Nissan X-Trail T33, Hyundai Tucson NX4 et Kia Sportage NQ5.
- Auteur, licence, URL source HTTPS et SHA-1 de revision sont obligatoires dans le
  manifeste. Les fichiers sont des JPEG de 1200 px maximum, sans generation IA.
- Chaque image recente exige une annee de profil compatible avec la generation
  representee. Une annee absente ou hors plage retourne l'illustration neutre.
- Le test cible `VehiclePhotoCatalogTests` passe 9/9 et la suite complete 342/342,
  sans echec ni test ignore. Le build 42 est signe puis installe et confirme sur
  l'iPhone 16. La base avant/apres installation reste identique octet pour octet,
  SHA-256 `9b26ce5bcf54778ba64268f460ecf0dedbde3d69dbd3308a5f76b48675fc01fc`,
  126 trajets et `PRAGMA integrity_check=ok`.
- Le lancement automatise a expire apres 8 secondes. La base ne contient toujours
  pas l'entite `FuelFillUp` : l'app n'a donc pas encore execute la migration Build41
  sur l'appareil. Il faut deverrouiller et ouvrir Viim avant de controler cette porte.
