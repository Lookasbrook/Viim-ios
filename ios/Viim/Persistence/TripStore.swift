import CoreData
import CoreLocation
import Foundation

struct TripRecord: Identifiable, Equatable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let distanceKm: Double
    let durationSec: Int
    let avgSpeedKmh: Double
    let maxSpeedKmh: Double
    let score: Int?
    let fuelLiters: Double?
    let fuelFCFA: Int?
    let isCalibration: Bool
    let vehicleType: VehicleType
    let synced: Bool
}

struct DrivingSummary: Equatable {
    var tripsCount: Int
    var totalKm: Double
    var totalDurationSec: Int
    var avgScore: Int?
    var pendingSyncCount: Int

    static let empty = DrivingSummary(
        tripsCount: 0,
        totalKm: 0,
        totalDurationSec: 0,
        avgScore: nil,
        pendingSyncCount: 0
    )
}

struct TripStore {
    private let context: NSManagedObjectContext
    private let calendar: Calendar

    init(context: NSManagedObjectContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    func tripExists(id: UUID) -> Bool {
        context.performAndWait {
            Self.tripExists(id: id, in: context)
        }
    }

    func completedTripsCount() throws -> Int {
        try context.performAndWait {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Trip")
            request.resultType = .countResultType
            return try context.count(for: request)
        }
    }

    func calibrationTripCount() throws -> Int {
        try context.performAndWait {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Trip")
            request.resultType = .countResultType
            request.predicate = NSPredicate(format: "isCalibration == YES")
            return min(5, try context.count(for: request))
        }
    }

    func insertCompletedTrip(
        _ completedTrip: CompletedDetectedTrip,
        samples: [LocationSample],
        vehicleType: VehicleType,
        isCalibration: Bool
    ) throws {
        try context.performAndWait {
            if Self.tripExists(id: completedTrip.id, in: context) {
                return
            }

            let object = NSManagedObject(entity: TripStore.entity(named: "Trip", in: context), insertInto: context)
            let distanceKm = completedTrip.distanceMeters / 1_000
            let durationSec = max(0, Int(completedTrip.duration.rounded()))
            let avgSpeedKmh = durationSec > 0 ? distanceKm / (Double(durationSec) / 3_600) : 0
            let maxSpeedKmh = samples.map(\.speedKmh).max() ?? avgSpeedKmh

            object.setValue(completedTrip.id, forKey: "id")
            object.setValue(completedTrip.startedAt, forKey: "startDate")
            object.setValue(completedTrip.endedAt, forKey: "endDate")
            object.setValue(distanceKm, forKey: "distanceKm")
            object.setValue(Int64(durationSec), forKey: "durationSec")
            object.setValue(avgSpeedKmh, forKey: "avgSpeedKmh")
            object.setValue(maxSpeedKmh, forKey: "maxSpeedKmh")
            object.setValue(nil, forKey: "score")
            object.setValue(nil, forKey: "scoreVitesse")
            object.setValue(nil, forKey: "scoreFluidite")
            object.setValue(nil, forKey: "scoreVigilance")
            object.setValue(nil, forKey: "scoreEco")
            object.setValue(nil, forKey: "fuelLiters")
            object.setValue(nil, forKey: "fuelFCFA")
            object.setValue(Self.encodedPolyline(from: samples), forKey: "polyline")
            object.setValue(isCalibration, forKey: "isCalibration")
            object.setValue(vehicleType.rawValue, forKey: "vehicleType")
            object.setValue("conducteur", forKey: "role")
            object.setValue(false, forKey: "synced")
            object.setValue(Date(), forKey: "createdAt")

            try context.save()
        }
    }

    func fetchRecentTrips(limit: Int = 3) throws -> [TripRecord] {
        try context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "Trip")
            request.sortDescriptors = [NSSortDescriptor(key: "endDate", ascending: false)]
            request.fetchLimit = limit
            return try context.fetch(request).compactMap(Self.record(from:))
        }
    }

    func fetchSummary(since startDate: Date? = nil) throws -> DrivingSummary {
        try context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "Trip")
            request.sortDescriptors = []
            if let startDate {
                request.predicate = NSPredicate(format: "endDate >= %@", startDate as NSDate)
            }

            let records = try context.fetch(request).compactMap(Self.record(from:))
            return Self.summary(from: records)
        }
    }

    func fetchTodaySummary() throws -> DrivingSummary {
        try fetchSummary(since: calendar.startOfDay(for: Date()))
    }

    func fetchLast30DaysSummary() throws -> DrivingSummary {
        let startDate = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return try fetchSummary(since: startDate)
    }

    private static func entity(named name: String, in context: NSManagedObjectContext) -> NSEntityDescription {
        guard let entity = NSEntityDescription.entity(forEntityName: name, in: context) else {
            preconditionFailure("Entite CoreData manquante: \(name)")
        }
        return entity
    }

    private static func tripExists(id: UUID, in context: NSManagedObjectContext) -> Bool {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Trip")
        request.resultType = .countResultType
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1

        do {
            return (try context.count(for: request)) > 0
        } catch {
            return false
        }
    }

    private static func record(from object: NSManagedObject) -> TripRecord? {
        guard let id = object.value(forKey: "id") as? UUID,
              let startDate = object.value(forKey: "startDate") as? Date,
              let endDate = object.value(forKey: "endDate") as? Date,
              let vehicleTypeRaw = object.value(forKey: "vehicleType") as? String,
              let vehicleType = VehicleType(rawValue: vehicleTypeRaw) else {
            return nil
        }

        return TripRecord(
            id: id,
            startDate: startDate,
            endDate: endDate,
            distanceKm: object.value(forKey: "distanceKm") as? Double ?? 0,
            durationSec: Int(object.value(forKey: "durationSec") as? Int64 ?? 0),
            avgSpeedKmh: object.value(forKey: "avgSpeedKmh") as? Double ?? 0,
            maxSpeedKmh: object.value(forKey: "maxSpeedKmh") as? Double ?? 0,
            score: optionalInt(object.value(forKey: "score")),
            fuelLiters: object.value(forKey: "fuelLiters") as? Double,
            fuelFCFA: optionalInt(object.value(forKey: "fuelFCFA")),
            isCalibration: object.value(forKey: "isCalibration") as? Bool ?? true,
            vehicleType: vehicleType,
            synced: object.value(forKey: "synced") as? Bool ?? false
        )
    }

    private static func summary(from records: [TripRecord]) -> DrivingSummary {
        let scoreValues = records.compactMap(\.score)
        let avgScore = scoreValues.isEmpty ? nil : Int((Double(scoreValues.reduce(0, +)) / Double(scoreValues.count)).rounded())

        return DrivingSummary(
            tripsCount: records.count,
            totalKm: records.reduce(0) { $0 + $1.distanceKm },
            totalDurationSec: records.reduce(0) { $0 + $1.durationSec },
            avgScore: avgScore,
            pendingSyncCount: records.filter { !$0.synced }.count
        )
    }

    private static func optionalInt(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? Int64 {
            return Int(value)
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return nil
    }

    private static func encodedPolyline(from samples: [LocationSample]) -> Data? {
        let points = samples.map { sample in
            StoredPolylinePoint(
                timestamp: sample.timestamp,
                latitude: sample.latitude,
                longitude: sample.longitude,
                speedKmh: sample.speedKmh,
                horizontalAccuracy: sample.horizontalAccuracy
            )
        }
        return try? JSONEncoder().encode(points)
    }
}

private struct StoredPolylinePoint: Codable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let speedKmh: Double
    let horizontalAccuracy: CLLocationAccuracy
}
