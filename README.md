# Viim — Application iOS de suivi de conduite et sécurité routière

**Viim** (« la vie » en mooré) — éditée par YAMSTACK TECHNOLOGIE (SARL, Ouagadougou, Burkina Faso).

> Règle de marque : "Viim" partout dans l'app ; "YAMSTACK TECHNOLOGIE" uniquement en pied de l'onglet Assistance et dans les mentions légales. Détails : [design/branding-vocabulaire.md](design/branding-vocabulaire.md).

## Vision

Au Burkina Faso, un accident de la route survient toutes les 23 minutes ; 65 % des accidents sont causés par des comportements modifiables. Viim est la première application de suivi de conduite pensée pour le marché africain francophone : capteurs natifs du smartphone (aucun boîtier), alertes WhatsApp, économies en FCFA, adaptée aux motos et aux routes de Ouagadougou. L'app s'adapte au **moyen de déplacement déclaré à l'inscription** (illustration du véhicule, seuils, textes, entretien).

**Référence UX** : application Banque Nationale Assurances (Canada). Maquettes : [design/maquettes-ecrans.html](design/maquettes-ecrans.html).

## Stack

| Couche | Technologie |
|---|---|
| Mobile | Swift 5.9+ / iOS 16+ / SwiftUI |
| Capteurs | CoreMotion (CMMotionManager) |
| Localisation | CoreLocation — background mode `location` obligatoire |
| Cartographie | **MapKit natif, affiché dans l'app** (jamais d'app externe pour la consultation) |
| Stockage local | CoreData (flag `synced`) |
| Données sensibles | Keychain + AES-256 |
| Backend | Node.js sur Hetzner CX33 via Coolify — burktech-ia.com |
| Base de données | PostgreSQL |
| Alertes | WhatsApp Business API (NEwAGENT-IA) + SMS fallback (MessageUI) |

## Navigation — 4 onglets

| Onglet | Contenu | Couleur active |
|---|---|---|
| Accueil | Véhicule suivi, résumé du jour, statuts, derniers trajets | Navy `#1A3A5C` |
| Votre conduite | Score montagne, portrait 5 critères, historique | Bleu `#2E75B6` |
| Assistance | Collision, alerte famille, fiche médicale, constat | Rouge `#C00000` |
| Prévention | Zones dangereuses, conditions route, entretien | Vert `#217346` |

## Liens rapides

- **Blueprints d'exécution (Codex commence ici)** : [blueprints/](blueprints/)
- Architecture globale : [architecture/overview.md](architecture/overview.md)
- Algorithmes capteurs (critique) : [architecture/sensor-algorithms.md](architecture/sensor-algorithms.md)
- Modèles de données : [architecture/data-models.md](architecture/data-models.md)
- API backend : [architecture/api-endpoints.md](architecture/api-endpoints.md)
- Inscription & véhicule adaptatif : [features/inscription-onboarding.md](features/inscription-onboarding.md)
- Spécifications par onglet : [features/](features/)
- Branding & vocabulaire : [design/branding-vocabulaire.md](design/branding-vocabulaire.md)
- À faire : [tracking/todo.md](tracking/todo.md) · Plan de test : [qa/test-plan.md](qa/test-plan.md) · ADRs : [decisions/](decisions/)

## Équipe et rôles

| Rôle | Personne |
|---|---|
| Product Owner | Guy (Teli) |
| Développeur principal (Builder — Codex) | François De Salle |
| Gérant PDG | Hyacinthe WANGRAWA |
| Architecte + QA | Claude |

## Phase actuelle : MVP — test de fiabilité capteurs

Groupe fermé (famille, amis, iPhone). Métriques et seuils dans [qa/test-plan.md](qa/test-plan.md).

## Convention de travail

Chaque étape complétée par le builder : mise à jour de `tracking/in-progress.md`, fichier daté dans `tracking/done/`, entrée dans `CHANGELOG.md`, ADR dans `decisions/` si décision d'architecture.
