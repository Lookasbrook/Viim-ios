# Fiabilite des donnees affichees

Objectif: aucune valeur metier ne doit etre affichee sans source de verite, formule, condition de validite, et raison explicite quand la valeur manque.

## Notes de fiabilite au 2026-07-17 (build 0.1.0 (10) installe)

Bareme: /10. « Terrain » = preuve sur roulage reel avec la build qui contient le correctif.

| Donnee affichee | Note | Justification |
|---|---|---|
| Completude des trajets (aucun trajet oublie) | 6/10 provisoire | Toutes les causes racines prouvees (promotion a froid, GPS coupe en WhenInUse, moto mal classee, suspension iOS, fenetre candidat, arret des changements significatifs) sont corrigees et testees (123/123). Le build 10 est installe le 2026-07-17 ; la note passera a 8-9 apres la porte terrain 3/3 trajets (blueprint 2026-07-14 §14). Avant cette installation, l'iPhone roulait sur le build 6 defectueux : note reelle 3/10. |
| Distance trajet | 8/10 | `trip-metrics-v2` : filtre par incertitude combinee + vitesse fiable, ancre cumulative, glitch isole saute. Valide sur 2 fixtures reelles (faux trajet 0,1077 km rejete). Reste l'ecart <= 5 % contre odometre a prouver sur build 10. |
| Duree trajet | 8/10 | `trip-quality-v2` separe duree active et queue stationnaire (queues 682-11886 s reparees). Recalcul historique automatique. |
| Vitesse moyenne | 8/10 | Derivee de distance/duree fiables uniquement ; indisponible sinon. |
| Vitesse max | 7/10 | Filtree par `speedAccuracy`, zeros legacy repares, vitesse impossible par type de vehicule -> a verifier. Les polylines legacy sans `speedAccuracy` restent non scorables (choix assume). |
| Carte / trace | 8/10 | Polyline seulement si >= 2 points GPS valides, sinon etat explicite. |
| Score conduite | 5/10 | `score-speed-v1` : sous-score vitesse uniquement, affiche comme partiel. Honnete mais incomplet tant que fluidite/vigilance/eco n'existent pas. |
| Score 30 jours | 5/10 | Moyenne de scores partiels ; reste partiel par construction. |
| Cout carburant | 5/10 | Distance GPS validee x conso catalogue v4 (marque/modele generique, sans annee/motorisation) x prix du litre du profil (defaut XOF/CAD ou saisi). Marge estimee +/-20-30 %. Marque « Estime ». Montera a ~8 avec fiches techniques verifiees et prix regionaux backend (blueprint 2026-07-14 P1-P4). |
| Statuts Accueil (reseau, detection, collision) | 9/10 | Sources reelles : `NWPathMonitor`, etat effectif de la detection, collision affichee « Pas encore actif » tant que le detecteur n'existe pas. |
| Position Assistance | 8/10 | Position fraiche demandee a l'ouverture, erreurs explicites. |
| Test WhatsApp | 4/10 | Backend exige `providerMessageId` et persiste les statuts (13/13 tests), mais aucun vrai message WhatsApp de production prouve (WA-103 ouvert). |
| Synchronisation | N/A honnete | Aucun moteur de sync : aucun statut affiche, conforme a la regle. |

## Etats UI obligatoires

| Etat | Usage | Regle UI |
|---|---|---|
| fiable | Source validee, formule complete, seuils respectes | Afficher la valeur normalement |
| partielle | Source presente, mais calcul incomplet | Afficher la valeur avec libelle explicite |
| a renseigner | Donnee utilisateur manquante | Ne pas afficher de chiffre invente |
| indisponible | Source absente ou insuffisante | Afficher la raison, pas une valeur par defaut |
| a verifier | Incoherence detectee | Masquer la valeur et signaler le probleme |

## Matrice source de verite

| Donnee | Source de verite | Formule | Conditions de fiabilite | Si absent/invalide | Tests obligatoires |
|---|---|---|---|---|---|
| Distance trajet | Points GPS filtres par `LocationService` puis `TripMetricsCalculator` | Somme des segments valides | Duree >= 60 s, distance >= 80 m, au moins 2 points GPS valides | Trajet trop court ou GPS insuffisant | Unit distance, fallback trajet court, legacy CoreData |
| Duree trajet | `endedAt - startedAt` | Difference dates, jamais depuis UI | Dates presentes, duree positive, seuil minimum respecte | Trajet incomplet ou trop court | Unit duree negative/zero/courte |
| Vitesse moyenne | Distance fiable / duree fiable | `distanceKm / durationHours` | Distance et duree fiables | Indisponible si distance/duree invalides | Unit moyenne, division zero |
| Vitesse max | Samples GPS valides | Maximum des vitesses GPS filtrees | Precision <= 50 m, vitesse finie, seuil impossible par type vehicule non depasse | GPS trop imprecis ou valeur a verifier | Unit GPS imprecis, vitesse impossible |
| Route/carte | Polyline issue des points GPS valides | Trace des points valides | Au moins 2 points GPS valides | Carte indisponible, GPS insuffisant | Unit moins de 2 points, UI etat vide |
| Score trajet | `ScoreEngine` versionne | Sous-scores connus selon version | Fiable seulement quand les sous-scores attendus sont disponibles | Partiel si vitesse seule, indisponible si aucun sous-score | Unit score partiel, aucun score, anti constante |
| Score 30 jours | Synthese des scores trajets fiables/partiels | Moyenne des scores existants | Partiel tant que les scores sources sont partiels | Score indisponible | Unit moyenne, aucun score |
| Cout FCFA | `VehicleFuelCatalog` v2 si vehicule reconnu par saisie canonisee/autocomplete, puis donnees utilisateur/plein manuel plus tard | Distance * conso catalogue ajustee par style de conduite * prix carburant catalogue | Estimation partielle si vehicule reconnu ; fiable seulement avec calibration utilisateur/plein manuel | A renseigner uniquement si vehicule non reconnu | Unit Toyota Corolla estimee, motos Burkina, voitures Afrique de l'Ouest, inconnu nil, typo canonisee |
| Sync | Futur `SyncManager` reel | Etat file locale + reponse backend | Afficher sync seulement si moteur existe | Sync indisponible | Unit presenter, pas de faux statut |
| Assistance position | `LocationService.latestLocation` ou demande fraiche | Coordonnees GPS | Autorisation iOS + position recente | Position indisponible | Unit erreur permission/reseau |
| WhatsApp test | `BackendAPIClient` + contact Keychain valide | POST `/v1/alerts/test` | Contact normalise + reseau + serveur OK | A configurer ou erreur actionnable | Unit contact invalide/offline/503 |

## Regles non negociables

- Pas de montant FCFA invente : un vehicule reconnu peut produire une estimation automatique marquee partielle/estimee.
- A l'inscription, privilegier les suggestions du catalogue pour stocker `marque` et `modele` sous forme canonique.
- Pas de statut de synchronisation sans vrai moteur de sync.
- Pas de carte trajet si moins de 2 points GPS valides.
- Pas de vitesse max si la precision GPS est trop mauvaise.
- Pas de score global fiable si seuls des sous-scores partiels existent.
- Toute absence de donnee doit expliquer la cause: a renseigner, trajet trop court, GPS insuffisant, GPS trop imprecis, a verifier.

## Politique legacy CoreData

Les anciens trajets sans preuve suffisante ne deviennent jamais fiables par defaut.

| Cas legacy | Etat |
|---|---|
| Polyline absente ou moins de 2 points valides | Carte indisponible |
| `fuelFCFA` absent avec vehicule reconnu recalculable | Estime |
| `fuelFCFA` absent avec vehicule inconnu | A renseigner |
| Score absent | Indisponible |
| Score vitesse seul | Partiel |
| Vitesse max impossible | A verifier |
