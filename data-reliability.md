# Fiabilite des donnees affichees

Objectif : aucune valeur metier ne doit etre affichee sans source de verite, formule, condition de validite et raison explicite quand la valeur manque.

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
| Cout | Instantane CoreData du trajet | litres x prix utilisateur, arrondi en unite mineure | Profil vehicule exact + prix utilisateur + trajet affichable | `A renseigner`, `Vehicule a confirmer` ou `A verifier` |
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
