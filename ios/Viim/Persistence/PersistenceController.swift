import CoreData

/// Immutable identifiers for every schema shipped in `Viim.xcdatamodeld`.
/// Core Data uses entity version hashes, while these identifiers keep migration
/// diagnostics and historical fixtures unambiguous.
enum ViimStoreModelVersion: String, CaseIterable {
    case build33 = "Viim.build33"

    static let current = ViimStoreModelVersion.build33
}

enum PersistenceBackupError: LocalizedError {
    case noSQLiteStore
    case sourceStoreMissing(URL)
    case destinationAlreadyExists(URL)
    case backupVerificationMismatch(expected: [String: Int], actual: [String: Int])

    var errorDescription: String? {
        switch self {
        case .noSQLiteStore:
            return "Aucun store SQLite Viim n'est charge."
        case .sourceStoreMissing(let url):
            return "Le store Viim est introuvable : \(url.lastPathComponent)."
        case .destinationAlreadyExists(let url):
            return "La sauvegarde existe deja : \(url.lastPathComponent)."
        case .backupVerificationMismatch(let expected, let actual):
            return "La sauvegarde Core Data est incomplete (attendu \(expected), obtenu \(actual))."
        }
    }
}

enum PersistenceModelError: LocalizedError {
    case bundledModelMissing

    var errorDescription: String? {
        switch self {
        case .bundledModelMissing:
            return "Le modele Core Data versionne Viim est absent du bundle."
        }
    }
}

struct VerifiedPersistenceBackup: Equatable {
    let url: URL
    let rowCountsByEntity: [String: Int]
}

struct RawPersistenceSnapshot: Equatable, Identifiable {
    let id: UUID
    let directoryURL: URL
    let fileURLs: [URL]
}

struct PersistenceRecoveryState: Equatable {
    let storeURL: URL?
    let errorDomain: String
    let errorCode: Int

    var diagnosticSummary: String {
        "domain=\(errorDomain) code=\(errorCode) store=\(storeURL?.lastPathComponent ?? "unknown")"
    }
}

enum PersistenceBootstrapResult {
    case ready(PersistenceController)
    case recoveryRequired(PersistenceRecoveryState)
}

struct PersistenceController {
    let container: NSPersistentContainer

    init(inMemory: Bool = false, storeURL: URL? = nil) {
        do {
            self = try PersistenceController(
                loadingInMemory: inMemory,
                storeURL: storeURL
            )
        } catch {
            let nsError = error as NSError
            preconditionFailure(
                "CoreData store failed to load (\(nsError.domain):\(nsError.code))"
            )
        }
    }

    static func bootstrap(
        storeURL: URL? = nil,
        migrationBackupRootURL: URL? = nil
    ) -> PersistenceBootstrapResult {
        let resolvedStoreURL = storeURL ?? defaultSQLiteStoreURL()
        do {
            if let resolvedStoreURL,
               let snapshot = try createPreMigrationSnapshotIfNeeded(
                   storeURL: resolvedStoreURL,
                   backupRootURL: migrationBackupRootURL ?? defaultMigrationBackupRootURL()
               ) {
                ViimDiagnostics.log(
                    "persistence.migration.backup created=true files=\(snapshot.fileURLs.count)"
                )
            }
            return .ready(
                try PersistenceController(
                    loadingInMemory: false,
                    storeURL: storeURL
                )
            )
        } catch {
            let nsError = error as NSError
            let state = PersistenceRecoveryState(
                storeURL: resolvedStoreURL,
                errorDomain: nsError.domain,
                errorCode: nsError.code
            )
            ViimDiagnostics.log("persistence.load.failed \(state.diagnosticSummary)")
            return .recoveryRequired(state)
        }
    }

    private init(loadingInMemory inMemory: Bool, storeURL: URL?) throws {
        let managedObjectModel = try Self.requireBundledManagedObjectModel()
        container = NSPersistentContainer(
            name: "Viim",
            managedObjectModel: managedObjectModel
        )

        if inMemory {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
        } else if let storeURL {
            container.persistentStoreDescriptions = [Self.sqliteStoreDescription(url: storeURL)]
        }

        for description in container.persistentStoreDescriptions {
            Self.configure(description)
        }

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    private static func defaultSQLiteStoreURL() -> URL? {
        NSPersistentContainer.defaultDirectoryURL()
            .appendingPathComponent("Viim.sqlite")
    }

    private static func defaultMigrationBackupRootURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? NSPersistentContainer.defaultDirectoryURL()
        return applicationSupport.appendingPathComponent("ViimMigrationBackups", isDirectory: true)
    }

    static func createPreMigrationSnapshotIfNeeded(
        storeURL: URL,
        backupRootURL: URL
    ) throws -> RawPersistenceSnapshot? {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return nil
        }

        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: storeURL,
            options: nil
        )
        let currentModel = try requireBundledManagedObjectModel()
        guard !currentModel.isConfiguration(
            withName: nil,
            compatibleWithStoreMetadata: metadata
        ) else {
            return nil
        }

        return try copyStoreFamily(
            storeURL: storeURL,
            destinationRootURL: backupRootURL,
            directoryPrefix: "pre-migration"
        )
    }

    static func createRecoveryExport(
        state: PersistenceRecoveryState,
        destinationRootURL: URL? = nil
    ) throws -> RawPersistenceSnapshot {
        guard let storeURL = state.storeURL else {
            throw PersistenceBackupError.noSQLiteStore
        }
        let rootURL = destinationRootURL
            ?? FileManager.default.temporaryDirectory.appendingPathComponent(
                "ViimRecoveryExports",
                isDirectory: true
            )
        return try copyStoreFamily(
            storeURL: storeURL,
            destinationRootURL: rootURL,
            directoryPrefix: "recovery"
        )
    }

    private static func copyStoreFamily(
        storeURL: URL,
        destinationRootURL: URL,
        directoryPrefix: String
    ) throws -> RawPersistenceSnapshot {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: storeURL.path) else {
            throw PersistenceBackupError.sourceStoreMissing(storeURL)
        }

        try fileManager.createDirectory(
            at: destinationRootURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        let snapshotID = UUID()
        let directoryURL = destinationRootURL.appendingPathComponent(
            "Viim-\(directoryPrefix)-\(snapshotID.uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableDirectoryURL = directoryURL
        try mutableDirectoryURL.setResourceValues(resourceValues)

        let sourceURLs = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-wal"),
            URL(fileURLWithPath: storeURL.path + "-shm")
        ]
        let copiedURLs = try sourceURLs.compactMap { sourceURL -> URL? in
            guard fileManager.fileExists(atPath: sourceURL.path) else { return nil }
            let destinationURL = directoryURL.appendingPathComponent(sourceURL.lastPathComponent)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: destinationURL.path
            )
            return destinationURL
        }

        return RawPersistenceSnapshot(
            id: snapshotID,
            directoryURL: directoryURL,
            fileURLs: copiedURLs
        )
    }

    /// Cree une sauvegarde SQLite coherente, y compris lorsque le store actif
    /// utilise WAL. `replacePersistentStore` est volontairement utilise a la
    /// place d'une copie de fichier, puis la destination est rouverte et
    /// comparee avant d'etre declaree valide.
    func createVerifiedBackup(at destinationURL: URL) throws -> VerifiedPersistenceBackup {
        guard let sourceStore = container.persistentStoreCoordinator.persistentStores.first(where: {
            $0.type == NSSQLiteStoreType
        }), let sourceURL = sourceStore.url else {
            throw PersistenceBackupError.noSQLiteStore
        }
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw PersistenceBackupError.destinationAlreadyExists(destinationURL)
        }

        try container.viewContext.performAndWait {
            if container.viewContext.hasChanges {
                try container.viewContext.save()
            }
        }
        let expectedCounts = try Self.rowCounts(in: container.viewContext)
        try container.persistentStoreCoordinator.replacePersistentStore(
            at: destinationURL,
            destinationOptions: [
                NSPersistentStoreFileProtectionKey:
                    FileProtectionType.completeUntilFirstUserAuthentication
            ],
            withPersistentStoreFrom: sourceURL,
            sourceOptions: sourceStore.options,
            ofType: NSSQLiteStoreType
        )

        let actualCounts = try Self.rowCounts(
            at: destinationURL,
            model: container.managedObjectModel
        )
        guard actualCounts == expectedCounts else {
            throw PersistenceBackupError.backupVerificationMismatch(
                expected: expectedCounts,
                actual: actualCounts
            )
        }
        return VerifiedPersistenceBackup(url: destinationURL, rowCountsByEntity: actualCounts)
    }

    /// Frozen build-33 reference used only by compatibility and migration tests.
    /// Runtime stores are opened with the compiled model from `Viim.xcdatamodeld`.
    static func makeManagedObjectModel(
        version: ViimStoreModelVersion = .current
    ) -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.versionIdentifiers = [version.rawValue]

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
            attribute("fuelLitersLowerBound", .doubleAttributeType, isOptional: true),
            attribute("fuelLitersUpperBound", .doubleAttributeType, isOptional: true),
            attribute("fuelBaselineLiters", .doubleAttributeType, isOptional: true),
            attribute("fuelDynamicsMultiplier", .doubleAttributeType, isOptional: true),
            attribute("fuelDynamicsCoverageRatio", .doubleAttributeType, isOptional: true),
            attribute("fuelElevationMultiplier", .doubleAttributeType, isOptional: true),
            attribute("fuelElevationCoverageRatio", .doubleAttributeType, isOptional: true),
            attribute("fuelUncertaintyRatio", .doubleAttributeType, isOptional: true),
            attribute("fuelReferenceResolution", .stringAttributeType, isOptional: true),
            attribute("fuelFCFA", .integer64AttributeType, isOptional: true),
            attribute("fuelCostMinorUnits", .integer64AttributeType, isOptional: true),
            attribute("fuelCostLowerBoundMinorUnits", .integer64AttributeType, isOptional: true),
            attribute("fuelCostUpperBoundMinorUnits", .integer64AttributeType, isOptional: true),
            attribute("fuelCurrencyCode", .stringAttributeType, isOptional: true),
            attribute("fuelPricePerLiter", .doubleAttributeType, isOptional: true),
            attribute("fuelPriceCapturedAt", .dateAttributeType, isOptional: true),
            attribute("fuelPriceSource", .stringAttributeType, isOptional: true),
            attribute("fuelPriceSourceIdentifier", .stringAttributeType, isOptional: true),
            attribute("fuelPriceSourceURL", .stringAttributeType, isOptional: true),
            attribute("fuelPriceLocality", .stringAttributeType, isOptional: true),
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
            attribute("altitudeMeters", .doubleAttributeType, isOptional: true),
            attribute("verticalAccuracy", .doubleAttributeType, defaultValue: -1.0),
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

    static func bundledManagedObjectModel(bundle: Bundle = .main) -> NSManagedObjectModel? {
        guard let modelURL = bundle.url(forResource: "Viim", withExtension: "momd") else {
            return nil
        }
        return NSManagedObjectModel(contentsOf: modelURL)
    }

    private static func requireBundledManagedObjectModel(
        bundle: Bundle = .main
    ) throws -> NSManagedObjectModel {
        guard let model = bundledManagedObjectModel(bundle: bundle) else {
            throw PersistenceModelError.bundledModelMissing
        }
        return model
    }

    /// Hashes of the frozen reference model, pinned against the bundled model.
    static func schemaHashes(
        version: ViimStoreModelVersion = .current
    ) -> [String: String] {
        makeManagedObjectModel(version: version).entityVersionHashesByName
            .mapValues { $0.base64EncodedString() }
    }

    static func sqliteStoreDescription(url: URL) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        configure(description)
        return description
    }

    static func rowCounts(
        at storeURL: URL,
        model: NSManagedObjectModel = makeManagedObjectModel()
    ) throws -> [String: Int] {
        let validationContainer = NSPersistentContainer(
            name: "ViimBackupValidation",
            managedObjectModel: model
        )
        let description = sqliteStoreDescription(url: storeURL)
        description.setOption(true as NSNumber, forKey: NSReadOnlyPersistentStoreOption)
        description.shouldMigrateStoreAutomatically = false
        description.shouldInferMappingModelAutomatically = false
        validationContainer.persistentStoreDescriptions = [description]

        var loadError: Error?
        validationContainer.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }
        defer {
            validationContainer.persistentStoreCoordinator.persistentStores.forEach {
                try? validationContainer.persistentStoreCoordinator.remove($0)
            }
        }
        return try rowCounts(in: validationContainer.viewContext)
    }

    private static func configure(_ description: NSPersistentStoreDescription) {
        description.setOption(
            true as NSNumber,
            forKey: NSMigratePersistentStoresAutomaticallyOption
        )
        description.setOption(
            true as NSNumber,
            forKey: NSInferMappingModelAutomaticallyOption
        )
        guard description.type == NSSQLiteStoreType else {
            return
        }
        description.shouldAddStoreAsynchronously = false
        // La collecte doit rester possible ecran verrouille apres le premier
        // deverrouillage, sans rendre le store accessible avant celui-ci.
        description.setOption(
            FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
            forKey: NSPersistentStoreFileProtectionKey
        )
    }

    private static func rowCounts(
        in context: NSManagedObjectContext
    ) throws -> [String: Int] {
        try context.performAndWait {
            var counts: [String: Int] = [:]
            for name in context.persistentStoreCoordinator?.managedObjectModel.entities.compactMap(\.name) ?? [] {
                counts[name] = try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: name))
            }
            return counts
        }
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
