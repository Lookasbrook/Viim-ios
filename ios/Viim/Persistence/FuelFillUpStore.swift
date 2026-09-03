import CoreData
import Foundation

struct FuelFillUpRecord: Equatable, Identifiable {
    let id: UUID
    let vehicleIdentity: String
    let vehicleDisplayName: String
    let fuelType: VehicleFuelType
    let odometerKm: Double
    let liters: Double
    let occurredAt: Date
    let createdAt: Date
}

struct FuelCalibrationEvidence: Equatable {
    let litersPer100Km: Double
    let intervalCount: Int
    let totalDistanceKm: Double
    let lastFillUpAt: Date
    let uncertaintyRatio: Double
    let sourceIdentifier: String
}

enum FuelFillUpValidationError: Error, Equatable {
    case unsupportedVehicle
    case fullTankConfirmationRequired
    case invalidOdometer
    case invalidLiters
    case invalidDate
    case nonMonotonicOdometer
    case nonMonotonicDate
    case storageUnavailable
}

struct FuelFillUpStore {
    static let minimumCalibrationIntervalCount = 2
    static let maximumCalibrationIntervalCount = 8

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    @discardableResult
    func recordFullTank(
        profile: UserProfile,
        odometerKm: Double,
        liters: Double,
        fullTankConfirmed: Bool,
        occurredAt: Date = Date(),
        now: Date = Date()
    ) throws -> FuelFillUpRecord {
        guard let fuelType = profile.fuelType,
              fuelType.supportsLiquidFuelEstimate,
              profile.vehicleType != .velo else {
            throw FuelFillUpValidationError.unsupportedVehicle
        }
        guard fullTankConfirmed else {
            throw FuelFillUpValidationError.fullTankConfirmationRequired
        }
        guard odometerKm.isFinite, (0..<3_000_000).contains(odometerKm) else {
            throw FuelFillUpValidationError.invalidOdometer
        }
        guard liters.isFinite, (0.2...250).contains(liters) else {
            throw FuelFillUpValidationError.invalidLiters
        }
        guard occurredAt <= now.addingTimeInterval(5 * 60),
              occurredAt >= Date(timeIntervalSince1970: 946_684_800) else {
            throw FuelFillUpValidationError.invalidDate
        }

        let identity = Self.vehicleIdentity(for: profile)
        return try context.performAndWait {
            let previous = try fetchRecords(vehicleIdentity: identity, limit: 1).first
            if let previous {
                guard odometerKm > previous.odometerKm else {
                    throw FuelFillUpValidationError.nonMonotonicOdometer
                }
                guard occurredAt > previous.occurredAt else {
                    throw FuelFillUpValidationError.nonMonotonicDate
                }
            }

            guard let entity = NSEntityDescription.entity(forEntityName: "FuelFillUp", in: context) else {
                throw FuelFillUpValidationError.storageUnavailable
            }
            let object = NSManagedObject(entity: entity, insertInto: context)
            let record = FuelFillUpRecord(
                id: UUID(),
                vehicleIdentity: identity,
                vehicleDisplayName: profile.vehicleDisplayName,
                fuelType: fuelType,
                odometerKm: odometerKm,
                liters: liters,
                occurredAt: occurredAt,
                createdAt: now
            )
            object.setValue(record.id, forKey: "id")
            object.setValue(record.vehicleIdentity, forKey: "vehicleIdentity")
            object.setValue(record.vehicleDisplayName, forKey: "vehicleDisplayName")
            object.setValue(record.fuelType.rawValue, forKey: "fuelType")
            object.setValue(record.odometerKm, forKey: "odometerKm")
            object.setValue(record.liters, forKey: "liters")
            object.setValue(true, forKey: "isFullTank")
            object.setValue(record.occurredAt, forKey: "occurredAt")
            object.setValue(record.createdAt, forKey: "createdAt")
            object.setValue(false, forKey: "synced")
            try context.save()
            return record
        }
    }

    func records(for profile: UserProfile, limit: Int = 20) throws -> [FuelFillUpRecord] {
        let identity = Self.vehicleIdentity(for: profile)
        return try context.performAndWait {
            try fetchRecords(vehicleIdentity: identity, limit: limit)
        }
    }

    @discardableResult
    func deleteLatestRecord(for profile: UserProfile) throws -> FuelFillUpRecord? {
        let identity = Self.vehicleIdentity(for: profile)
        return try context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "FuelFillUp")
            request.predicate = NSPredicate(
                format: "vehicleIdentity == %@ AND isFullTank == YES",
                identity
            )
            request.sortDescriptors = [NSSortDescriptor(key: "occurredAt", ascending: false)]
            request.fetchLimit = 1
            guard let object = try context.fetch(request).first,
                  let record = Self.record(from: object) else {
                return nil
            }
            context.delete(object)
            try context.save()
            return record
        }
    }

    func calibration(
        for profile: UserProfile,
        baseProfile: VehicleFuelProfile?
    ) throws -> FuelCalibrationEvidence? {
        guard let baseProfile,
              let fuelType = profile.fuelType,
              fuelType.supportsLiquidFuelEstimate,
              baseProfile.litersPer100Km > 0 else {
            return nil
        }
        let identity = Self.vehicleIdentity(for: profile)
        let records = try context.performAndWait {
            try fetchRecords(vehicleIdentity: identity, limit: Self.maximumCalibrationIntervalCount + 1)
        }.reversed()
        let ordered = Array(records)
        guard ordered.count >= Self.minimumCalibrationIntervalCount + 1 else {
            return nil
        }

        let intervals = zip(ordered, ordered.dropFirst()).compactMap { previous, current in
            Self.validInterval(previous: previous, current: current, vehicleType: profile.vehicleType)
        }
        guard intervals.count >= Self.minimumCalibrationIntervalCount else {
            return nil
        }

        let retained = Self.removingOutliers(intervals)
        guard retained.count >= Self.minimumCalibrationIntervalCount else {
            return nil
        }
        let totalDistance = retained.reduce(0) { $0 + $1.distanceKm }
        let totalLiters = retained.reduce(0) { $0 + $1.liters }
        guard totalDistance > 0 else { return nil }
        let observedConsumption = totalLiters / totalDistance * 100
        let ratio = observedConsumption / baseProfile.litersPer100Km
        guard (0.55...1.80).contains(ratio) else {
            return nil
        }

        let weightedVariance = retained.reduce(0) { partial, interval in
            let delta = interval.litersPer100Km - observedConsumption
            return partial + interval.distanceKm * delta * delta
        } / totalDistance
        let relativeStandardDeviation = sqrt(max(0, weightedVariance)) / observedConsumption
        let uncertainty = retained.count == 2
            ? max(0.18, min(0.25, relativeStandardDeviation + 0.06))
            : max(0.08, min(0.25, relativeStandardDeviation + 0.05))
        let lastFillUpAt = retained.map { $0.endedAt }.max() ?? ordered.last!.occurredAt
        let fingerprint = Self.identityFingerprint(identity)
        let source = String(
            format: "ViimFullTank.v1#%@#n=%d#km=%.0f#at=%.0f",
            fingerprint,
            retained.count,
            totalDistance,
            lastFillUpAt.timeIntervalSince1970
        )
        return FuelCalibrationEvidence(
            litersPer100Km: observedConsumption,
            intervalCount: retained.count,
            totalDistanceKm: totalDistance,
            lastFillUpAt: lastFillUpAt,
            uncertaintyRatio: uncertainty,
            sourceIdentifier: source
        )
    }

    static func vehicleIdentity(for profile: UserProfile) -> String {
        let specificationID = profile.vehicleSpecification?.matched(to: profile)?.qualifiedSourceIdentifier ?? "none"
        return [
            "v1",
            profile.vehicleType.rawValue,
            normalize(profile.vehicleBrand),
            normalize(profile.vehicleModel),
            normalize(profile.vehicleYear),
            profile.fuelType?.rawValue ?? "unknown",
            specificationID
        ].joined(separator: "|")
    }

    private func fetchRecords(vehicleIdentity: String, limit: Int) throws -> [FuelFillUpRecord] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "FuelFillUp")
        request.predicate = NSPredicate(format: "vehicleIdentity == %@ AND isFullTank == YES", vehicleIdentity)
        request.sortDescriptors = [NSSortDescriptor(key: "occurredAt", ascending: false)]
        request.fetchLimit = max(0, limit)
        return try context.fetch(request).compactMap(Self.record(from:))
    }

    private static func record(from object: NSManagedObject) -> FuelFillUpRecord? {
        guard let id = object.value(forKey: "id") as? UUID,
              let identity = object.value(forKey: "vehicleIdentity") as? String,
              let displayName = object.value(forKey: "vehicleDisplayName") as? String,
              let fuelRawValue = object.value(forKey: "fuelType") as? String,
              let fuelType = VehicleFuelType(rawValue: fuelRawValue),
              let odometer = object.value(forKey: "odometerKm") as? Double,
              let liters = object.value(forKey: "liters") as? Double,
              let occurredAt = object.value(forKey: "occurredAt") as? Date,
              let createdAt = object.value(forKey: "createdAt") as? Date else {
            return nil
        }
        return FuelFillUpRecord(
            id: id,
            vehicleIdentity: identity,
            vehicleDisplayName: displayName,
            fuelType: fuelType,
            odometerKm: odometer,
            liters: liters,
            occurredAt: occurredAt,
            createdAt: createdAt
        )
    }

    private struct CalibrationInterval {
        let distanceKm: Double
        let liters: Double
        let litersPer100Km: Double
        let endedAt: Date
    }

    private static func validInterval(
        previous: FuelFillUpRecord,
        current: FuelFillUpRecord,
        vehicleType: VehicleType
    ) -> CalibrationInterval? {
        let distance = current.odometerKm - previous.odometerKm
        let distanceRange: ClosedRange<Double> = vehicleType == .moto ? 40...1_500 : 80...2_500
        guard distanceRange.contains(distance), current.liters > 0 else { return nil }
        let consumption = current.liters / distance * 100
        let consumptionRange: ClosedRange<Double> = vehicleType == .moto ? 0.5...15 : 1.5...35
        guard consumptionRange.contains(consumption) else { return nil }
        return CalibrationInterval(
            distanceKm: distance,
            liters: current.liters,
            litersPer100Km: consumption,
            endedAt: current.occurredAt
        )
    }

    private static func removingOutliers(_ intervals: [CalibrationInterval]) -> [CalibrationInterval] {
        guard intervals.count >= 3 else { return intervals }
        let sorted = intervals.map(\.litersPer100Km).sorted()
        let median = sorted[sorted.count / 2]
        return intervals.filter { abs($0.litersPer100Km - median) / median <= 0.35 }
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    private static func identityFingerprint(_ identity: String) -> String {
        var value: UInt64 = 14_695_981_039_346_656_037
        for byte in identity.utf8 {
            value ^= UInt64(byte)
            value &*= 1_099_511_628_211
        }
        return String(value, radix: 16)
    }
}
