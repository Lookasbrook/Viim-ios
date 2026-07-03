# CHANGELOG — Viim (yamstack-ios)

Toutes les modifications notables du projet, par date (plus récent en haut).

## 2026-07-02

- **[P0]** Initialisation du repo GitHub cloné `Viim-ios` avec la documentation existante et la structure monorepo `ios/` + `backend/`.
- **[iOS]** Ajout du projet Xcode `Viim` (SwiftUI, iOS 16+, 4 onglets localisés, charte couleurs, background modes, entitlements Push, Team ID `MJJ6A56JHS`).
- **[Backend]** Ajout du squelette `viim-api` Node/Express avec `/health`, migration PostgreSQL initiale et Dockerfile Coolify.
- **[QA]** Build simulateur iOS OK, backend `/health` local OK ; blocages P0 consignés dans `qa/known-issues.md` pour signature iPhone réel, DNS API et SSH Coolify.
- **[QA]** Diagnostic signature iPhone réel affiné : certificat YELIM valide, build de contrôle OK sans APNs, échec normal causé par absence de profil Push `com.yamstack.viim` et par absence de compte Apple visible pour `xcodebuild`.
- **[iOS]** Résolution du build iPhone réel : profil `iOS Team Provisioning Profile: com.yamstack.viim` avec Push activé, build signé OK, installation et lancement confirmés sur l'iPhone de Guy.
- **[iOS]** Correction du packaging app : ajout des clés bundle standard dans `Info.plist` pour permettre l'installation (`CFBundleIdentifier`, version, exécutable, type).
- **[Repo]** Préparation de la publication du monorepo `Viim-ios` vers GitHub afin que Coolify puisse construire `backend/Dockerfile`.
- **[Repo]** Publication effective du monorepo sur `Lookasbrook/Viim-ios`, branche `main`, commit `253ee3a`, pour débloquer la création de l'app Viim dans Coolify.
- **[Backend]** Déploiement Coolify confirmé sur le VPS `178.105.115.6` : app Viim `blqn1beg8ae0dvddmqio6rth`, PostgreSQL Viim `v46pxb68fon91lz66pdyomot`, migrations initiales appliquées, `/health` runtime en `degraded` tant que NEwAGENT-IA n'est pas configuré.
- **[DNS]** Enregistrement `api.burktech-ia.com` corrigé côté authoritative vers `178.105.115.6`; TLS Let's Encrypt confirmé côté infra, mais `/health` reste `degraded` tant que le token NEwAGENT-IA n'est pas configuré.
- **[Backend]** Runtime Viim revérifié : `DATABASE_URL` et `NEWAGENT_URL` sont présents, `NEWAGENT_TOKEN` absent ; `/health` public retourne encore HTTP 503 `degraded`.
- **[Backend]** `NEWAGENT_TOKEN` configuré dans Coolify sans exposition du secret ; `/health` public de Viim retourne HTTP 200 avec `status:"ok"`, DB et WhatsApp OK.
- **[Monitoring]** Uptime Robot reste à configurer : endpoint `/health` prêt et vert, mais aucun accès/API key Uptime Robot disponible dans la session Codex.

## 2026-07-01 (nuit) — QA pré-handoff builder

- **[ADR]** Les 2 décisions laissées ouvertes dans `blueprints/00-ordre-execution.md` et `02-backend-coolify.md` sont tranchées par Claude (Architecte/QA) pour débloquer le démarrage du builder :
  - Repo Git unique `viim` (monorepo `ios/` + `backend/`) — [décisions/2026-07-01-repo-monorepo.md](decisions/2026-07-01-repo-monorepo.md).
  - API sur sous-domaine dédié `api.burktech-ia.com` (au lieu du domaine racine partagé avec NEwAGENT-IA) — [décisions/2026-07-01-sous-domaine-api.md](decisions/2026-07-01-sous-domaine-api.md).
- **[Sync]** Références mises à jour en conséquence : `blueprints/00-ordre-execution.md`, `01-ios-app.md`, `02-backend-coolify.md`, `architecture/api-endpoints.md`, `architecture/overview.md`, `qa/test-plan.md`.
- **[QA]** Revue complète de la documentation (17 fichiers .md) avant transmission au builder : cohérence vérifiée (branding, seuils capteurs, endpoints, ADRs), aucun bug bloquant (`qa/known-issues.md` vide, projet non démarré).

## 2026-07-01 (soir)

- **[Naming]** L'application s'appelle **Viim** (« la vie » en mooré) — décision de Guy. Règle de marque : YAMSTACK TECHNOLOGIE visible uniquement en pied de l'onglet Assistance + mentions légales (`design/branding-vocabulaire.md`).
- **[Design]** Maquettes v2 (`design/maquettes-ecrans.html`) : écran d'inscription avec véhicule adaptatif et illustration (modèle BNA), onglets alignés (icônes SVG), vocabulaire et typographie français soignés, carte MapKit natif.
- **[Specs]** Nouveau `features/inscription-onboarding.md` (adaptation de l'app au moyen de déplacement) ; `data-models.md` (illustration/photo véhicule), `api-endpoints.md`, `onglet-1-accueil.md` (carte véhicule suivi) réalignés ; notification collision au vouvoiement.
- **[Blueprints]** Création de `blueprints/` : ordre d'exécution, blueprint iOS, blueprint backend Hetzner/Coolify — point d'entrée du builder (Codex).

## 2026-07-01

- **[Design]** Maquettes HTML des 6 écrans clés dans `design/maquettes-ecrans.html` + propositions de nom (LAAFI SIRA / SIRA / BURKINDI) — remplacées le soir même par la décision **Viim**.
- **[Init]** Création de la structure documentaire complète (architecture, features, tracking, qa, decisions) par Claude (Architecte/QA).
- **[Init]** Rédaction des 4 ADRs fondateurs : iOS-first, WhatsApp comme canal d'alerte primaire, Keychain pour données médicales, filtrage capteurs (low-pass + confirmation GPS).
- **[Init]** Spécifications features rédigées à partir du Cahier des Charges v2.0 et des captures d'écran de référence BNA (Banque Nationale Assurances).
- **[Init]** Plan de test MVP avec métriques cibles définies dans `qa/test-plan.md`.
