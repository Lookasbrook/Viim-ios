# Architecture — Vue d'ensemble

## Schéma global

```
┌─────────────────────────────── iPhone (iOS 16+) ───────────────────────────────┐
│                                                                                 │
│  SwiftUI (4 onglets)          Services                        Stockage          │
│  ┌──────────────┐   ┌────────────────────────┐   ┌──────────────────────────┐  │
│  │ Accueil      │   │ TripManager            │   │ CoreData                 │  │
│  │ VotreConduite│◄──│ SensorService (CoreMotion)│◄─│  Trip, TripEvent,        │  │
│  │ Assistance   │   │ LocationService (CoreLoc)│  │  DailySummary (synced:)  │  │
│  │ Prévention   │   │ CollisionDetector      │   ├──────────────────────────┤  │
│  └──────────────┘   │ ScoreEngine            │   │ Keychain (AES-256)       │  │
│                     │ SyncManager (NWPathMon)│   │  Fiche médicale, contacts │  │
│                     │ AlertService           │   └──────────────────────────┘  │
│                     └───────────┬────────────┘                                 │
└─────────────────────────────────┼───────────────────────────────────────────────┘
                                  │ HTTPS (URLSession, background session pour collision)
                                  ▼
┌──────────────── Hetzner CX33 — Coolify — api.burktech-ia.com ───────────────────┐
│  Node.js API (viim-api) ──► PostgreSQL                                          │
│      │                                                                          │
│      ├──► NEwAGENT-IA (sur burktech-ia.com) — alertes collision + résumé 20h    │
│      └──► /health — monitoring Uptime Robot (5 min, alerte SMS + WhatsApp)      │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Principes directeurs

1. **Offline-first** : tout est écrit d'abord dans CoreData avec `synced: false`. Le `SyncManager` (via `NWPathMonitor`) pousse vers le backend dès que le réseau revient. L'app doit être 100% fonctionnelle sans réseau (hors alertes).
2. **Aucun boîtier** : uniquement les capteurs du téléphone. La qualité des données dépend donc du filtrage logiciel — voir [sensor-algorithms.md](sensor-algorithms.md).
3. **Vie privée par défaut** : fiche médicale et contacts d'urgence dans le Keychain (AES-256), jamais transmis au backend en routine. Transmission uniquement sur collision confirmée (pas de réponse sous 60 s).
4. **WhatsApp d'abord, SMS ensuite** : canal primaire WhatsApp via NEwAGENT-IA (déjà opérationnel sur le VPS) ; fallback SMS natif si échec ou pas de data.
5. **Économie de batterie** : cible < 12% / 2h de trajet. GPS 5 m par défaut, 20 m en mode économie. Capteurs coupés hors trajet (détection automatique début/fin de trajet).

## Modules Swift (découpage proposé — le builder est libre de l'organisation interne)

| Module | Responsabilité |
|---|---|
| `SensorService` | CMMotionManager, filtre passe-bas, buffer circulaire 30 s pré-impact |
| `LocationService` | CLLocationManager, `allowsBackgroundLocationUpdates = true`, détection début/fin trajet |
| `TripManager` | Cycle de vie d'un trajet, agrégation des événements, persistance CoreData |
| `ScoreEngine` | Calcul des 5 critères + score global 0-100 (voir sensor-algorithms.md) |
| `CollisionDetector` | Détection choc, fenêtre annulation 60 s, déclenchement AlertService |
| `AlertService` | WhatsApp via API backend + SMS fallback (MessageUI) |
| `SyncManager` | NWPathMonitor, file de sync, `URLSessionConfiguration.background` pour la micro-sync collision |
| `MedicalVault` | Lecture/écriture Keychain, chiffrement AES-256 |

## Contraintes iOS non négociables

- Background mode `location` activé dans les Capabilities Xcode.
- `allowsBackgroundLocationUpdates = true` sinon iOS suspend le tracking à l'écran verrouillé.
- Micro-sync collision via `URLSessionConfiguration.background` pour survivre aux suspensions.
- Phase de calibration : 5 premiers trajets sans affichage de score, flag `calibration: true` vers le backend.

## Décisions actées (voir decisions/)

- [2026-07-01 — iOS first malgré 92% Android](../decisions/2026-07-01-ios-first.md)
- [2026-07-01 — WhatsApp canal d'alerte primaire](../decisions/2026-07-01-whatsapp-alertes.md)
- [2026-07-01 — Données médicales : Keychain uniquement](../decisions/2026-07-01-donnees-medicales-keychain.md)
- [2026-07-01 — Filtrage capteurs : low-pass + confirmation GPS](../decisions/2026-07-01-filtrage-capteurs.md)
- [2026-07-01 — Repo Git unique `viim` (monorepo)](../decisions/2026-07-01-repo-monorepo.md)
- [2026-07-01 — API sur sous-domaine `api.burktech-ia.com`](../decisions/2026-07-01-sous-domaine-api.md)
