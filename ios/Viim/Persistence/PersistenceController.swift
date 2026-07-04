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
            attribute("polyline", .binaryDataAttributeType, isOptional: true),
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

        model.entities = [trip, tripEvent, dailySummary]
        return model
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        isOptional: Bool = false
    ) -> NSAttributeDescription {
        let description = NSAttributeDescription()
        description.name = name
        description.attributeType = type
        description.isOptional = isOptional
        return description
    }
}
