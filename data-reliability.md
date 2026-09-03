# Fiabilite des donnees affichees

Objectif : aucune valeur metier ne doit etre affichee sans source de verite, formule, condition de validite et raison explicite quand la valeur manque.

## Etat au 2026-09-03 — concordance prix/trajet iOS, build 49

- Un prix officiel ne cree plus de cout pendant la transaction qui sauvegarde le
  trajet. La persistance locale aboutit d'abord ; un enrichissement asynchrone
  traite ensuite les extremites qualifiees sans pouvoir supprimer le trajet.
- Le depart et l'arrivee doivent avoir une precision horizontale de 100 m ou mieux,
  etre resolus par Apple et appartenir tous deux au marche canonique de la preuve.
  Echec reseau, geocodage absent, ville differente, sortie de province/pays ou
  carburant discordant laissent le cout indisponible.
- La preuve fige pays, subdivision, localite demandee, marche publie, localites
  grossieres des deux extremites, date et version. Les diagnostics ne conservent
  ni coordonnee ni ville.
- Un cout officiel historique sans cette preuve reste stocke pour audit mais est
  masque et exclu des agregats. Il n'est jamais recalcule avec le profil courant.
- Les migrations Build 33→49 et Build 41→49 passent sur de vrais stores SQLite de
  test. Le build 49 est installe sur l'iPhone 16, mais son lancement est bloque par
  le verrouillage ; la migration du store appareil reste donc a prouver.

## Etat au 2026-09-03 — collision shadow iOS, build 29

- La detection automatique reste explicitement indisponible et aucune alerte
  collision n'est envoyee. Le moteur Core Motion n'est qu'un collecteur local de
  candidats pendant une collecte GPS active ; il ne constitue pas une garantie
  de protection quand l'app est suspendue ou terminee.
- `collision-shadow-v2-impact-gps-uncertainty` exige que la perte de vitesse reste
  au-dessus du seuil apres prise en compte des incertitudes GPS avant et apres
  l'impact. Les deux precisions sont conservees avec la preuve.
- Le moniteur echoue ferme si le profil vehicule n'est pas charge, si le vehicule
  est un velo, si Core Motion manque ou si Core Location ne collecte plus. Le type
  de vehicule est configure au lancement headless sans attendre une vue SwiftUI.
- Le journal local est borne a 512 Ko et 100 candidats, valide les nombres/dates,
  refuse les UUID conflictuels, rend un retry identique idempotent et lit au plus
  `limite + 1` octets. Un fichier corrompu est deplace sans perte en quarantaine,
  puis la collecte reprend dans un journal neuf.
- Les ecritures sont atomiques et accessibles apres le premier deverrouillage.
  Une erreur transitoire conserve jusqu'a 10 candidats en memoire et retente
  toutes les 5 secondes ; une terminaison avant retry peut encore les perdre.
- La suite iOS passe 251/251. Ces tests prouvent le contrat logiciel, pas la
  couverture capteur sur route ni la capacite a detecter une vraie collision.
- Le build 29 signe est installe sur l'iPhone 16. La base extraite avant/apres
  installation est identique (SHA-256), passe `PRAGMA integrity_check=ok` et
  contient toujours 126 trajets. Le lancement reste bloque par le verrouillage
  de l'iPhone, pas par le build.
- Chemin de production retenu : SafetyKit, apres approbation de l'entitlement
  Apple restreint, avec inbox idempotent, confirmation utilisateur et livraison
  externe prouvee. SafetyKit ne doit pas etre presente comme couvrant toutes les
  collisions, les motos ou les velos.

## Etat au 2026-09-03 — prix Ontario iOS, build 28 installe

- L'endpoint prix du backend de production repond `404 not_found` malgre sa
  presence dans le depot. Il n'est plus le chemin critique pour l'Ontario.
- L'iPhone telecharge directement le CSV hebdomadaire officiel Ontario par HTTPS.
  Le marche est selectionne localement : aucune coordonnee ni ville n'est envoyee
  a Viim. Sans ville exploitable, l'app utilise explicitement la moyenne Ontario.
- L'app refuse un hote ou chemin redirige non liste, un autre MIME, plus de 2 Mo,
  une source vieille de plus de 14 jours, une date future, une devise autre que
  CAD, un carburant discordant ou un prix hors plage plausible.
- Le prix conserve sa source, son URL, sa date, sa devise, son carburant et sa
  localite. En cas de panne, seul le dernier prix officiel encore valide peut
  continuer a alimenter les nouveaux instantanes de cout.
- Les tests couvrent CSV, moyenne provinciale, preuve malformee, reponse
  trop volumineuse, MIME, redirection hostile, fraicheur et protection contre
  l'ecrasement d'une saisie plus recente. La suite iOS passe 243/243. Le build 28
  signe est installe sur l'iPhone 16 ; le store extrait apres installation est
  integre et conserve 126 trajets. Le lancement et le parcours manuel du bouton
  de prix restent bloques tant que l'iPhone est verrouille.

## Etat au 2026-09-02 — build 18 privé, lot carburant partiel

Preuves disponibles pour le lot :

- suite iOS : 186/186 tests réussis sur simulateur ;
- backend : 75/75 tests réussis ;
- tests Android réussis ;
- build Debug 0.1.0 (18) signé et installé sur l'iPhone 16 de Guy ;
- prix public Ontario récupéré sans transmettre les coordonnées GPS au backend ;
- aucune validation de roulage T1–T6, aucune calibration par plein et aucun déploiement backend dans ce lot.

Le coût gagne en traçabilité : l'estimation de litres réagit à la vitesse, aux variations d'accélération, aux phases quasi immobiles et au dénivelé GPS filtré ; un prix officiel Ontario peut être daté et figé avec sa source. Il ne s'agit pas encore du modèle physique complet (masse, traînée, CoreMotion, météo, revêtement et calibration flotte restent absents), donc les litres restent une estimation et non une mesure.

## Etat au 2026-07-19 — durcissement build 17 non deploye

Preuves disponibles :

- suite iOS : 160/160 tests reussis sur iPhone 17 Simulator, iOS 26.5 ;
- backend : 15/15 tests reussis et verification syntaxique Node.js reussie ;
- build Release 0.1.0 (17) signe pour l'iPhone reel, installe et lance sur l'iPhone de Guy ;
- aucun deploiement backend/TestFlight, aucune modification de production, aucun roulage reel et aucun parcours manuel complet des champs clavier.

Bareme : /10. « Terrain » signifie une preuve obtenue pendant un roulage reel avec exactement la build qui contient le correctif. Les notes restent volontairement prudentes tant que cette porte n'est pas franchie.

| Donnee affichee | Note | Justification |
|---|---|---|
| Completude des trajets | 6/10 provisoire | Les causes logicielles connues sont couvertes par tests, mais la porte terrain de 3 trajets consecutifs ecran verrouille reste obligatoire. |
| Distance trajet | 8/10 | `trip-metrics-v2` filtre l'incertitude GPS, les vitesses non fiables et les segments impossibles. L'ecart <= 5 % contre une reference terrain reste a prouver. |
| Duree trajet | 8/10 | Duree active separee de la queue stationnaire. La couverture GPS inclut maintenant le debut et la fin reels du trajet. |
| Vitesse moyenne | 8/10 | Calculee seulement depuis une distance et une duree valides. |
| Vitesse max | 7/10 | Filtree par precision GPS et limites physiques du type de vehicule. Sans `speedAccuracy`, la valeur n'est pas promue comme fiable. |
| Carte / trace | 8/10 | Trace uniquement avec au moins deux points valides et jamais pour un trajet classe `a verifier` ou `rejete`. |
| Score conduite | 7/10 | `score-v3` combine vitesse, fluidite et eco. La vigilance reste indisponible. Le score vitesse utilise un seuil technique fixe et ne pretend plus connaitre la limitation routiere reelle. |
| Score 30 jours | 7/10 | Moyenne des trois composantes implementees sur les seuls trajets fiables ou partiels. Un critere agrege reste indisponible si un seul trajet inclus ne le possede pas. |
| Cout carburant | 7/10 pour les nouveaux trajets eligibles | Instantane immuable : distance validee x consommation exacte du catalogue x prix saisi par l'utilisateur. Le total reste indisponible si un trajet inclus n'a pas de profil/prix ou si les devises different. |
| Numeros d'urgence | 9/10 pour BF/CA | Catalogue explicite Burkina Faso (18/17) et Canada (911), avec source. Pour tout autre pays, l'app refuse de deviner et affiche « Numero non verifie ». |
| Conseils Prevention | 7/10 | Region acceptee seulement avec une position recente et suffisamment precise. Les contenus statiques sont presentes comme conseils, jamais comme meteo ou etat routier en temps reel. |
| Position Assistance | 8/10 | Position fraiche demandee, erreurs explicites et partage uniquement manuel. |
| Detection collision | Indisponible honnêtement | Shadow local sans alerte ; aucune couverture continue ni livraison protectrice prouvee. La cible SafetyKit depend encore d'un entitlement Apple. |
| Test WhatsApp | 4/10 | Le backend exige une preuve fournisseur et persiste le statut, mais aucun message reel de production n'a ete prouve. Un succes partiel n'est plus affiche comme un succes total. |
| Saisie clavier | 8/10 logiciel | Fermeture interactive au defilement, bouton clavier « Termine » et fermeture explicite apres sauvegarde. Il manque encore un test UI automatise de bout en bout. |
| Synchronisation | N/A honnete | Aucun moteur de synchronisation : aucun faux statut de sync n'est affiche. |

## Etats UI obligatoires

| Etat | Usage | Regle UI |
|---|---|---|
| fiable | Source validee, formule complete, seuils respectes | Afficher la valeur normalement |
| partielle | Source presente, calcul limite ou estimation | Afficher la valeur avec un libelle explicite |
| a renseigner | Donnee utilisateur manquante | Ne jamais injecter un chiffre par defaut |
| indisponible | Source absente ou insuffisante | Afficher la raison, pas une valeur inventee |
| a verifier | Incoherence detectee | Masquer distance, duree, carte, score et cout |

## Matrice source de verite

| Donnee | Source de verite | Formule / regle | Condition de validite | Si absent ou invalide |
|---|---|---|---|---|
| Distance | Points GPS filtres | Somme des segments valides | Trajet non rejete, au moins deux points et mouvement superieur a l'incertitude | `GPS insuffisant` ou `A verifier` |
| Duree | Bornes actives du trajet | `activeEnd - startedAt` | Dates ordonnees et duree minimale | `Trajet trop court` |
| Couverture GPS | Horodatage GPS et reception | Couverture depuis le debut actif jusqu'a la fin active | Trous sous les seuils du moteur qualite | `GPS insuffisant` |
| Vitesse max | Samples avec precision de vitesse | Maximum filtre | Precision connue et valeur physiquement plausible | `GPS trop imprecis` ou `A verifier` |
| Route | Polyline validee | Trace des points retenus | Trajet affichable et >= 2 points | Carte masquee avec cause |
| Score | `ScoreEngine` `score-v3` | Moyenne vitesse + fluidite + eco | Les trois composantes implementees existent | Partiel ou indisponible |
| Cout | Instantane CoreData du trajet | litres estimes x prix, arrondi en unite mineure | Profil/carburant concordants ; prix utilisateur date ou prix officiel dont depart et arrivee correspondent au marche | `A renseigner`, `Prix local non verifie`, `Vehicule a confirmer` ou `A verifier` |
| Urgence | `EmergencyNumberCatalog` | Numero par pays et service | Pays BF ou CA connu | Bouton desactive, numero non verifie |
| Region Prevention | Position iOS recente | Pays estime seulement si precision <= 10 km et age <= 15 min | Localisation autorisee et exploitable | Region inconnue |
| WhatsApp | API + `providerMessageId` | Un resultat par contact | Reponse fournisseur prouvee et statut persiste | Erreur detaillee ou succes partiel |

## Regles non negociables

- Aucun cout historique n'est recalcule avec le prix ou le vehicule courant.
- Aucun montant n'est affiche a partir d'un prix par defaut non verifie.
- Aucun total de consommation, de cout ou de critere de score n'est publie comme complet si un trajet inclus manque la preuve correspondante.
- Une saisie vehicule approximative propose des suggestions, mais ne selectionne jamais silencieusement un autre modele.
- Un trajet `needsReview` ou `rejected` ne fournit ni distance, ni duree, ni carte, ni score, ni cout a l'interface.
- Le score vitesse est un indicateur technique Viim, pas une preuve de respect de la limitation legale de la route.
- Aucun numero d'urgence n'est devine pour un pays non pris en charge.
- Aucun partage de position ou de fiche medicale n'est presente comme automatique.

## Politique legacy CoreData

Les anciens trajets sans preuve suffisante ne deviennent jamais fiables par defaut.

| Cas legacy | Etat |
|---|---|
| Qualite `needsReview` ou `rejected` | Valeurs et carte masquees |
| Polyline absente ou moins de 2 points valides | Carte indisponible |
| Cout sans instantane prix/devise/source | Cout indisponible, aucun recalcul |
| Score absent | Indisponible |
| Score incomplet | Partiel |
| Vitesse max impossible | A verifier |

## Portes restantes avant de qualifier les donnees de « grande fiabilite »

1. Trois trajets reels consecutifs, ecran verrouille : 3/3 visibles, aucun brouillon orphelin, aucun indicateur GPS hors trajet.
2. Comparaison distance Viim / odometre ou trace de reference avec ecart cible <= 5 %.
3. Migration d'une copie du store CoreData reel vers les nouveaux champs optionnels, avec verification avant/apres du nombre de trajets.
4. Parcours manuel de tous les champs clavier sur appareil et ajout d'une cible XCUITest pour prevenir la regression.
5. Remplacement du seuil vitesse fixe par des limitations routieres map-matchees et sourcees.
6. Catalogue vehicule par annee/motorisation ou calibration par pleins reels.
7. Validation WhatsApp en production avec consentement, reception effective et `providerMessageId`.
8. Entitlement SafetyKit approuve, tests de lancement termine/verrouille, doublons,
   position absente, annulation et livraison aux contacts de bout en bout.
