import CoreData
import CoreLocation
import Foundation

enum ActiveTripDraftPhase: String, Equatable {
    case candidate
    case active
}

struct ActiveTripDraftRecord: Equatable, Identifiable {
    let id: UUID
    let startedAt: Date
    let lastUpdatedAt: Date
    let lastMovingAt: Date
    let distanceMeters: CLLocationDistance
    let sampleCount: Int
    let vehicleType: VehicleType
    let createdAt: Date
    let phase: ActiveTripDraftPhase
}

struct TripCaptureOutcomeRecord: Equatable, Identifiable {
    let id: UUID
    let tripId: UUID
    let createdAt: Date
    let status: String
    let reason: String
    let source: String
    let sampleCount: Int
}

struct ActiveTripJournal {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func saveCandidate(
        id: UUID,
        vehicleType: VehicleType,
        samples: [LocationSample],
        distanceMeters: CLLocationDistance
    ) throws {
        guard let first = samples.first, let last = samples.last else {
            return
        }

        try context.performAndWait {
            let draft = try Self.upsertDraft(id: id, in: context)
            draft.setValue(id, forKey: "id")
            draft.setValue(first.timestamp, forKey: "startedAt")
            draft.setValue(last.timestamp, forKey: "lastUpdatedAt")
            draft.setValue(last.timestamp, forKey: "lastMovingAt")
            draft.setValue(distanceMeters, forKey: "distanceMeters")
            draft.setValue(Int64(samples.count), forKey: "sampleCount")
            draft.setValue(vehicleType.rawValue, forKey: "vehicleType")
            draft.setValue(ActiveTripDraftPhase.candidate.rawValue, forKey: "phase")
            try Self.deleteSamples(for: id, in: context)
            samples.forEach { Self.insertSample($0, tripId: id, in: context) }
            try context.save()
        }
    }

    func startTrip(
        _ activeTrip: ActiveDetectedTrip,
        vehicleType: VehicleType,
        samples: [LocationSample]
    ) throws {
        try context.performAndWait {
            let draft = try Self.upsertDraft(id: activeTrip.id, in: context)
            Self.apply(activeTrip: activeTrip, vehicleType: vehicleType, to: draft)
            draft.setValue(ActiveTripDraftPhase.active.rawValue, forKey: "phase")
            try Self.deleteSamples(for: activeTrip.id, in: context)
            samples.forEach { Self.insertSample($0, tripId: activeTrip.id, in: context) }
            try context.save()
        }
    }

    func appendSample(
        _ sample: LocationSample,
        to activeTrip: ActiveDetectedTrip,
        vehicleType: VehicleType
    ) throws {
        try context.performAndWait {
            let draft = try Self.upsertDraft(id: activeTrip.id, in: context)
            Self.apply(activeTrip: activeTrip, vehicleType: vehicleType, to: draft)
            draft.setValue(ActiveTripDraftPhase.active.rawValue, forKey: "phase")
            Self.insertSample(sample, tripId: activeTrip.id, in: context)
            try context.save()
        }
    }

    func updateDraft(_ activeTrip: ActiveDetectedTrip, vehicleType: VehicleType) throws {
        try context.performAndWait {
            let draft = try Self.upsertDraft(id: activeTrip.id, in: context)
            Self.apply(activeTrip: activeTrip, vehicleType: vehicleType, to: draft)
            draft.setValue(ActiveTripDraftPhase.active.rawValue, forKey: "phase")
            try context.save()
        }
    }

    func activeDrafts() throws -> [ActiveTripDraftRecord] {
        try context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "ActiveTripDraft")
            request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: true)]
            return try context.fetch(request).compactMap(Self.record(from:))
        }
    }

    func samples(for tripId: UUID) throws -> [LocationSample] {
        try context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "ActiveTripSample")
            request.predicate = NSPredicate(format: "tripId == %@", tripId as CVarArg)
            request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
            return try context.fetch(request).compactMap(Self.sample(from:))
        }
    }

    func deleteTrip(id tripId: UUID) throws {
        try context.performAndWait {
            try Self.deleteSamples(for: tripId, in: context)

            let draftRequest = NSFetchRequest<NSManagedObject>(entityName: "ActiveTripDraft")
            draftRequest.predicate = NSPredicate(format: "id == %@", tripId as CVarArg)
            draftRequest.fetchLimit = 1
            try context.fetch(draftRequest).forEach(context.delete)

            try context.save()
        }
    }

    /// Ecrit le resultat terminal et nettoie le brouillon dans la meme
    /// transaction Core Data. Un trajet ne peut donc plus disparaitre sans
    /// laisser une cause auditable, meme si l'app est arretee juste apres.
    func finalizeTrip(
        id tripId: UUID,
        status: String,
        reason: String,
        source: String,
        sampleCount: Int
    ) throws {
        try context.performAndWait {
            let outcome = try Self.upsertOutcome(tripId: tripId, in: context)
            outcome.setValue(tripId, forKey: "tripId")
            outcome.setValue(Date(), forKey: "createdAt")
            outcome.setValue(status, forKey: "status")
            outcome.setValue(reason, forKey: "reason")
            outcome.setValue(source, forKey: "source")
            outcome.setValue(Int64(sampleCount), forKey: "sampleCount")

            // Les echantillons d'un trajet rejete sont conserves comme preuve
            // auditable : c'est la seule trace GPS restante pour diagnostiquer
            // un rejet conteste. Les statuts persisted/duplicate n'en ont plus
            // besoin, le trajet lui-meme est la preuve.
            if status != "rejected" {
                try Self.deleteSamples(for: tripId, in: context)
            }
            let draftRequest = NSFetchRequest<NSManagedObject>(entityName: "ActiveTripDraft")
            draftRequest.predicate = NSPredicate(format: "id == %@", tripId as CVarArg)
            try context.fetch(draftRequest).forEach(context.delete)
            try context.save()
        }
    }

    func captureOutcomes() throws -> [TripCaptureOutcomeRecord] {
        try context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "TripCaptureOutcome")
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            return try context.fetch(request).compactMap(Self.outcomeRecord(from:))
        }
    }

    private static func upsertDraft(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: "ActiveTripDraft")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1

        if let existingDraft = try context.fetch(request).first {
            return existingDraft
        }

        let draft = NSManagedObject(entity: entity(named: "ActiveTripDraft", in: context), insertInto: context)
        draft.setValue(id, forKey: "id")
        draft.setValue(Date(), forKey: "createdAt")
        return draft
    }

    private static func upsertOutcome(tripId: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: "TripCaptureOutcome")
        request.predicate = NSPredicate(format: "tripId == %@", tripId as CVarArg)
        request.fetchLimit = 1
        if let existing = try context.fetch(request).first {
            return existing
        }

        let outcome = NSManagedObject(entity: entity(named: "TripCaptureOutcome", in: context), insertInto: context)
        outcome.setValue(UUID(), forKey: "id")
        return outcome
    }

    private static func apply(
        activeTrip: ActiveDetectedTrip,
        vehicleType: VehicleType,
        to object: NSManagedObject
    ) {
        object.setValue(activeTrip.id, forKey: "id")
        object.setValue(activeTrip.startedAt, forKey: "startedAt")
        object.setValue(activeTrip.lastUpdatedAt, forKey: "lastUpdatedAt")
        object.setValue(activeTrip.lastMovingAt, forKey: "lastMovingAt")
        object.setValue(activeTrip.distanceMeters, forKey: "distanceMeters")
        object.setValue(Int64(activeTrip.sampleCount), forKey: "sampleCount")
        object.setValue(vehicleType.rawValue, forKey: "vehicleType")
        if object.value(forKey: "createdAt") == nil {
            object.setValue(Date(), forKey: "createdAt")
        }
    }

    private static func insertSample(
        _ sample: LocationSample,
        tripId: UUID,
        in context: NSManagedObjectContext
    ) {
        let object = NSManagedObject(entity: entity(named: "ActiveTripSample", in: context), insertInto: context)
        object.setValue(UUID(), forKey: "id")
        object.setValue(tripId, forKey: "tripId")
        object.setValue(sample.timestamp, forKey: "timestamp")
        object.setValue(sample.latitude, forKey: "latitude")
        object.setValue(sample.longitude, forKey: "longitude")
        object.setValue(sample.speedKmh, forKey: "speedKmh")
        object.setValue(sample.horizontalAccuracy, forKey: "horizontalAccuracy")
        object.setValue(sample.speedAccuracy, forKey: "speedAccuracy")
        // createdAt porte l'heure de reception du point : c'est la seconde
        // chronologie utilisee pour restaurer la duree d'un trajet dont les
        // timestamps GPS ont ete compresses par une relivraison iOS.
        object.setValue(sample.receivedAt, forKey: "createdAt")
    }

    private static func deleteSamples(for tripId: UUID, in context: NSManagedObjectContext) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: "ActiveTripSample")
        request.predicate = NSPredicate(format: "tripId == %@", tripId as CVarArg)
        try context.fetch(request).forEach(context.delete)
    }

    private static func record(from object: NSManagedObject) -> ActiveTripDraftRecord? {
        guard let id = object.value(forKey: "id") as? UUID,
              let startedAt = object.value(forKey: "startedAt") as? Date,
              let lastUpdatedAt = object.value(forKey: "lastUpdatedAt") as? Date,
              let lastMovingAt = object.value(forKey: "lastMovingAt") as? Date,
              let vehicleTypeRaw = object.value(forKey: "vehicleType") as? String,
              let vehicleType = VehicleType(rawValue: vehicleTypeRaw) else {
            return nil
        }

        return ActiveTripDraftRecord(
            id: id,
            startedAt: startedAt,
            lastUpdatedAt: lastUpdatedAt,
            lastMovingAt: lastMovingAt,
            distanceMeters: object.value(forKey: "distanceMeters") as? Double ?? 0,
            sampleCount: Int(object.value(forKey: "sampleCount") as? Int64 ?? 0),
            vehicleType: vehicleType,
            createdAt: object.value(forKey: "createdAt") as? Date ?? startedAt,
            phase: ActiveTripDraftPhase(
                rawValue: object.value(forKey: "phase") as? String ?? ""
            ) ?? .active
        )
    }

    private static func sample(from object: NSManagedObject) -> LocationSample? {
        guard let timestamp = object.value(forKey: "timestamp") as? Date,
              let latitude = object.value(forKey: "latitude") as? Double,
              let longitude = object.value(forKey: "longitude") as? Double,
              let speedKmh = object.value(forKey: "speedKmh") as? Double,
              let horizontalAccuracy = object.value(forKey: "horizontalAccuracy") as? Double,
              let speedAccuracy = object.value(forKey: "speedAccuracy") as? Double else {
            return nil
        }

        return LocationSample(
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            speedKmh: speedKmh,
            horizontalAccuracy: horizontalAccuracy,
            speedAccuracy: speedAccuracy,
            receivedAt: object.value(forKey: "createdAt") as? Date
        )
    }

    private static func outcomeRecord(from object: NSManagedObject) -> TripCaptureOutcomeRecord? {
        guard let id = object.value(forKey: "id") as? UUID,
              let tripId = object.value(forKey: "tripId") as? UUID,
              let createdAt = object.value(forKey: "createdAt") as? Date,
              let status = object.value(forKey: "status") as? String,
              let reason = object.value(forKey: "reason") as? String,
              let source = object.value(forKey: "source") as? String else {
            return nil
        }
        return TripCaptureOutcomeRecord(
            id: id,
            tripId: tripId,
            createdAt: createdAt,
            status: status,
            reason: reason,
            source: source,
            sampleCount: Int(object.value(forKey: "sampleCount") as? Int64 ?? 0)
        )
    }

    private static func entity(named name: String, in context: NSManagedObjectContext) -> NSEntityDescription {
        guard let entity = NSEntityDescription.entity(forEntityName: name, in: context) else {
            preconditionFailure("Entite CoreData manquante: \(name)")
        }
        return entity
    }
}
