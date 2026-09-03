# Investigation iOS — fiabilite des trajets, carburant et catalogue

Date locale : 2026-09-02
Statut : `DONE_WITH_CONCERNS`

## Causes et niveau de preuve

1. **Confirme :** sous `authorizedWhenInUse`, Core Location ne relance pas Viim
   apres terminaison pour un changement significatif. Viim choisit en plus de ne
   pas maintenir de suivi continu avec indicateur bleu dans cet etat. La collecte
   premier plan reste possible : `When In Use` ne signifie donc pas « aucun GPS ».
2. **Defaut confirme, contribution causale tres probable :** un override Debug
   persiste pouvait activer `gpsSessionSplit` entre plusieurs installations et
   supprimer le lien de relance en arriere-plan. Le plist et le chemin de code le
   prouvent ; aucun essai A/B de l'ancien build n'a toutefois ete realise sur route.
3. La recuperation d'un brouillon tres ancien le persistait comme un trajet normal,
   et une erreur de lecture des echantillons pouvait supprimer la seule preuve brute.
4. Le catalogue carburant utilisait une resolution par sous-chaine : plusieurs
   variantes moto et certains modeles courts pouvaient recevoir la consommation
   d'un autre vehicule.
5. Une consommation generique par modele recopiait le carburant choisi par
   l'utilisateur, donnant a tort l'impression que l'annee et la motorisation
   avaient ete resolues.
6. Une requete asynchrone de prix pouvait ecraser une configuration plus recente ;
   l'affichage a deux decimales pouvait aussi modifier une valeur officielle a trois
   decimales et supprimer sa provenance au prochain enregistrement.
7. Le catalogue photo utilisait lui aussi des sous-chaines et pouvait afficher une
   vraie photo, mais du mauvais modele.
8. Une erreur `kCLErrorDenied` ecrasait l'etat interne avec `.denied` sans relire
   la permission systeme. Sous `authorizedWhenInUse`, un refus de livraison GPS en
   arriere-plan etait donc journalise a tort comme un retrait d'autorisation.

## Corrections implementees

- Etat de disponibilite background derive de toutes les conditions reelles et
  journalise au lancement/reveil ; l'UI signale explicitement le mode premier plan.
- L'escalade de `When In Use` vers `Always` reste une action utilisateur explicite
  dans la carte de suivi. Le build 25 ne pretend pas reafficher automatiquement une
  invite que Core Location limite a une demande utile ; le lien Reglages reste le
  recours apres un refus.
- Flags experimentaux Debug limites au processus et anciens overrides supprimes.
- Sessions de fiabilite conservees sous autorisation `Always`, independamment du
  flag experimental.
- Brouillons de plus de 12 h mis en quarantaine/rejetes avec conservation des
  echantillons ; erreurs de lecture rendues reessayables.
- Collision automatique presentee comme indisponible ; seule l'assistance manuelle
  est annoncee tant que la chaine capteur-confirmation-alerte n'existe pas.
- Moteur de calibration collision `collision-shadow-v1` raccorde uniquement aux
  trajets motorises actifs : acceleration sans gravite a 50 Hz, rotation, vitesse
  GPS recente et precise, puis confirmation par perte de vitesse dans une fenetre
  de 5 s. Aucun envoi reseau et aucune alerte automatique.
- Evenements shadow bornes a 100 resumes locaux sans latitude ni longitude ; les
  trous de livraison capteur reinitialisent le candidat pour eviter une confirmation
  a travers une suspension iOS.
- Catalogue carburant et catalogue photo resolus uniquement sur une correspondance
  exacte connue ; les fautes restent des suggestions et ne deviennent pas des
  donnees silencieusement.
- Reference de consommation marquee `partial`, sans pretendre connaitre le type de
  carburant, l'annee ou la motorisation.
- Effet de conduite GPS applique seulement si la duree du trajet est connue, si la
  distance concorde et si la couverture dynamique atteint 80 % ; sinon multiplicateur
  neutre `x1`.
- Prix officiel exigeant une preuve complete (identifiant, URL HTTPS, localite,
  horodatage), affichage a trois decimales et conservation de provenance si la valeur
  n'a pas change.
- Requetes de prix annulees/invalidees par identifiant et snapshot de configuration ;
  mise a jour logique du carburant et de son prix en une operation.
- Identite de configuration du recorder etendue au vehicule et a toutes les preuves
  de prix pour eviter de conserver un ancien snapshot.
- Les erreurs GPS `denied` relisent desormais `authorizationStatus`, arretent la
  tentative courante et conservent l'etat reel `foregroundOnly` lorsque la
  permission systeme reste `When In Use`.
- Profil vehicule etendu par une fiche officielle optionnelle, versionnee et
  auditable (annee, variante, moteur, transmission, carburant, consommations ville,
  route et combinee, identifiant de ligne, URL et date de collecte).
- Client FuelEconomy.gov limite a un domaine HTTPS et aux routes vehicule attendues,
  avec timeout, taille maximale, type MIME, statut HTTP, schema et identite exacte.
  La recherche ne transmet aucune coordonnee ni trace de trajet.
- Selection explicite de la variante dans Profil ; une fiche incoherente ou une
  reponse terminee apres un changement de profil est rejetee. La fiche exacte prime
  sur la moyenne indicative, qui reste clairement etiquetee.
- Les 18 photos embarquees portent maintenant un manifeste controle via l'API
  Wikimedia : auteur, source, licence, lien de licence, empreinte de revision,
  modification et methode photographique. Les credits sont visibles dans l'app et
  les alias de trims voisins ont ete retires.
- Le modele carburant `v10` conserve desormais une plage basse/centrale/haute,
  la resolution catalogue, les couvertures conduite/altitude, les multiplicateurs
  appliques et la meme plage convertie en cout. Le denivele est enfin branche au
  calcul, sans reduction supposee en descente ni fausse mesure de charge/meteo.

## Verification

- Tests de regression d'abord observes en echec sur les correspondances vehicule,
  l'absence de duree et les variantes moto, puis corriges.
- Suite finale : 236 tests passes, 0 echec, 0 ignore, iOS Simulator 26.5.
- Migration de schema verifiee avec un vrai store SQLite ancien contenant un trajet :
  la ligne est preservee et les nouveaux champs optionnels restent `nil`.
- `git diff --check` sans erreur.
- Build 27 signe pour `com.yamstack.viim`, installe sur iPhone 16 / iOS 26.6.1 et
  confirme par les metadonnees appareil comme `0.1.0 (27)`. Son lancement est refuse
  uniquement parce que l'appareil est verrouille.
- Sauvegarde pre-installation verifiee (`PRAGMA integrity_check = ok`). Tant que le
  build 27 n'a pas ete lance, SQLite, WAL et SHM restent identiques octet pour octet
  a cette sauvegarde. La migration reelle de l'appareil n'est donc pas encore prouvee.
- Diagnostic appareil : build 23 lance, flags experimentaux desactives, GPS precis,
  actualisation background disponible, mais autorisation encore
  `authorizedWhenInUse`; la collecte verrouillee n'est donc pas encore validee.

Le passage historique de `authorizedAlways` a `authorizedWhenInUse` n'est pas
attribue avec certitude a une reinstallation ou a une signature : c'est une
hypothese, pas une cause racine prouvee.

## Sources publiques retenues pour la suite du catalogue

- Ressources naturelles Canada / Gouvernement ouvert : jeu officiel de consommation
  1995-2026, avec annee, marque, modele, moteur, cylindres, transmission, carburant,
  ville, route et combine.
- FuelEconomy.gov : API publique officielle complementaire pour les vehicules US.
- NHTSA vPIC : decodage VIN et caracteristiques constructeur, sans en deduire une
  consommation absente de la source.

La premiere integration FuelEconomy.gov respecte desormais ces exigences pour une
variante choisie explicitement. En cas d'ambiguite, la valeur reste indicative tant
que l'utilisateur n'a pas choisi sa variante. NRCan, les plages multi-variantes et
la couverture des motos restent a ajouter sans jamais inventer une valeur exacte.

## References primaires pour la calibration collision

- Apple Core Motion / `CMMotionManager` : une seule instance par app, lecture de
  `userAcceleration`, `rotationRate` et controle des horodatages reels.
  https://developer.apple.com/documentation/coremotion/cmmotionmanager
- NHTSA, *Recording Automotive Crash Event Data* : les detecteurs embarques
  utilisent un seuil d'acceleration puis une variation de vitesse pour qualifier
  un evenement. Ces valeurs proviennent de capteurs fixes au vehicule et ne sont
  donc pas transposees directement a un telephone mobile.
  https://www.nhtsa.gov/sites/nhtsa.gov/files/recording_automotive_crash_event_data.pdf

## References primaires pour la collecte iOS

- Apple, autorisations Core Location : `When In Use` peut poursuivre une session
  deja active en arriere-plan, mais ne relance pas l'app terminee ; `Always` permet
  certains reveils passifs. L'escalade vers `Always` est limitee par le systeme.
  https://developer.apple.com/documentation/CoreLocation/requesting-authorization-to-use-location-services
- Apple, collecte en arriere-plan : recreer immediatement les sessions de service
  au lancement et utiliser une `CLBackgroundActivitySession` pour une activite
  visible sous `When In Use`.
  https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background
- Apple, changements significatifs : le reveil est grossier (environ 500 m, pas
  plus d'une notification toutes les cinq minutes) et ne remplace pas une trace GPS
  continue.
  https://developer.apple.com/documentation/corelocation/cllocationmanager/startmonitoringsignificantlocationchanges()

## Risques et portes restantes

- P0 terrain : l'utilisateur doit accorder `Toujours` puis effectuer trois trajets
  verrouilles pour prouver la collecte background.
- P0 produit : le moteur shadow multi-capteurs est implemente, mais aucune detection
  automatique utilisable n'est active. Ne pas afficher de promesse de protection
  avant calibration terrain, confirmation utilisateur, annulation et livraison
  d'alerte testees avec accuse de reception.
- P1 mesure carburant : le calcul reste une estimation sans OBD/plein reel ; une
  calibration par pleins est necessaire pour mesurer l'erreur par vehicule.
- P1 catalogue : FuelEconomy.gov et le schema moteur/variante sont implementes pour
  les voitures ; les valeurs historiques restent generiques. NRCan, les plages en
  cas d'ambiguite et une source moto licite restent a construire.
- P1 persistance : Core Data reste programme sans modele versionne ni plan de
  migration pour suppressions/renommages futurs.
- P1 livraison urgence : le canal backend doit etre teste en production avec accusé
  de reception avant toute revendication de protection automatique.
- P2 photos : 18 photos reelles sourcees, manifestees et creditees sont embarquees ;
  la couverture doit etre elargie uniquement avec licence, attribution, modele et
  generation verificables. Les correspondances ambiguës restent volontairement
  neutres.
