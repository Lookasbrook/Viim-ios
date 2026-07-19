# Blueprint 00 — Ordre d'exécution (point d'entrée Codex)

Tu es le builder du projet **Viim**. Ce dossier te donne la structure, les contraintes et les critères de validation — tu es libre de l'implémentation. Lis dans cet ordre : ce fichier → `01-ios-app.md` → `02-backend-coolify.md`, puis les références citées.

## Priorité actuelle — 2026-07-14

Le plan maître actif est [Fiabilité complète, véhicules, coûts et internationalisation](2026-07-14-fiabilite-vehicules-couts-internationalisation.md).

Il remplace les règles contradictoires des anciens blueprints concernant le prix saisi manuellement, la consommation modifiée par le score, le véhicule identifié seulement par marque/modèle, la devise FCFA unique et la validation de dix trajets avant la build privée. Les anciens documents restent des preuves historiques et des diagnostics ; en cas de conflit, le blueprint du 2026-07-14 prévaut.

Ordre actif : `P0 capture/indicateur et build privée` → `P1 catalogue` → `P2 prix/devises` → `P3 inscription/migration` → `P4 coût` → `P5 sync/écrans` → `P6 assistance` → `P7 validation externe`.

## Prérequis (à vérifier avant la première ligne de code)

1. Accès au VPS Hetzner CX33 + Coolify (burktech-ia.com) — **identifiants sur le Mac de Guy, jamais dans le repo**. Tout secret passe par les variables d'environnement Coolify.
2. Compte développeur Apple : connecté et configuré (déjà fait).
3. NEwAGENT-IA : déjà déployé et opérationnel sur le VPS — vérifier l'endpoint et le token auprès de Guy.
4. Créer le repo Git unique `viim` (monorepo `ios/` + `backend/`) — voir [ADR](../decisions/2026-07-01-repo-monorepo.md).

## Règles transverses non négociables

- Nom visible : **Viim** partout ; YAMSTACK TECHNOLOGIE uniquement en pied de l'onglet Assistance + À propos (`design/branding-vocabulaire.md`).
- Cartes : **MapKit natif, dans l'app**.
- Aucune chaîne en dur : `Localizable.strings` (fr) dès le départ.
- Vouvoiement dans l'UI ; typographie française (espaces insécables, "19 h 06", "1 200 F").
- Offline-first : CoreData + flag `synced` ; l'app fonctionne intégralement sans réseau.
- Fiche médicale/contacts : Keychain uniquement (`decisions/2026-07-01-donnees-medicales-keychain.md`).

## Séquence (reprend tracking/todo.md)

| Étape | Contenu | Definition of Done |
|---|---|---|
| P0 Fondations | Repo, projet Xcode, squelette backend, `/health`, Uptime Robot | App 4 onglets vides compilée sur iPhone réel ; `/health` vert ; monitoring actif |
| P1 Capteurs & trajets | Inscription véhicule adaptatif, GPS background, filtrage, CoreData, Accueil, historique | S1 (background GPS) passe ; 1 trajet réel enregistré fidèlement, écran verrouillé |
| P2 Score & sync | ScoreEngine, montagne + portrait, SyncManager, moyennes communautaires | S3 + S4 passent ; scores visibles après calibration |
| P3 Sécurité | Collision, fiche médicale, contacts, alertes WhatsApp/SMS, localisation, constat | S2 passe ; alerte de bout en bout < 90 s |
| P4 Prévention & engagement | Zones ONASER, conditions, entretien, résumé 20 h, badges | S6 passe |
| P5 Validation | Dérouler `qa/test-plan.md` complet | Toutes les métriques ≥ seuil minimum |

## Boucle de travail obligatoire (chaque tâche)

1. Déclarer la tâche dans `tracking/in-progress.md`.
2. Implémenter ; tester sur iPhone réel (pas seulement le simulateur — capteurs !).
3. À la fin : fichier `tracking/done/[YYYY-MM-DD]-[tâche].md` (livré, écarts vs spec, commits) + entrée `CHANGELOG.md`.
4. Décision d'architecture prise en route → ADR dans `decisions/`.
5. Bug découvert → `qa/known-issues.md` immédiatement.

## Ce qui bloque une livraison

Score affiché pendant la calibration · donnée médicale dans un log ou une requête hors collision · carte non-MapKit · mention YAMSTACK hors emplacements autorisés · trajet perdu en offline.
