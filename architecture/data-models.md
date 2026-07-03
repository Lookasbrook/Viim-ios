# Modèles de données — Swift (CoreData) + API

Le builder est libre des détails d'implémentation ; les champs ci-dessous sont le contrat minimal.

## CoreData (local, offline-first)

Toutes les entités persistées portent `synced: Bool` et `createdAt: Date`.

### Trip

```swift
id: UUID
startDate / endDate: Date
distanceKm: Double
durationSec: Int
avgSpeedKmh / maxSpeedKmh: Double
score: Int?                    // nil pendant la calibration
scoreVitesse / scoreFluidite / scoreVigilance / scoreEco: Int?
fuelLiters: Double?            // estimation
fuelFCFA: Int?
polyline: Data                 // points GPS encodés (ou relation vers TripPoint)
isCalibration: Bool            // true pour les 5 premiers trajets
vehicleType: String            // moto | voiture | velo
role: String                   // conducteur | passager (modifiable a posteriori, cf. BNA)
synced: Bool
```

### TripEvent

```swift
id: UUID
tripId: UUID (relation)
type: String        // freinage_brusque | acceleration_brusque | virage_serre | exces_vitesse | distraction | collision
timestamp: Date
latitude / longitude: Double
intensity: Double   // valeur filtrée du pic
gpsConfirmed: Bool  // doit être true pour être comptabilisé
```

### DailySummary

```swift
date: Date
tripsCount: Int
totalKm: Double
totalDurationSec: Int
avgScore: Int?
fuelFCFA: Int?
synced: Bool        // déclenche le résumé WhatsApp de 20h côté backend
```

### Vehicle / UserProfile (CoreData)

```swift
// Vehicle
type: String (moto|voiture|velo), brand, model, year
illustrationAsset: String      // mapping marque+modèle → asset, fallback silhouette du type
photoLocalPath: String?        // photo réelle prise par l'utilisateur — JAMAIS synchronisée
refConsumptionL100: Double?    // calibrée par saisie de plein
odometerKm: Double             // alimenté par l'app, sert aux rappels entretien
// UserProfile
firstName: String
phoneE164: String              // numéro WhatsApp de l'utilisateur
badges: [String]
leaderboardOptIn: Bool         // false par défaut
```

## Keychain (AES-256 — ne quitte jamais l'appareil sauf collision confirmée)

```swift
// MedicalRecord
bloodType: String              // A+…O-
allergies: String
chronicDiseases: String
medications: String            // max 200 caractères
idNumber: String               // CNIB

// EmergencyContact (jusqu'à 3, ordonnés par priorité)
name, phoneE164, relation: String
priority: Int                  // 1 = prioritaire, 2 = si non-lu 5 min, 3 = backup
customMessage: String?
```

## PostgreSQL (backend — miroir sync)

Tables `users`, `trips`, `trip_events`, `daily_summaries` reprenant les champs ci-dessus + `device_id`, `received_at`. Les trajets `calibration=true` sont stockés mais **exclus** des agrégats communautaires (`community_averages` par critère, recalculés quotidiennement pour la comparaison "Les autres — Ouagadougou").

**Jamais stocké en base** : fiche médicale, contacts d'urgence (transmis uniquement dans le payload d'alerte collision, relayés à WhatsApp, non persistés).

## Payload collision (micro-sync, URLSession background)

```json
{
  "type": "collision",
  "userId": "...",
  "timestamp": "2026-07-01T20:55:00Z",
  "location": { "lat": 12.3714, "lng": -1.5197, "accuracy": 8 },
  "preImpactData": [ /* 30 s de capteurs échantillonnés */ ],
  "medical": { "bloodType": "O+", "allergies": "...", "...": "..." },
  "contacts": [ { "name": "...", "phone": "+226...", "priority": 1 } ]
}
```
