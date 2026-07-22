# Dashboard admin privé Viim

## Objectif

Donner au propriétaire de Viim une vue opérationnelle sur les données réellement reçues par le backend, sans contourner les promesses de confidentialité de l'app iOS.

## Livré

- interface web responsive sous `/admin` : vue d'ensemble, utilisateurs, trajets, sécurité et système ;
- statistiques PostgreSQL sur les comptes du cercle, profils synchronisés, trajets, alertes, incidents, relations et notifications ;
- fil d'activité, graphique 14 jours, file d'intervention et export CSV local des listes utilisateurs/trajets ;
- connexion admin avec mot de passe, session HMAC signée, cookie sécurisé en production et limitation des tentatives ;
- téléphones masqués, coordonnées d'incident arrondies et endpoints admin en lecture seule ;
- suppression du profil médical avant persistance d'une preuve d'alerte et migration de nettoyage des anciennes métadonnées ;
- documentation de configuration et de déploiement dans `architecture/admin-dashboard.md`.

## Écart assumé

L'app iOS ne synchronise pas encore le profil d'onboarding ni les trajets. Ce flux n'a pas été activé silencieusement, car `PRIVACY.md` indique actuellement que ces données restent sur l'appareil. Le dashboard indique clairement cette absence de couverture.

## Vérification

- `node --test test/admin.test.js test/alerts.test.js test/circle.test.js test/migrate.test.js test/newagent.test.js test/start.test.js` : 32/32 réussis ;
- vérification syntaxique des nouveaux modules et `git diff --check` ;
- connexion, navigation des cinq sections, états vides, jeu de données fictif, desktop 1440 px, tablette 768 px et mobile 375 px contrôlés dans Chromium ; aucune erreur console.

## Déploiement

Non effectué. Ajouter les secrets `ADMIN_*` dans Coolify avant de déployer le backend.
