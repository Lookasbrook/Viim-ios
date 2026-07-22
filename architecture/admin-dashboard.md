# Dashboard admin Viim

## Objectif

Le poste de contrôle répond à trois questions :

1. Quelle activité le serveur Viim reçoit-il ?
2. Une alerte ou un incident exige-t-il une intervention ?
3. Quelle partie des données est réellement couverte aujourd'hui ?

URL après déploiement : `https://api.burktech-ia.com/admin`.

## Données visibles

- comptes du cercle de confiance, relations, disponibilité des notifications et statistiques volontairement partagées ;
- futurs profils et trajets présents dans les tables `users` et `trips` ;
- preuves d'envoi WhatsApp : type, état, date et identifiant fournisseur ;
- incidents du cercle : auteur, gravité, date, position arrondie et lecture par les proches ;
- santé de l'API, de PostgreSQL et du canal WhatsApp.

Le dashboard masque les numéros de téléphone et ne renvoie jamais la fiche médicale. La migration `004_remove_sensitive_alert_metadata.sql` retire aussi des anciennes alertes toute clé `medicalProfile` qui aurait été persistée avant ce correctif.

## Limite actuelle importante

Les trajets et le profil d'onboarding restent aujourd'hui sur l'iPhone, conformément à `PRIVACY.md`. Les tables PostgreSQL existent, mais l'app iOS n'appelle pas encore `/users/register` ni `/trips/batch`. Le dashboard affiche donc ces sources comme « En attente » tant qu'une synchronisation expliquée et consentie n'est pas livrée.

Les données déjà envoyées par les fonctions connectées, notamment le cercle, les alertes et les incidents, sont disponibles dès le déploiement du backend.

## Sécurité

Le dashboard est en lecture seule et fermé par défaut. Il exige :

```dotenv
ADMIN_USERNAME=identifiant-prive
ADMIN_PASSWORD=mot-de-passe-de-12-caracteres-minimum
ADMIN_SESSION_SECRET=secret-aleatoire-de-32-caracteres-minimum
ADMIN_SESSION_HOURS=8
```

Recommandation pour générer le secret hors du dépôt :

```bash
openssl rand -base64 48
```

Les variables doivent être configurées dans Coolify, jamais commitées. En production, le cookie porte les attributs `Secure`, `HttpOnly` et `SameSite=Strict`. Après cinq échecs de connexion dans une fenêtre de quinze minutes, les nouvelles tentatives de la même adresse sont temporairement refusées.

Si les identifiants ou le secret ne respectent pas les longueurs minimales, `/admin` répond `503` et aucun accès de secours n'est ouvert.

## Déploiement

1. Ajouter les quatre variables `ADMIN_*` dans l'environnement Coolify du backend Viim.
2. Déployer le backend. Le point d'entrée production applique automatiquement les migrations `003` et `004` avant d'écouter le trafic.
3. Ouvrir `/admin`, se connecter, puis vérifier dans « Système » que l'API, PostgreSQL et WhatsApp sont opérationnels.
4. Conserver les identifiants dans un gestionnaire de mots de passe et les renouveler si une personne quitte l'équipe.

Le déploiement n'est pas effectué automatiquement par l'ajout de ce dashboard.
