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
    let scoreVitesse: Int?
    let scoreFluidite: Int?
    let scoreVigilance: Int?
    let scoreEco: Int?
    let fuelLiters: Double?
    let fuelFCFA: Int?
    let routePoints: [TripRoutePoint]
    let qualityScore: Int
    let qualityConfidence: TripQualityConfidence
    let qualityReasonCodes: [TripQualityReasonCode]
    let activeDurationSec: Int
    let stationaryTailSec: Int
    let gpsAccuracyAvg: Double
    let gpsAccuracyP95: Double
    let rejectedSegmentCount: Int
    let validSegmentCount: Int
    let maxSampleGapSec: Double
    let p95SampleGapSec: Double
    let coverageRatio: Double
    let burstCount: Int
    let motionAgreementRate: Double?
    let qualityFormulaVersion: String
    let isCalibration: Bool
    let vehicleType: VehicleType
    let synced: Bool
}

struct TripRoutePoint: Codable, Equatable, Identifiable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let speedKmh: Double
    let horizontalAccuracy: CLLocationAccuracy
    let speedAccuracy: CLLocationSpeedAccuracy

    init(
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        speedKmh: Double,
        horizontalAccuracy: CLLocationAccuracy,
        speedAccuracy: CLLocationSpeedAccuracy = -1
    ) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.speedKmh = speedKmh
        self.horizontalAccuracy = horizontalAccuracy
        self.speedAccuracy = speedAccuracy
    }

    private enum CodingKeys: String, CodingKey {
        case timestamp
        case latitude
        case longitude
        case speedKmh
        case horizontalAccuracy
        case speedAccuracy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        speedKmh = try container.decode(Double.self, forKey: .speedKmh)
        horizontalAccuracy = try container.decode(Double.self, forKey: .horizontalAccuracy)
        speedAccuracy = try container.decodeIfPresent(Double.self, forKey: .speedAccuracy) ?? -1
    }

    var id: TimeInterval {
        timestamp.timeIntervalSinceReferenceDate
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct DrivingSummary: Equatable {
    var tripsCount: Int
    var totalKm: Double
    var totalDurationSec: Int
    var avgScore: Int?
    var avgScoreFluidite: Int?
    var avgScoreEco: Int?
    var fuelLiters: Double?
    // Champ historique conserve pour migrer les anciennes donnees XOF. Les
    // nouveaux affichages calculent le cout depuis fuelLiters et le prix choisi.
    var fuelFCFA: Int?
    var pendingSyncCount: Int

    static let empty = DrivingSummary(
        tripsCount: 0,
        totalKm: 0,
        totalDurationSec: 0,
        avgScore: nil,
        avgScoreFluidite: nil,
        avgScoreEco: nil,
        fuelLiters: nil,
        fuelFCFA: nil,
        pendingSyncCount: 0
    )
}

enum TripStoreError: Error {
    case unreliableTrip(MetricReasonCode)
    case rejectedTrip(TripQualityReasonCode)
}

struct TripStore {
    private let context: NSManagedObjectContext
    private let calendar: Calendar
    private static let currentUnverifiableQualityReport = TripQualityReport(
        score: 0,
        confidence: .needsReview,
        reasonCodes: [.legacyUnverified],
        activeDurationSec: 0,
        stationaryTailSec: 0,
        gpsAccuracyAvg: -1,
        gpsAccuracyP95: -1,
        rejectedSegmentCount: 0,
        validSegmentCount: 0,
        maxSampleGapSec: 0,
        p95SampleGapSec: 0,
        coverageRatio: 0,
        burstCount: 0,
        motionAgreementRate: nil,
        formulaVersion: TripQualityEngine.formulaVersion
    )

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

    func fetchQualityTelemetryEvents(limit: Int = 50) throws -> [TripQualityTelemetryRecord] {
        try context.performAndWait {
            try Self.fetchQualityTelemetryEvents(limit: limit, in: context)
        }
    }

    func fetchQualityLearningProfile(limit: Int = 50) throws -> TripQualityLearningProfile {
        try context.performAndWait {
            let records = try Self.fetchQualityTelemetryEvents(limit: limit, in: context)
            return TripQualityLearningEngine.profile(from: records)
        }
    }

    func recordQualityDecision(
        tripId: UUID?,
        report qualityReport: TripQualityReport,
        vehicleType: VehicleType,
        sampleCount: Int,
        source: TripQualityDecisionSource,
        acceptedForStorage: Bool
    ) throws {
        try context.performAndWait {
            Self.insertQualityTelemetry(
                tripId: tripId,
                report: qualityReport,
                vehicleType: vehicleType,
                sampleCount: sampleCount,
                source: source,
                acceptedForStorage: acceptedForStorage,
                in: context
            )
            try context.save()
        }
    }

    func recalculateLegacyQualityReports() throws -> Int {
        try context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "Trip")
            request.sortDescriptors = []
            request.predicate = NSPredicate(format: "qualityFormulaVersion != %@", TripQualityEngine.formulaVersion)

            let objects = try context.fetch(request)
            var updatedCount = 0

            for object in objects {
                guard let qualityReport = Self.recalculatedQualityReport(for: object) else {
                    Self.applyQualityReport(Self.currentUnverifiableQualityReport, to: object)
                    Self.insertQualityTelemetry(
                        tripId: object.value(forKey: "id") as? UUID,
                        report: Self.currentUnverifiableQualityReport,
                        vehicleType: Self.vehicleType(from: object) ?? .moto,
                        sampleCount: 0,
                        source: .historicalRecalculation,
                        acceptedForStorage: false,
                        in: context
                    )
                    object.setValue(false, forKey: "synced")
                    updatedCount += 1
                    continue
                }

                Self.applyQualityReport(qualityReport, to: object)
                let vehicleType = Self.vehicleType(from: object) ?? .moto
                let samples = Self.samples(from: Self.decodedPolyline(from: object.value(forKey: "polyline") as? Data))
                Self.insertQualityTelemetry(
                    tripId: object.value(forKey: "id") as? UUID,
                    report: qualityReport,
                    vehicleType: vehicleType,
                    sampleCount: samples.count,
                    source: .historicalRecalculation,
                    acceptedForStorage: qualityReport.shouldPersist,
                    in: context
                )

                if qualityReport.shouldPersist {
                    Self.applyRecalculatedTripMetrics(
                        samples: samples,
                        vehicleType: vehicleType,
                        durationSec: qualityReport.activeDurationSec,
                        to: object
                    )
                }

                object.setValue(false, forKey: "synced")
                updatedCount += 1
            }

            if context.hasChanges {
                try context.save()
            }

            return updatedCount
        }
    }

    func repairStoredMaxSpeedValues() throws -> Int {
        try context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "Trip")
            request.sortDescriptors = []
            request.predicate = NSPredicate(format: "maxSpeedKmh == 0")

            let objects = try context.fetch(request)
            var updatedCount = 0

            for object in objects {
                guard let vehicleType = Self.vehicleType(from: object) else {
                    continue
                }

                let samples = Self.samples(from: Self.decodedPolyline(from: object.value(forKey: "polyline") as? Data))
                let repairedMaxSpeed = Self.maxSpeedForStorage(
                    samples: samples,
                    vehicleType: vehicleType,
                    existingValue: object.value(forKey: "maxSpeedKmh") as? Double
                )
                guard repairedMaxSpeed > 0 else {
                    continue
                }

                object.setValue(repairedMaxSpeed, forKey: "maxSpeedKmh")
                object.setValue(false, forKey: "synced")
                updatedCount += 1
            }

            if context.hasChanges {
                try context.save()
            }

            return updatedCount
        }
    }

    func recalculateFuelEstimates(
        fuelProfile: VehicleFuelProfile,
        vehicleType: VehicleType
    ) throws -> Int {
        try context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "Trip")
            request.sortDescriptors = []
            request.predicate = NSPredicate(
                format: "vehicleType == %@ AND (fuelFormulaVersion == nil OR fuelFormulaVersion != %@)",
                vehicleType.rawValue,
                VehicleFuelCatalog.formulaVersion
            )

            let objects = try context.fetch(request)
            var updatedCount = 0

            for object in objects {
                let distanceKm = object.value(forKey: "distanceKm") as? Double ?? 0
                let routePoints = Self.decodedPolyline(from: object.value(forKey: "polyline") as? Data)
                let dynamics = DrivingDynamicsAnalyzer.dynamics(
                    routePoints: routePoints,
                    vehicleType: vehicleType,
                    distanceKm: distanceKm
                )
                guard let estimate = VehicleFuelCatalog.estimateConsumption(
                    distanceKm: distanceKm,
                    fuelProfile: fuelProfile,
                    dynamics: dynamics
                ) else {
                    continue
                }

                object.setValue(estimate.liters, forKey: "fuelLiters")
                object.setValue(nil, forKey: "fuelFCFA")
                object.setValue(VehicleFuelCatalog.formulaVersion, forKey: "fuelFormulaVersion")
                object.setValue(false, forKey: "synced")
                updatedCount += 1
            }

            if context.hasChanges {
                try context.save()
            }

            return updatedCount
        }
    }

    func insertCompletedTrip(
        _ completedTrip: CompletedDetectedTrip,
        samples: [LocationSample],
        vehicleType: VehicleType,
        isCalibration: Bool,
        scores: TripScores = .unavailable,
        fuelProfile: VehicleFuelProfile? = nil,
        qualityReport providedQualityReport: TripQualityReport? = nil
    ) throws {
        try context.performAndWait {
            if Self.tripExists(id: completedTrip.id, in: context) {
                return
            }

            let qualityReport = providedQualityReport ?? TripQualityEngine.report(
                completedTrip: completedTrip,
                samples: samples,
                vehicleType: vehicleType
            )
            guard qualityReport.shouldPersist else {
                Self.insertQualityTelemetry(
                    tripId: completedTrip.id,
                    report: qualityReport,
                    vehicleType: vehicleType,
                    sampleCount: samples.count,
                    source: .liveRejected,
                    acceptedForStorage: false,
                    in: context
                )
                try context.save()
                throw TripStoreError.rejectedTrip(
                    qualityReport.reasonCodes.first { $0 != .complete } ?? .legacyUnverified
                )
            }

            let distanceMetric = TripMetricsCalculator.distanceMetric(
                samples: samples,
                vehicleType: vehicleType
            )
            guard let distanceMeters = distanceMetric.value else {
                throw TripStoreError.unreliableTrip(distanceMetric.reasonCode)
            }

            let durationMetric = TripMetricsCalculator.durationMetric(completedTrip: completedTrip)
            guard let duration = durationMetric.value else {
                throw TripStoreError.unreliableTrip(durationMetric.reasonCode)
            }

            let distanceKm = distanceMeters / 1_000
            let durationSec = max(0, Int(duration.rounded()))
            let avgSpeedKmh = durationSec > 0 ? distanceKm / (Double(durationSec) / 3_600) : 0
            let maxSpeedKmh = Self.maxSpeedForStorage(
                samples: samples,
                vehicleType: vehicleType,
                existingValue: nil
            )
            let resolvedFuelProfile = fuelProfile ?? Self.defaultFuelProfile(for: vehicleType)
            let fuelEstimate = VehicleFuelCatalog.estimateConsumption(
                distanceKm: distanceKm,
                fuelProfile: resolvedFuelProfile,
                dynamics: DrivingDynamicsAnalyzer.dynamics(
                    samples: samples,
                    vehicleType: vehicleType,
                    distanceKm: distanceKm
                )
            )

            let object = NSManagedObject(entity: TripStore.entity(named: "Trip", in: context), insertInto: context)
            object.setValue(completedTrip.id, forKey: "id")
            object.setValue(completedTrip.startedAt, forKey: "startDate")
            object.setValue(completedTrip.endedAt, forKey: "endDate")
            object.setValue(distanceKm, forKey: "distanceKm")
            object.setValue(Int64(durationSec), forKey: "durationSec")
            object.setValue(avgSpeedKmh, forKey: "avgSpeedKmh")
            object.setValue(maxSpeedKmh, forKey: "maxSpeedKmh")
            Self.setOptionalInt(scores.score, forKey: "score", on: object)
            Self.setOptionalInt(scores.scoreVitesse, forKey: "scoreVitesse", on: object)
            Self.setOptionalInt(scores.scoreFluidite, forKey: "scoreFluidite", on: object)
            Self.setOptionalInt(scores.scoreVigilance, forKey: "scoreVigilance", on: object)
            Self.setOptionalInt(scores.scoreEco, forKey: "scoreEco", on: object)
            if let fuelEstimate {
                object.setValue(fuelEstimate.liters, forKey: "fuelLiters")
                object.setValue(nil, forKey: "fuelFCFA")
            } else {
                object.setValue(nil, forKey: "fuelLiters")
                object.setValue(nil, forKey: "fuelFCFA")
            }
            object.setValue(VehicleFuelCatalog.formulaVersion, forKey: "fuelFormulaVersion")
            object.setValue(Self.encodedPolyline(from: samples), forKey: "polyline")
            Self.applyQualityReport(qualityReport, to: object)
            object.setValue(isCalibration, forKey: "isCalibration")
            object.setValue(vehicleType.rawValue, forKey: "vehicleType")
            object.setValue("conducteur", forKey: "role")
            object.setValue(false, forKey: "synced")
            object.setValue(Date(), forKey: "createdAt")
            Self.insertQualityTelemetry(
                tripId: completedTrip.id,
                report: qualityReport,
                vehicleType: vehicleType,
                sampleCount: samples.count,
                source: .liveAccepted,
                acceptedForStorage: true,
                in: context
            )

            try context.save()
        }
    }

    func fetchRecentTrips(limit: Int = 3, since startDate: Date? = nil) throws -> [TripRecord] {
        try fetchTripRecords(limit: limit, since: startDate)
    }

    func fetchTrips(since startDate: Date? = nil) throws -> [TripRecord] {
        try fetchTripRecords(limit: nil, since: startDate)
    }

    private func fetchTripRecords(limit: Int?, since startDate: Date?) throws -> [TripRecord] {
        try context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "Trip")
            request.sortDescriptors = [NSSortDescriptor(key: "endDate", ascending: false)]
            if let limit {
                request.fetchLimit = limit
            }
            if let startDate {
                request.predicate = NSPredicate(format: "endDate >= %@", startDate as NSDate)
            }
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
            let learningProfile = TripQualityLearningEngine.profile(
                from: try Self.fetchQualityTelemetryEvents(limit: 50, in: context)
            )
            return Self.summary(from: records, learningProfile: learningProfile)
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
              let vehicleType = vehicleType(from: object) else {
            return nil
        }

        let distanceKm = object.value(forKey: "distanceKm") as? Double ?? 0

        return TripRecord(
            id: id,
            startDate: startDate,
            endDate: endDate,
            distanceKm: distanceKm,
            durationSec: Int(object.value(forKey: "durationSec") as? Int64 ?? 0),
            avgSpeedKmh: object.value(forKey: "avgSpeedKmh") as? Double ?? 0,
            maxSpeedKmh: object.value(forKey: "maxSpeedKmh") as? Double ?? 0,
            score: optionalInt(object.value(forKey: "score")),
            scoreVitesse: optionalInt(object.value(forKey: "scoreVitesse")),
            scoreFluidite: optionalInt(object.value(forKey: "scoreFluidite")),
            scoreVigilance: optionalInt(object.value(forKey: "scoreVigilance")),
            scoreEco: optionalInt(object.value(forKey: "scoreEco")),
            fuelLiters: object.value(forKey: "fuelLiters") as? Double,
            fuelFCFA: optionalInt(object.value(forKey: "fuelFCFA")),
            routePoints: decodedPolyline(from: object.value(forKey: "polyline") as? Data),
            qualityScore: optionalInt(object.value(forKey: "qualityScore")) ?? TripQualityReport.legacyUnverified.score,
            qualityConfidence: TripQualityConfidence(rawValue: object.value(forKey: "qualityConfidence") as? String ?? "") ?? .needsReview,
            qualityReasonCodes: decodedQualityReasonCodes(from: object.value(forKey: "qualityReasonCodes") as? String),
            activeDurationSec: optionalInt(object.value(forKey: "activeDurationSec")) ?? 0,
            stationaryTailSec: optionalInt(object.value(forKey: "stationaryTailSec")) ?? 0,
            gpsAccuracyAvg: object.value(forKey: "gpsAccuracyAvg") as? Double ?? -1,
            gpsAccuracyP95: object.value(forKey: "gpsAccuracyP95") as? Double ?? -1,
            rejectedSegmentCount: optionalInt(object.value(forKey: "rejectedSegmentCount")) ?? 0,
            validSegmentCount: optionalInt(object.value(forKey: "validSegmentCount")) ?? 0,
            maxSampleGapSec: object.value(forKey: "maxSampleGapSec") as? Double ?? 0,
            p95SampleGapSec: object.value(forKey: "p95SampleGapSec") as? Double ?? 0,
            coverageRatio: object.value(forKey: "coverageRatio") as? Double ?? 0,
            burstCount: optionalInt(object.value(forKey: "burstCount")) ?? 0,
            motionAgreementRate: object.value(forKey: "motionAgreementRate") as? Double,
            qualityFormulaVersion: object.value(forKey: "qualityFormulaVersion") as? String ?? TripQualityReport.legacyUnverified.formulaVersion,
            isCalibration: object.value(forKey: "isCalibration") as? Bool ?? true,
            vehicleType: vehicleType,
            synced: object.value(forKey: "synced") as? Bool ?? false
        )
    }

    private static func summary(
        from records: [TripRecord],
        learningProfile: TripQualityLearningProfile = .insufficientData
    ) -> DrivingSummary {
        let records = records.filter { $0.isReliableEnoughForSummary(learningProfile: learningProfile) }
        let fuelLiters = records.compactMap(\.fuelLiters)
        let fuelAmounts = records.compactMap(\.fuelFCFA)

        return DrivingSummary(
            tripsCount: records.count,
            totalKm: records.reduce(0) { $0 + $1.distanceKm },
            totalDurationSec: records.reduce(0) { $0 + $1.durationSec },
            avgScore: averageScore(records.compactMap(\.score)),
            avgScoreFluidite: averageScore(records.compactMap(\.scoreFluidite)),
            avgScoreEco: averageScore(records.compactMap(\.scoreEco)),
            fuelLiters: fuelLiters.isEmpty ? nil : fuelLiters.reduce(0, +),
            fuelFCFA: fuelAmounts.isEmpty ? nil : fuelAmounts.reduce(0, +),
            pendingSyncCount: records.filter { !$0.synced }.count
        )
    }

    private static func averageScore(_ values: [Int]) -> Int? {
        guard !values.isEmpty else {
            return nil
        }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }

    private static func defaultFuelProfile(for vehicleType: VehicleType) -> VehicleFuelProfile? {
        guard vehicleType == .velo else {
            return nil
        }

        return VehicleFuelCatalog.profile(vehicleType: vehicleType, brand: "", model: "")
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

    private static func setOptionalInt(_ value: Int?, forKey key: String, on object: NSManagedObject) {
        if let value {
            object.setValue(Int64(value), forKey: key)
        } else {
            object.setValue(nil, forKey: key)
        }
    }

    private static func encodedPolyline(from samples: [LocationSample]) -> Data? {
        let points = TripMetricsCalculator.validRoutePoints(from: samples)
        return try? JSONEncoder().encode(points)
    }

    private static func decodedPolyline(from data: Data?) -> [TripRoutePoint] {
        guard let data else {
            return []
        }
        return (try? JSONDecoder().decode([TripRoutePoint].self, from: data)) ?? []
    }

    private static func encodedQualityReasonCodes(_ reasonCodes: [TripQualityReasonCode]) -> String {
        reasonCodes.map(\.rawValue).joined(separator: ",")
    }

    private static func decodedQualityReasonCodes(from rawValue: String?) -> [TripQualityReasonCode] {
        guard let rawValue, !rawValue.isEmpty else {
            return [.legacyUnverified]
        }

        let reasonCodes = rawValue
            .split(separator: ",")
            .compactMap { TripQualityReasonCode(rawValue: String($0)) }
        return reasonCodes.isEmpty ? [.legacyUnverified] : reasonCodes
    }

    private static func fetchQualityTelemetryEvents(
        limit: Int,
        in context: NSManagedObjectContext
    ) throws -> [TripQualityTelemetryRecord] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "TripQualityTelemetry")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        if limit > 0 {
            request.fetchLimit = limit
        }
        return try context.fetch(request).compactMap(Self.qualityTelemetryRecord(from:))
    }

    private static func qualityTelemetryRecord(from object: NSManagedObject) -> TripQualityTelemetryRecord? {
        guard let id = object.value(forKey: "id") as? UUID,
              let createdAt = object.value(forKey: "createdAt") as? Date,
              let decisionSourceRaw = object.value(forKey: "decisionSource") as? String,
              let decisionSource = TripQualityDecisionSource(rawValue: decisionSourceRaw),
              let vehicleTypeRaw = object.value(forKey: "vehicleType") as? String,
              let vehicleType = VehicleType(rawValue: vehicleTypeRaw),
              let qualityConfidenceRaw = object.value(forKey: "qualityConfidence") as? String,
              let qualityConfidence = TripQualityConfidence(rawValue: qualityConfidenceRaw) else {
            return nil
        }

        return TripQualityTelemetryRecord(
            id: id,
            tripId: object.value(forKey: "tripId") as? UUID,
            createdAt: createdAt,
            decisionSource: decisionSource,
            vehicleType: vehicleType,
            qualityScore: optionalInt(object.value(forKey: "qualityScore")) ?? 0,
            qualityConfidence: qualityConfidence,
            qualityReasonCodes: decodedQualityReasonCodes(from: object.value(forKey: "qualityReasonCodes") as? String),
            acceptedForStorage: object.value(forKey: "acceptedForStorage") as? Bool ?? false,
            includedInSummaryAtDecision: object.value(forKey: "includedInSummaryAtDecision") as? Bool ?? false,
            sampleCount: optionalInt(object.value(forKey: "sampleCount")) ?? 0,
            gpsAccuracyAvg: object.value(forKey: "gpsAccuracyAvg") as? Double ?? -1,
            gpsAccuracyP95: object.value(forKey: "gpsAccuracyP95") as? Double ?? -1,
            rejectedSegmentCount: optionalInt(object.value(forKey: "rejectedSegmentCount")) ?? 0,
            validSegmentCount: optionalInt(object.value(forKey: "validSegmentCount")) ?? 0,
            maxSampleGapSec: object.value(forKey: "maxSampleGapSec") as? Double ?? 0,
            p95SampleGapSec: object.value(forKey: "p95SampleGapSec") as? Double ?? 0,
            coverageRatio: object.value(forKey: "coverageRatio") as? Double ?? 0,
            burstCount: optionalInt(object.value(forKey: "burstCount")) ?? 0,
            formulaVersion: object.value(forKey: "formulaVersion") as? String ?? "unknown",
            synced: object.value(forKey: "synced") as? Bool ?? false
        )
    }

    private static func insertQualityTelemetry(
        tripId: UUID?,
        report qualityReport: TripQualityReport,
        vehicleType: VehicleType,
        sampleCount: Int,
        source: TripQualityDecisionSource,
        acceptedForStorage: Bool,
        in context: NSManagedObjectContext
    ) {
        let object = NSManagedObject(entity: entity(named: "TripQualityTelemetry", in: context), insertInto: context)
        object.setValue(UUID(), forKey: "id")
        object.setValue(tripId, forKey: "tripId")
        object.setValue(Date(), forKey: "createdAt")
        object.setValue(source.rawValue, forKey: "decisionSource")
        object.setValue(vehicleType.rawValue, forKey: "vehicleType")
        object.setValue(Int64(qualityReport.score), forKey: "qualityScore")
        object.setValue(qualityReport.confidence.rawValue, forKey: "qualityConfidence")
        object.setValue(encodedQualityReasonCodes(qualityReport.reasonCodes), forKey: "qualityReasonCodes")
        object.setValue(acceptedForStorage, forKey: "acceptedForStorage")
        object.setValue(qualityReport.isReliableEnoughForSummary(learningProfile: .insufficientData), forKey: "includedInSummaryAtDecision")
        object.setValue(Int64(sampleCount), forKey: "sampleCount")
        object.setValue(qualityReport.gpsAccuracyAvg, forKey: "gpsAccuracyAvg")
        object.setValue(qualityReport.gpsAccuracyP95, forKey: "gpsAccuracyP95")
        object.setValue(Int64(qualityReport.rejectedSegmentCount), forKey: "rejectedSegmentCount")
        object.setValue(Int64(qualityReport.validSegmentCount), forKey: "validSegmentCount")
        object.setValue(qualityReport.maxSampleGapSec, forKey: "maxSampleGapSec")
        object.setValue(qualityReport.p95SampleGapSec, forKey: "p95SampleGapSec")
        object.setValue(qualityReport.coverageRatio, forKey: "coverageRatio")
        object.setValue(Int64(qualityReport.burstCount), forKey: "burstCount")
        object.setValue(qualityReport.formulaVersion, forKey: "formulaVersion")
        object.setValue(false, forKey: "synced")
    }

    private static func vehicleType(from object: NSManagedObject) -> VehicleType? {
        guard let vehicleTypeRaw = object.value(forKey: "vehicleType") as? String else {
            return nil
        }
        return VehicleType(rawValue: vehicleTypeRaw)
    }

    private static func recalculatedQualityReport(for object: NSManagedObject) -> TripQualityReport? {
        guard let id = object.value(forKey: "id") as? UUID,
              let startDate = object.value(forKey: "startDate") as? Date,
              let endDate = object.value(forKey: "endDate") as? Date,
              let vehicleType = vehicleType(from: object) else {
            return nil
        }

        let routePoints = decodedPolyline(from: object.value(forKey: "polyline") as? Data)
        guard !routePoints.isEmpty else {
            return nil
        }

        let samples = samples(from: routePoints)
        let distanceMeters = ((object.value(forKey: "distanceKm") as? Double) ?? 0) * 1_000
        let completedTrip = CompletedDetectedTrip(
            id: id,
            startedAt: startDate,
            endedAt: endDate,
            distanceMeters: distanceMeters,
            sampleCount: samples.count
        )
        return TripQualityEngine.report(
            completedTrip: completedTrip,
            samples: samples,
            vehicleType: vehicleType
        )
    }

    private static func applyRecalculatedTripMetrics(
        samples: [LocationSample],
        vehicleType: VehicleType,
        durationSec: Int,
        to object: NSManagedObject
    ) {
        guard let distanceMeters = TripMetricsCalculator.distanceMetric(samples: samples, vehicleType: vehicleType).value else {
            return
        }

        let distanceKm = distanceMeters / 1_000
        object.setValue(distanceKm, forKey: "distanceKm")
        object.setValue(Int64(max(0, durationSec)), forKey: "durationSec")
        object.setValue(durationSec > 0 ? distanceKm / (Double(durationSec) / 3_600) : 0, forKey: "avgSpeedKmh")
        object.setValue(
            maxSpeedForStorage(
                samples: samples,
                vehicleType: vehicleType,
                existingValue: object.value(forKey: "maxSpeedKmh") as? Double
            ),
            forKey: "maxSpeedKmh"
        )
    }

    private static func maxSpeedForStorage(
        samples: [LocationSample],
        vehicleType: VehicleType,
        existingValue: Double?
    ) -> Double {
        if let reliableMaxSpeed = TripMetricsCalculator.maxSpeedMetric(
            samples: samples,
            vehicleType: vehicleType
        ).value {
            return reliableMaxSpeed
        }

        if let legacyMaxSpeed = legacyDisplayMaxSpeed(samples: samples, vehicleType: vehicleType) {
            return legacyMaxSpeed
        }

        let fallback = existingValue ?? 0
        return fallback.isFinite && fallback > 0 ? fallback : 0
    }

    private static func legacyDisplayMaxSpeed(
        samples: [LocationSample],
        vehicleType: VehicleType
    ) -> Double? {
        let maximumReasonableSpeed = TripReliabilityRules.maximumReasonableSpeedKmh(for: vehicleType)
        let speeds = samples.compactMap { sample -> Double? in
            guard TripReliabilityRules.isValidSpeedAccuracy(sample.horizontalAccuracy),
                  sample.speedKmh.isFinite,
                  sample.speedKmh >= 0,
                  sample.speedKmh <= maximumReasonableSpeed else {
                return nil
            }
            return sample.speedKmh
        }

        return speeds.max()
    }

    private static func applyQualityReport(_ qualityReport: TripQualityReport, to object: NSManagedObject) {
        object.setValue(Int64(qualityReport.score), forKey: "qualityScore")
        object.setValue(qualityReport.confidence.rawValue, forKey: "qualityConfidence")
        object.setValue(encodedQualityReasonCodes(qualityReport.reasonCodes), forKey: "qualityReasonCodes")
        object.setValue(Int64(qualityReport.activeDurationSec), forKey: "activeDurationSec")
        object.setValue(Int64(qualityReport.stationaryTailSec), forKey: "stationaryTailSec")
        object.setValue(qualityReport.gpsAccuracyAvg, forKey: "gpsAccuracyAvg")
        object.setValue(qualityReport.gpsAccuracyP95, forKey: "gpsAccuracyP95")
        object.setValue(Int64(qualityReport.rejectedSegmentCount), forKey: "rejectedSegmentCount")
        object.setValue(Int64(qualityReport.validSegmentCount), forKey: "validSegmentCount")
        object.setValue(qualityReport.maxSampleGapSec, forKey: "maxSampleGapSec")
        object.setValue(qualityReport.p95SampleGapSec, forKey: "p95SampleGapSec")
        object.setValue(qualityReport.coverageRatio, forKey: "coverageRatio")
        object.setValue(Int64(qualityReport.burstCount), forKey: "burstCount")
        object.setValue(qualityReport.motionAgreementRate, forKey: "motionAgreementRate")
        object.setValue(qualityReport.formulaVersion, forKey: "qualityFormulaVersion")
    }

    private static func samples(from routePoints: [TripRoutePoint]) -> [LocationSample] {
        routePoints.map { point in
            LocationSample(
                timestamp: point.timestamp,
                latitude: point.latitude,
                longitude: point.longitude,
                speedKmh: point.speedKmh,
                horizontalAccuracy: point.horizontalAccuracy,
                speedAccuracy: point.speedAccuracy
            )
        }
    }
}

private extension TripRecord {
    func isReliableEnoughForSummary(learningProfile: TripQualityLearningProfile) -> Bool {
        TripQualityReport(
            score: qualityScore,
            confidence: qualityConfidence,
            reasonCodes: qualityReasonCodes,
            activeDurationSec: activeDurationSec,
            stationaryTailSec: stationaryTailSec,
            gpsAccuracyAvg: gpsAccuracyAvg,
            gpsAccuracyP95: gpsAccuracyP95,
            rejectedSegmentCount: rejectedSegmentCount,
            validSegmentCount: validSegmentCount,
            maxSampleGapSec: maxSampleGapSec,
            p95SampleGapSec: p95SampleGapSec,
            coverageRatio: coverageRatio,
            burstCount: burstCount,
            motionAgreementRate: motionAgreementRate,
            formulaVersion: qualityFormulaVersion
        ).isReliableEnoughForSummary(learningProfile: learningProfile)
    }
}

private extension TripQualityReport {
    func isReliableEnoughForSummary(learningProfile: TripQualityLearningProfile) -> Bool {
        switch confidence {
        case .reliable:
            return score >= learningProfile.minimumSummaryQualityScore
        case .partial:
            return score >= learningProfile.minimumSummaryQualityScore
        case .needsReview, .rejected:
            return false
        }
    }
}
