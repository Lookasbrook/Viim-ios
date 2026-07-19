import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(
            name: "Viim",
            managedObjectModel: Self.makeManagedObjectModel()
        )

        if inMemory {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
        }

        for description in container.persistentStoreDescriptions {
            description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        }

        container.loadPersistentStores { _, error in
            precondition(error == nil, "CoreData store failed to load")
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    private static func makeManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let trip = NSEntityDescription()
        trip.name = "Trip"
        trip.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        trip.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("startDate", .dateAttributeType),
            attribute("endDate", .dateAttributeType),
            attribute("distanceKm", .doubleAttributeType),
            attribute("durationSec", .integer64AttributeType),
            attribute("avgSpeedKmh", .doubleAttributeType),
            attribute("maxSpeedKmh", .doubleAttributeType),
            attribute("score", .integer64AttributeType, isOptional: true),
            attribute("scoreVitesse", .integer64AttributeType, isOptional: true),
            attribute("scoreFluidite", .integer64AttributeType, isOptional: true),
            attribute("scoreVigilance", .integer64AttributeType, isOptional: true),
            attribute("scoreEco", .integer64AttributeType, isOptional: true),
            attribute("fuelLiters", .doubleAttributeType, isOptional: true),
            attribute("fuelFCFA", .integer64AttributeType, isOptional: true),
            attribute("fuelCostMinorUnits", .integer64AttributeType, isOptional: true),
            attribute("fuelCurrencyCode", .stringAttributeType, isOptional: true),
            attribute("fuelPricePerLiter", .doubleAttributeType, isOptional: true),
            attribute("fuelPriceCapturedAt", .dateAttributeType, isOptional: true),
            attribute("fuelPriceSource", .stringAttributeType, isOptional: true),
            attribute("fuelProfileName", .stringAttributeType, isOptional: true),
            attribute("fuelProfileLitersPer100Km", .doubleAttributeType, isOptional: true),
            attribute("fuelProfileSource", .stringAttributeType, isOptional: true),
            attribute("fuelFormulaVersion", .stringAttributeType, defaultValue: "legacy"),
            attribute("polyline", .binaryDataAttributeType, isOptional: true),
            attribute("qualityScore", .integer64AttributeType, defaultValue: Int64(0)),
            attribute("qualityConfidence", .stringAttributeType, defaultValue: TripQualityConfidence.needsReview.rawValue),
            attribute("qualityReasonCodes", .stringAttributeType, defaultValue: TripQualityReasonCode.legacyUnverified.rawValue),
            attribute("activeDurationSec", .integer64AttributeType, defaultValue: Int64(0)),
            attribute("stationaryTailSec", .integer64AttributeType, defaultValue: Int64(0)),
            attribute("gpsAccuracyAvg", .doubleAttributeType, defaultValue: -1.0),
            attribute("gpsAccuracyP95", .doubleAttributeType, defaultValue: -1.0),
            attribute("rejectedSegmentCount", .integer64AttributeType, defaultValue: Int64(0)),
            attribute("validSegmentCount", .integer64AttributeType, defaultValue: Int64(0)),
            attribute("maxSampleGapSec", .doubleAttributeType, defaultValue: 0.0),
            attribute("p95SampleGapSec", .doubleAttributeType, defaultValue: 0.0),
            attribute("coverageRatio", .doubleAttributeType, defaultValue: 0.0),
            attribute("burstCount", .integer64AttributeType, defaultValue: Int64(0)),
            attribute("motionAgreementRate", .doubleAttributeType, isOptional: true),
            attribute("qualityFormulaVersion", .stringAttributeType, defaultValue: TripQualityReport.legacyUnverified.formulaVersion),
            attribute("isCalibration", .booleanAttributeType),
            attribute("vehicleType", .stringAttributeType),
            attribute("role", .stringAttributeType),
            attribute("synced", .booleanAttributeType),
            attribute("createdAt", .dateAttributeType)
        ]

        let tripEvent = NSEntityDescription()
        tripEvent.name = "TripEvent"
        tripEvent.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        tripEvent.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("tripId", .UUIDAttributeType),
            attribute("type", .stringAttributeType),
            attribute("timestamp", .dateAttributeType),
            attribute("latitude", .doubleAttributeType),
            attribute("longitude", .doubleAttributeType),
            attribute("intensity", .doubleAttributeType),
            attribute("gpsConfirmed", .booleanAttributeType),
            attribute("synced", .booleanAttributeType),
            attribute("createdAt", .dateAttributeType)
        ]

        let dailySummary = NSEntityDescription()
        dailySummary.name = "DailySummary"
        dailySummary.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        dailySummary.properties = [
            attribute("date", .dateAttributeType),
            attribute("tripsCount", .integer64AttributeType),
            attribute("totalKm", .doubleAttributeType),
            attribute("totalDurationSec", .integer64AttributeType),
            attribute("avgScore", .integer64AttributeType, isOptional: true),
            attribute("fuelFCFA", .integer64AttributeType, isOptional: true),
            attribute("synced", .booleanAttributeType),
            attribute("createdAt", .dateAttributeType)
        ]

        let tripQualityTelemetry = NSEntityDescription()
        tripQualityTelemetry.name = "TripQualityTelemetry"
        tripQualityTelemetry.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        tripQualityTelemetry.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("tripId", .UUIDAttributeType, isOptional: true),
            attribute("createdAt", .dateAttributeType),
            attribute("decisionSource", .stringAttributeType),
            attribute("vehicleType", .stringAttributeType),
            attribute("qualityScore", .integer64AttributeType),
            attribute("qualityConfidence", .stringAttributeType),
            attribute("qualityReasonCodes", .stringAttributeType),
            attribute("acceptedForStorage", .booleanAttributeType),
            attribute("includedInSummaryAtDecision", .booleanAttributeType),
            attribute("sampleCount", .integer64AttributeType),
            attribute("gpsAccuracyAvg", .doubleAttributeType),
            attribute("gpsAccuracyP95", .doubleAttributeType),
            attribute("rejectedSegmentCount", .integer64AttributeType),
            attribute("validSegmentCount", .integer64AttributeType),
            attribute("maxSampleGapSec", .doubleAttributeType, defaultValue: 0.0),
            attribute("p95SampleGapSec", .doubleAttributeType, defaultValue: 0.0),
            attribute("coverageRatio", .doubleAttributeType, defaultValue: 0.0),
            attribute("burstCount", .integer64AttributeType, defaultValue: Int64(0)),
            attribute("formulaVersion", .stringAttributeType),
            attribute("synced", .booleanAttributeType)
        ]

        let activeTripDraft = NSEntityDescription()
        activeTripDraft.name = "ActiveTripDraft"
        activeTripDraft.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        activeTripDraft.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("startedAt", .dateAttributeType),
            attribute("lastUpdatedAt", .dateAttributeType),
            attribute("lastMovingAt", .dateAttributeType),
            attribute("distanceMeters", .doubleAttributeType),
            attribute("sampleCount", .integer64AttributeType),
            attribute("vehicleType", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("phase", .stringAttributeType, defaultValue: ActiveTripDraftPhase.active.rawValue)
        ]

        let activeTripSample = NSEntityDescription()
        activeTripSample.name = "ActiveTripSample"
        activeTripSample.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        activeTripSample.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("tripId", .UUIDAttributeType),
            attribute("timestamp", .dateAttributeType),
            attribute("latitude", .doubleAttributeType),
            attribute("longitude", .doubleAttributeType),
            attribute("speedKmh", .doubleAttributeType),
            attribute("horizontalAccuracy", .doubleAttributeType),
            attribute("speedAccuracy", .doubleAttributeType),
            attribute("createdAt", .dateAttributeType)
        ]

        let tripCaptureOutcome = NSEntityDescription()
        tripCaptureOutcome.name = "TripCaptureOutcome"
        tripCaptureOutcome.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        tripCaptureOutcome.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("tripId", .UUIDAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("status", .stringAttributeType),
            attribute("reason", .stringAttributeType),
            attribute("source", .stringAttributeType),
            attribute("sampleCount", .integer64AttributeType)
        ]

        model.entities = [
            trip,
            tripEvent,
            dailySummary,
            tripQualityTelemetry,
            activeTripDraft,
            activeTripSample,
            tripCaptureOutcome
        ]
        return model
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        isOptional: Bool = false,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let description = NSAttributeDescription()
        description.name = name
        description.attributeType = type
        description.isOptional = isOptional
        description.defaultValue = defaultValue
        return description
    }
}
