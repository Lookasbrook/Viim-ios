# Plan de correction et validation — build 52

Objectif : afficher uniquement des informations étayées, conserver les trajets
et améliorer la reprise GPS sans imposer une pastille de localisation.

## Corrections exécutées

| Domaine | Correction | Validation |
| --- | --- | --- |
| Carburant | Alias exact Corolla LE ; référence indicative conservée ; variantes inconnues refusées | Tests du catalogue, coût estimé, mauvais constructeur, hybride non qualifié, prix et provenance |
| Scores | Au moins 80 % de durée GPS exploitable ; aucune note fondée sur quelques points ; la réception ne gonfle plus la couverture ; dynamique bornée au trajet | Traces continues, seuil 80 %, trous de cinq minutes, rafales comprimées, NaN/infini/vitesses négatives |
| Historique | Scores avec couverture connue insuffisante masqués et exclus des moyennes, données originales conservées | Test Core Data vérifiant affichage, agrégats et valeur brute inchangée |
| Vitesse actuelle | Fraîcheur fondée sur l'heure de mesure, pas celle de réception ; expiration après 15 secondes ; dernier point actuel conservé lors de livraisons désordonnées | Tests de données retardées, ordre inversé, expiration et absence de fausse preuve de collecte fraîche |
| Reprise GPS | Réaffirmer les mises à jour natives au retour au premier plan et après pause système, sans finaliser le trajet ; ne pas réactiver un suivi arrêté | Tests avec gestionnaire Core Location simulé |
| Autorisations | Arrêt natif et nettoyage des états de suivi lorsque la permission est retirée | Test de révocation et tests existants Always/When In Use/reprise passive |
| Diagnostic terrain | Événements de cycle de vie, interruptions de livraison, pauses/reprises et diagnostics natifs CLServiceSession ; aucun enregistrement de coordonnées dans ces événements | Compilation et lecture des logs du build installé |
| Interface | Retrait des liens constat/dépanneur/hôpitaux menant à des pages non fonctionnelles ; outils de recherche réservés à DEBUG ; explication honnête du score absent et de la collision indisponible | Compilation Release et inspection du code de présentation |
| Assistance | Maintien de la distinction contact configuré / livraison prouvée ; aucune activation prématurée de collision | Tests de transport simulé, contacts invalides, serveur indisponible, hors ligne, état public de collision |

## Validation de livraison

1. Sauvegarder Application Support avant toute installation.
2. Exécuter tous les tests iOS sur simulateur, dont persistance, migrations,
   récupération de brouillons, calculs carburant, scores et assistance.
3. Compiler et signer la version Release 52 pour l'iPhone connecté.
4. Mettre à jour l'app sans désinstallation, puis vérifier son lancement, ses
   permissions, ses diagnostics et la conservation des trajets.
5. Consigner les résultats et limites ci-dessous.

## Validation terrain nécessaire

Un test unitaire ne reproduit pas l'ordonnancement GPS d'iOS sur route.
Les reprises corrigées ne constituent pas une preuve que les interruptions
de cinq minutes sont éliminées. La cause système exacte reste ouverte.

- À l'arrêt, ouvrir Viim et vérifier « Toujours » et la localisation précise.
- Effectuer un trajet motorisé de 15 à 20 minutes, écran verrouillé et sans
  manipuler le téléphone en conduisant ; terminer par un arrêt d'au moins
  cinq minutes pour vérifier la finalisation automatique.
- Relever la couverture, les interruptions maximales, les diagnostics
  `location.serviceDiagnostic`, `location.deliveryGap`, `app.scene` et les
  événements de pause. Comparer la distance à une référence indépendante.
- Attendu : pas de trous répétés d'environ 300 secondes pendant le mouvement,
  ni faux score lorsque la couverture est insuffisante ; coût explicitement
  estimé uniquement si référence et prix sont exploitables.
- Répéter ultérieurement avec économie d'énergie et perte temporaire de réseau.
  La livraison WhatsApp doit faire l'objet d'un essai explicitement convenu
  avec le contact ; aucun envoi réel n'est inclus dans cette exécution.

Ne pas activer la collision automatique avant une validation spécifique de
détection, faux positifs, consentement et livraison de bout en bout. Aucun
recalcul rétroactif du carburant n'utilise le véhicule ou le prix actuels.

## Résultats

- Bilan officiel Xcode : **422 tests réussis, 0 échec, 0 ignoré**, simulateur
  iPhone 17 / iOS 26.5. Résultat :
  `/tmp/viim-fix.HCOCLu/permission-final.xcresult`.
- Compilation Release signée réussie ; `codesign --verify --strict` réussi
  avec accès au trousseau ; ressources plist/strings et diff valides.
- Build 52 installé sur l'iPhone, y compris la dernière correction du premier
  démarrage (une notification initiale « non déterminé » ne doit pas annuler
  une demande de suivi en attente).
- Sauvegarde avant installation : `/tmp/viim-fix.HCOCLu/before-install`.
  Contrôle après la première installation : 135 trajets avant et après,
  aucun identifiant de trajet manquant ; intégrité SQLite `quick_check=ok`.
- Contrôle de lancement **non terminé** : deux tentatives échouent avec
  CoreDevice 4000 (déconnexion) ; état de verrouillage lu :
  `passcodeRequired=true`. Une lecture ultérieure échoue avec une erreur de
  ressource CoreDevice. L'installation, elle, est confirmée par l'outil Apple.
- Déverrouiller l'iPhone et ouvrir Viim pour vérifier les logs du build 52.
  Aucune observation visuelle sur l'iPhone ni validation routière du nouveau
  build n'est revendiquée. La suppression des interruptions de cinq minutes
  n'est donc pas encore démontrée.
