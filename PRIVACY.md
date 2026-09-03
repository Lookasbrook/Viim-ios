# Politique de confidentialité de Viim

Dernière mise à jour : 3 septembre 2026

Viim est une application iOS de suivi de conduite et de sécurité routière éditée par YAMSTACK TECHNOLOGIE. Cette politique explique quelles données sont utilisées, pourquoi elles le sont et quels choix restent sous le contrôle de l’utilisateur.

## Données utilisées sur l’appareil

Viim peut utiliser les données suivantes lorsque l’utilisateur active les fonctions correspondantes :

- le prénom, le numéro de téléphone, le type de véhicule et les réglages de carburant saisis pendant l’inscription ;
- la position précise, la vitesse et l’itinéraire nécessaires à la détection et à l’analyse des trajets ;
- l’activité de mouvement fournie par iOS afin de détecter automatiquement un déplacement ;
- les trajets, événements de conduite, scores et diagnostics techniques générés par l’application ;
- le nom et le numéro d’un contact d’urgence ;
- les informations médicales facultatives saisies dans la fiche d’urgence ;
- une photo de véhicule ou de constat lorsque l’utilisateur choisit d’utiliser l’appareil photo.

Les trajets et diagnostics sont conservés localement dans l’espace privé de l’application. Le contact d’urgence et la fiche médicale sont conservés dans le trousseau iOS et ne sont pas transmis en routine.

## Données transmises

Viim transmet uniquement les informations nécessaires lorsqu’un utilisateur déclenche une fonction connectée :

- pour rechercher volontairement un prix public de carburant : le service de géocodage Apple traite la position afin de déterminer le pays, la région et la ville. La source Ontario reçoit seulement une demande générique de fichier. Statistique Canada reçoit l’identifiant public d’une série qui indique un marché publié et le type de carburant, sans coordonnées GPS ni nom de ville en texte libre. Pour les autres pays pris en charge, l’API Viim peut recevoir le pays, la région, la ville et le carburant, jamais l’itinéraire ;
- pour rechercher volontairement une fiche de consommation officielle : l’année, la marque et le modèle du véhicule sont transmis à Ressources naturelles Canada ou FuelEconomy.gov selon le pays, sans position ni trajet ;
- pour un test d’alerte WhatsApp : prénom du conducteur et coordonnées du contact choisi ;
- pour un partage de position : prénom du conducteur, coordonnées du contact choisi et position au moment du partage ;
- pour une alerte de collision confirmée : coordonnées des contacts choisis, position et informations médicales facultatives nécessaires à l’assistance ;
- l’attestation du conducteur selon laquelle les contacts choisis acceptent d’être prévenus par messagerie.

Ces échanges utilisent HTTPS avec l’API Viim ou la source publique explicitement décrite par la fonction. Les seules données d’alerte sont ensuite transmises au fournisseur de messagerie chargé d’acheminer le message. Viim ne vend pas de données personnelles et n’utilise pas les données pour de la publicité ou du suivi entre applications.

## Autorisations iOS

L’utilisateur peut refuser ou retirer à tout moment les autorisations de localisation, de mouvement, de notifications ou de caméra dans les réglages iOS. Certaines fonctions, notamment la détection automatique des trajets, nécessitent la localisation et le mouvement pour fonctionner.

## Conservation et suppression

Les données locales restent sur l’appareil jusqu’à leur suppression par l’utilisateur, la suppression de l’application ou une opération de réinitialisation prévue dans Viim. Les données d’alerte côté serveur sont limitées à ce qui est nécessaire pour acheminer, diagnostiquer et prouver l’état d’envoi du message. La fiche médicale transmise lors d’une collision n’est pas conservée dans la preuve d’envoi. Les numéros nécessaires à cette preuve sont masqués dans le dashboard d’administration.

L’utilisateur peut demander l’accès, la correction ou la suppression de ses données en contactant l’éditeur.

## Sécurité

Viim utilise les protections iOS, notamment le bac à sable de l’application et le trousseau iOS pour les données sensibles. Les communications avec le service Viim utilisent HTTPS.

## Mineurs

Viim n’est pas destiné aux enfants de moins de 13 ans et ne cherche pas à collecter sciemment leurs données.

## Contact

Pour toute question relative à cette politique ou pour exercer un droit sur les données :

- Éditeur : YAMSTACK TECHNOLOGIE
- Courriel : contact@burktech.com
- Site : https://burktech-ia.com

Cette politique pourra être mise à jour lorsque les fonctions ou les obligations applicables évoluent.
