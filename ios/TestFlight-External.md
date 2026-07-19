# Préparation TestFlight externe — Viim 0.1.0 (14)

## Configuration cible

- App : Viim
- Bundle ID : `com.yamstack.viim`
- Groupe interne requis : `Équipe Viim`
- Groupe externe proposé : `Bêta externe Viim`
- Notification automatique des testeurs : désactivée pour la première revue
- Lien public : désactivé jusqu’à l’approbation du premier build

## Informations de test

### Description de l’app bêta

Viim est une application iOS de sécurité routière conçue pour les conducteurs de voitures et de motos. Elle détecte automatiquement les trajets, conserve un historique local, calcule des indicateurs de conduite et permet de partager sa position ou de tester une alerte WhatsApp avec un contact d’urgence consenti.

Cette bêta sert à valider la fiabilité de la détection des trajets en arrière-plan, la cohérence des distances et vitesses, l’affichage des scores, les estimations de carburant et le parcours Assistance.

### Courriel de retour

`kaboreguy269@gmail.com`

### URL marketing

`https://burktech-ia.com`

### URL de politique de confidentialité

Publier le fichier `PRIVACY.md` sur une URL HTTPS publique dédiée à Viim avant la soumission App Store. La politique générique actuellement disponible sur `https://burktech-ia.com/confidentialite` ne décrit pas les données de Viim.

## Informations « Quoi tester »

Merci de tester Viim sur un iPhone réel :

1. Terminer l’inscription et choisir le type de véhicule.
2. Autoriser le mouvement et la localisation précise, puis activer la localisation « Toujours » pour la détection en arrière-plan.
3. Effectuer au moins trois trajets réels, dont un avec l’écran verrouillé.
4. Vérifier que chaque trajet apparaît, que les heures sont correctes et que la distance reste cohérente avec l’odomètre ou une application de navigation.
5. Vérifier le score, la vitesse maximale et l’estimation de carburant.
6. Tester le mode hors ligne puis le retour du réseau.
7. Avec le consentement du destinataire, configurer un contact d’urgence et utiliser le bouton de test WhatsApp ainsi que le partage ponctuel de position.
8. Signaler tout trajet manquant, doublon, distance incohérente, écran bloqué ou fermeture inattendue.

## Informations pour la revue bêta Apple

- Connexion requise : non
- Compte de démonstration : non requis
- Notes de revue :

  Viim fonctionne sans compte distant. Au premier lancement, le réviseur doit terminer une courte inscription locale et choisir un véhicule. Les fonctions principales utilisent CoreMotion et Core Location. La détection automatique complète d’un trajet nécessite un iPhone réel en déplacement ; l’interface, l’inscription, l’historique, les réglages et le parcours Assistance restent accessibles sans conduire. Les coordonnées du contact d’urgence et la fiche médicale sont facultatives et stockées dans le trousseau iOS. Aucun achat intégré n’est présent.

### Coordonnées proposées

- Prénom : Guy
- Nom : Kabore
- Courriel : `kaboreguy269@gmail.com`
- Téléphone : **À RENSEIGNER dans App Store Connect**

## Conformité export

Le projet n’embarque pas d’implémentation cryptographique propriétaire ni de bibliothèque cryptographique tierce. Il utilise les mécanismes fournis par iOS, notamment HTTPS, URLSession et le trousseau. Le build 14 déclare `ITSAppUsesNonExemptEncryption = false`.

## Ordre des actions App Store Connect

1. Vérifier que le build `0.1.0 (14)` affiche `Ready to Submit`.
2. Sous TestFlight → Informations de test, saisir la description et le courriel ci-dessus.
3. Sous Informations pour la revue bêta, saisir les coordonnées et les notes ci-dessus.
4. Vérifier ou créer le groupe interne `Équipe Viim`.
5. Créer le groupe externe `Bêta externe Viim`.
6. Ajouter le build 14 au groupe externe et coller « Quoi tester ».
7. Laisser « Informer automatiquement les testeurs » désactivé.
8. Ne pas ajouter d’adresses de testeurs avant l’approbation si l’objectif est seulement de préparer la revue.
9. Cliquer sur `Submit Review` lorsque la fiche est complète.
