# TODO — priorisé pour le builder (Codex)

Ordre recommandé — démarrer par [blueprints/00-ordre-execution.md](../blueprints/00-ordre-execution.md). Chaque tâche terminée : déplacer vers `in-progress.md` puis `done/`, mettre à jour `CHANGELOG.md`.

Rappels transverses : app nommée **Viim** (règle de marque dans `design/branding-vocabulaire.md`), cartes **MapKit natif dans l'app**, aucune chaîne en dur (Localizable.strings), vouvoiement.

## Phase 0 — Fondations
- [x] Créer le repo Git + projet Xcode « Viim » (Swift 5.9+, iOS 16+, SwiftUI) avec les 4 onglets vides et la charte couleurs (README).
- [x] Activer Capabilities : Background Modes (`location`), Push Notifications.
- [x] Squelette backend Node.js sur Coolify + PostgreSQL + endpoint `/health`.
- [ ] Configurer Uptime Robot sur `/health` (5 min, alerte SMS + WhatsApp). **Reporté par décision PO le 2026-07-03 ; obligatoire avant tout testeur externe.**

## Phase 1 — Capteurs & trajets (cœur du MVP)
- [x] Parcours d'inscription 3 étapes avec véhicule adaptatif + illustration (features/inscription-onboarding.md).
- [x] `LocationService` : background GPS, détection auto début/fin de trajet.
- [ ] `SensorService` : CoreMotion 50 Hz, filtre passe-bas (alpha selon véhicule), buffer 30 s.
- [x] `TripManager` + CoreData (`Trip`, `TripEvent`, flag `synced`).
- [ ] Détection d'événements avec confirmation GPS (sensor-algorithms.md §2-3).
- [x] Ancienne phase silencieuse de 5 trajets supprimée par décision produit : score GPS personnel affiché dès le premier trajet enregistré.
- [x] Onglet Accueil (résumé du jour + statuts + trajets du jour, détail navigation, emplacement coût carburant).
- [ ] Onglet Votre conduite : historique complet + événements.

## Phase 2 — Score & sync
- [ ] `ScoreEngine` : 5 critères + score global + couleur polyline.
- [ ] Vue montagne + portrait détaillé avec comparaison "Les autres".
- [ ] `SyncManager` : NWPathMonitor, `/trips/batch` idempotent.
- [ ] Backend : agrégats communautaires + `/community/averages`.

## Phase 3 — Sécurité (Assistance)
- [ ] `CollisionDetector` + fenêtre annulation 60 s.
- [ ] `MedicalVault` (Keychain AES-256) + écran fiche médicale.
- [x] Contacts d'urgence + bouton test WhatsApp (`/alerts/test`).
- [ ] Micro-sync collision (URLSession background) + cascade WhatsApp backend + SMS fallback.
- [x] Voir ma localisation + partage WhatsApp ponctuel.
- [ ] Assistance routière complète (18/17, hôpitaux), constat PDF.

## Phase 4 — Prévention & engagement
- [ ] Zones dangereuses ONASER + geofencing ; conditions de route.
- [ ] Entretien véhicule + rappels.
- [ ] Résumé WhatsApp 20h00 (cron backend via NEwAGENT-IA).
- [ ] Écoconduite avancée : conso véhicule, prix carburant, saisie de plein ; badges ; classement opt-in.
- [ ] Profil & Paramètres complets (export, suppression, batterie, sensibilité).

## Phase 5 — Validation
- [ ] Reprendre la configuration Uptime Robot si elle n'a pas été faite avant l'ouverture aux testeurs externes.
- [ ] Dérouler le plan de test (`qa/test-plan.md`) et consigner dans `qa/test-results.md`.
