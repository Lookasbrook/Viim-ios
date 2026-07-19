# TODO — priorisé pour le builder (Codex)

Ordre recommandé — démarrer par [blueprints/00-ordre-execution.md](../blueprints/00-ordre-execution.md). Chaque tâche terminée : déplacer vers `in-progress.md` puis `done/`, mettre à jour `CHANGELOG.md`.

Rappels transverses : app nommée **Viim** (règle de marque dans `design/branding-vocabulaire.md`), cartes **MapKit natif dans l'app**, aucune chaîne en dur (Localizable.strings), vouvoiement.

État du durcissement du 2026-07-19 : 160/160 tests iOS + 15/15 backend, build Release 0.1.0 (17) signé, installé et lancé sur l'iPhone réel, aucun déploiement backend/TestFlight. Les cases terrain restent volontairement ouvertes.

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
- [x] Onglet Votre conduite : historique, synthèse réelle et détail des trajets.
- [ ] Enrichir l'historique avec les événements capteurs confirmés quand `SensorService` sera disponible.

## Phase 2 — Score & sync
- [x] `ScoreEngine` v3 : vitesse, fluidité, éco et score global versionnés.
- [ ] Ajouter vigilance, événements capteurs et limitations routières map-matchées avant de présenter 5 critères complets.
- [ ] Vue montagne + portrait détaillé avec comparaison "Les autres".
- [ ] `SyncManager` : NWPathMonitor, `/trips/batch` idempotent.
- [ ] Backend : agrégats communautaires + `/community/averages`.

## Phase 3 — Sécurité (Assistance)
- [ ] `CollisionDetector` + fenêtre annulation 60 s.
- [x] `MedicalVault` Keychain + écran fiche médicale et politique de partage manuel explicite.
- [x] Contacts d'urgence + bouton test WhatsApp (`/alerts/test`).
- [ ] Micro-sync collision (URLSession background) + cascade WhatsApp backend + SMS fallback.
- [x] Voir ma localisation + partage WhatsApp ponctuel.
- [x] Catalogue d'urgence BF/CA ; aucun numéro deviné pour un pays inconnu.
- [ ] Assistance routière complète : fournisseurs, hôpitaux vérifiés et constat PDF.

## Phase 4 — Prévention & engagement
- [ ] Zones dangereuses sourcees + geofencing ; les conseils embarqués actuels restent statiques et explicitement étiquetés.
- [x] Entretien véhicule local basé sur l'odomètre + rappels dans l'app.
- [ ] Résumé WhatsApp 20h00 (cron backend via NEwAGENT-IA).
- [ ] Écoconduite avancée : instantané de coût local livré ; restent variantes véhicule sourcees, saisie de plein/calibration, badges fiables et classement opt-in.
- [ ] Profil & Paramètres complets (export, suppression, batterie, sensibilité).

## Phase 5 — Validation
- [ ] Reprendre la configuration Uptime Robot si elle n'a pas été faite avant l'ouverture aux testeurs externes.
- [x] Régression automatisée locale 2026-07-19 consignée dans `qa/test-results.md` (175/175 tests).
- [ ] Exécuter les portes terrain : 3 trajets écran verrouillé, distance ≤ 5 %, clavier sur appareil, WhatsApp production.
