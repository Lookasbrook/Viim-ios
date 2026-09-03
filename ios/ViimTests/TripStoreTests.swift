import CoreLocation
import CoreData
import XCTest
@testable import Viim

final class TripStoreTests: XCTestCase {
    func testRecoveryExportCopiesSQLiteWALAndSHMWithoutChangingSources() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Viim-recovery-export-\(UUID().uuidString)", isDirectory: true)
        let exportRoot = directory.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Viim.sqlite")
        let sourceBytes: [String: Data] = [
            "Viim.sqlite": Data("sqlite-source".utf8),
            "Viim.sqlite-wal": Data("wal-source".utf8),
            "Viim.sqlite-shm": Data("shm-source".utf8)
        ]
        for (name, data) in sourceBytes {
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        }
        let state = PersistenceRecoveryState(
            storeURL: storeURL,
            errorDomain: NSCocoaErrorDomain,
            errorCode: 1
        )

        let snapshot = try PersistenceController.createRecoveryExport(
            state: state,
            destinationRootURL: exportRoot
        )

        XCTAssertEqual(Set(snapshot.fileURLs.map(\.lastPathComponent)), Set(sourceBytes.keys))
        for (name, expectedData) in sourceBytes {
            XCTAssertEqual(
                try Data(contentsOf: snapshot.directoryURL.appendingPathComponent(name)),
                expectedData
            )
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(name)), expectedData)
        }
    }

    func testBootstrapCreatesRawBackupBeforeLightweightMigration() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Viim-pre-migration-\(UUID().uuidString)", isDirectory: true)
        let backupRoot = directory.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Viim.sqlite")

        let legacyModel = PersistenceController.makeManagedObjectModel()
        legacyModel.versionIdentifiers = ["Viim.testLegacy"]
        let legacyTrip = try XCTUnwrap(legacyModel.entitiesByName["Trip"])
        legacyTrip.properties = legacyTrip.properties.filter { $0.name != "fuelUncertaintyRatio" }
        let legacyContainer = NSPersistentContainer(name: "Viim", managedObjectModel: legacyModel)
        let description = NSPersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        legacyContainer.persistentStoreDescriptions = [description]
        var loadError: Error?
        legacyContainer.loadPersistentStores { _, error in loadError = error }
        XCTAssertNil(loadError)
        for store in legacyContainer.persistentStoreCoordinator.persistentStores {
            try legacyContainer.persistentStoreCoordinator.remove(store)
        }
        let originalStoreBytes = try Data(contentsOf: storeURL)

        let result = PersistenceController.bootstrap(
            storeURL: storeURL,
            migrationBackupRootURL: backupRoot
        )

        guard case .ready = result else {
            return XCTFail("La migration legere doit reussir apres la sauvegarde")
        }
        let snapshotDirectories = try FileManager.default.contentsOfDirectory(
            at: backupRoot,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(snapshotDirectories.count, 1)
        let copiedStoreURL = try XCTUnwrap(snapshotDirectories.first)
            .appendingPathComponent("Viim.sqlite")
        XCTAssertEqual(try Data(contentsOf: copiedStoreURL), originalStoreBytes)
    }

    func testCompatibleStoreDoesNotCreateMigrationBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Viim-compatible-\(UUID().uuidString)", isDirectory: true)
        let backupRoot = directory.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Viim.sqlite")
        let legacyProgrammaticContainer = NSPersistentContainer(
            name: "Viim",
            managedObjectModel: PersistenceController.makeManagedObjectModel()
        )
        let description = NSPersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        legacyProgrammaticContainer.persistentStoreDescriptions = [description]
        var loadError: Error?
        legacyProgrammaticContainer.loadPersistentStores { _, error in loadError = error }
        XCTAssertNil(loadError)
        for store in legacyProgrammaticContainer.persistentStoreCoordinator.persistentStores {
            try legacyProgrammaticContainer.persistentStoreCoordinator.remove(store)
        }

        let snapshot = try PersistenceController.createPreMigrationSnapshotIfNeeded(
            storeURL: storeURL,
            backupRootURL: backupRoot
        )

        XCTAssertNil(snapshot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupRoot.path))
    }

    func testBootstrapDoesNotMigrateWhenPreMigrationBackupCannotBeCreated() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Viim-blocked-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Viim.sqlite")
        let blockedBackupRoot = directory.appendingPathComponent("not-a-directory")

        let legacyModel = PersistenceController.makeManagedObjectModel()
        legacyModel.versionIdentifiers = ["Viim.testBlockedMigration"]
        let legacyTrip = try XCTUnwrap(legacyModel.entitiesByName["Trip"])
        legacyTrip.properties = legacyTrip.properties.filter { $0.name != "fuelUncertaintyRatio" }
        let legacyContainer = NSPersistentContainer(name: "Viim", managedObjectModel: legacyModel)
        let description = NSPersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        legacyContainer.persistentStoreDescriptions = [description]
        var loadError: Error?
        legacyContainer.loadPersistentStores { _, error in loadError = error }
        XCTAssertNil(loadError)
        for store in legacyContainer.persistentStoreCoordinator.persistentStores {
            try legacyContainer.persistentStoreCoordinator.remove(store)
        }
        let originalStoreBytes = try Data(contentsOf: storeURL)
        try Data("backup-root-is-a-file".utf8).write(to: blockedBackupRoot, options: .atomic)

        let result = PersistenceController.bootstrap(
            storeURL: storeURL,
            migrationBackupRootURL: blockedBackupRoot
        )

        guard case .recoveryRequired = result else {
            return XCTFail("La migration doit etre bloquee si la sauvegarde prealable echoue")
        }
        XCTAssertEqual(try Data(contentsOf: storeURL), originalStoreBytes)
    }

    func testBootstrapUsesRecoveryModeWithoutChangingCorruptedStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Viim-corrupt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Viim.sqlite")
        let originalBytes = Data("not-a-sqlite-store".utf8)
        try originalBytes.write(to: storeURL, options: .atomic)

        let result = PersistenceController.bootstrap(storeURL: storeURL)

        guard case .recoveryRequired(let state) = result else {
            return XCTFail("Un store corrompu ne doit jamais etre remplace silencieusement")
        }
        XCTAssertEqual(state.storeURL, storeURL)
        XCTAssertFalse(state.errorDomain.isEmpty)
        XCTAssertNotEqual(state.errorCode, 0)
        XCTAssertEqual(try Data(contentsOf: storeURL), originalBytes)
    }

    func testBootstrapOpensAValidStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Viim-valid-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Viim.sqlite")

        let result = PersistenceController.bootstrap(storeURL: storeURL)

        guard case .ready(let controller) = result else {
            return XCTFail("Un store valide doit etre disponible")
        }
        XCTAssertEqual(controller.container.persistentStoreCoordinator.persistentStores.count, 1)
    }

    func testCurrentPersistentSchemaContractIsPinned() {
        let model = PersistenceController.makeManagedObjectModel()

        XCTAssertEqual(
            model.versionIdentifiers,
            [ViimStoreModelVersion.current.rawValue]
        )
        XCTAssertEqual(
            PersistenceController.schemaHashes(),
            [
                "ActiveTripDraft": "4jf89C+KBuE39+UqWxNBpK6WPEv+3Y9pODS0DLeqHQk=",
                "ActiveTripSample": "AFLB97Fd8gePYDIlGzD1OJGP+9VzuHeCsDy9LPVrD14=",
                "DailySummary": "v/1GqNAqKZVeZ5jhUC7LKfMIASI2IsrkSIADn71C3l4=",
                "FuelFillUp": "vMS9N2zNLubsceQ3m7xa5mD5WZpNwDukCCK375jD8fA=",
                "Trip": "Ua2G5omlAlix7Bq1iw5EQV6cXyEubG+h45j83PyGW0A=",
                "TripCaptureOutcome": "KUaAcCoZEiwc76Hm03ZuBtsnnlR8/zzkAjDWlQSa2Do=",
                "TripEvent": "qWwt7sJI3onRYopoFtBkPA3E95uW+uwtFylzUixoHk4=",
                "TripQualityTelemetry": "Bv4RWTEY/HGLL9UVlJ9wje/1s4ljHSwXJMgFUCH1oW8="
            ]
        )
    }

    func testBundledVersionedModelExactlyMatchesCurrentProgrammaticSchema() throws {
        let bundledModel = try XCTUnwrap(PersistenceController.bundledManagedObjectModel())
        let currentModel = PersistenceController.makeManagedObjectModel()

        XCTAssertEqual(bundledModel.versionIdentifiers, currentModel.versionIdentifiers)
        XCTAssertEqual(bundledModel.entityVersionHashesByName, currentModel.entityVersionHashesByName)
        XCTAssertEqual(Set(bundledModel.entitiesByName.keys), Set(currentModel.entitiesByName.keys))
        for (entityName, currentEntity) in currentModel.entitiesByName {
            let bundledEntity = try XCTUnwrap(bundledModel.entitiesByName[entityName])
            XCTAssertEqual(
                Set(bundledEntity.attributesByName.keys),
                Set(currentEntity.attributesByName.keys),
                entityName
            )
            for (attributeName, currentAttribute) in currentEntity.attributesByName {
                let bundledAttribute = try XCTUnwrap(bundledEntity.attributesByName[attributeName])
                XCTAssertEqual(bundledAttribute.attributeType, currentAttribute.attributeType, attributeName)
                XCTAssertEqual(bundledAttribute.isOptional, currentAttribute.isOptional, attributeName)
                XCTAssertEqual(
                    String(describing: bundledAttribute.defaultValue),
                    String(describing: currentAttribute.defaultValue),
                    "\(entityName).\(attributeName)"
                )
            }
        }
    }

    func testSQLiteDescriptionUsesBackgroundCompatibleFileProtection() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Viim-protection-\(UUID().uuidString).sqlite")
        let description = PersistenceController.sqliteStoreDescription(url: url)

        XCTAssertEqual(description.type, NSSQLiteStoreType)
        XCTAssertFalse(description.shouldAddStoreAsynchronously)
        XCTAssertEqual(
            description.options[NSPersistentStoreFileProtectionKey] as? FileProtectionType,
            .completeUntilFirstUserAuthentication
        )
    }

    func testCompletedTripPersistsGPSReceiptTimeline() throws {
        let store = makeStore()
        let trip = completedTrip(index: 0)
        let receiptStart = trip.startedAt.addingTimeInterval(600)
        let routeSamples = samples(start: trip.startedAt).enumerated().map { index, sample in
            LocationSample(
                timestamp: sample.timestamp,
                latitude: sample.latitude,
                longitude: sample.longitude,
                speedKmh: sample.speedKmh,
                horizontalAccuracy: sample.horizontalAccuracy,
                speedAccuracy: sample.speedAccuracy,
                altitudeMeters: sample.altitudeMeters,
                verticalAccuracy: sample.verticalAccuracy,
                receivedAt: receiptStart.addingTimeInterval(Double(index) * 180)
            )
        }

        try store.insertCompletedTrip(
            trip,
            samples: routeSamples,
            vehicleType: .voiture,
            isCalibration: false
        )

        let stored = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)
        XCTAssertEqual(stored.routePoints.map(\.receivedAt), routeSamples.map(\.receivedAt))
    }

    func testLegacyPolylineWithoutReceiptTimelineFallsBackToGPSTimestamp() throws {
        let timestamp = Date(timeIntervalSinceReferenceDate: 123_456)
        let data = try JSONSerialization.data(withJSONObject: [[
            "timestamp": timestamp.timeIntervalSinceReferenceDate,
            "latitude": 45.5019,
            "longitude": -73.5674,
            "speedKmh": 32.0,
            "horizontalAccuracy": 8.0
        ]])

        let point = try XCTUnwrap(JSONDecoder().decode([TripRoutePoint].self, from: data).first)
        XCTAssertEqual(point.receivedAt, point.timestamp)
    }

    func testCoreDataBackupIsReopenedAndVerifiedWithEveryEntity() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Viim-backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Viim.sqlite")
        let backupURL = directory.appendingPathComponent("Viim.verified-backup.sqlite")
        let controller = PersistenceController(storeURL: storeURL)
        let context = controller.container.viewContext
        let tripEntity = try XCTUnwrap(NSEntityDescription.entity(forEntityName: "Trip", in: context))
        let trip = NSManagedObject(entity: tripEntity, insertInto: context)
        for attribute in tripEntity.attributesByName.values
            where !attribute.isOptional && attribute.defaultValue == nil {
            trip.setValue(legacyValue(for: attribute), forKey: attribute.name)
        }
        trip.setValue(UUID(), forKey: "id")
        trip.setValue(Date(timeIntervalSince1970: 1_788_000_000), forKey: "startDate")
        trip.setValue(Date(timeIntervalSince1970: 1_788_000_600), forKey: "endDate")
        trip.setValue(VehicleType.voiture.rawValue, forKey: "vehicleType")

        let backup = try controller.createVerifiedBackup(at: backupURL)

        XCTAssertEqual(backup.url, backupURL)
        XCTAssertEqual(backup.rowCountsByEntity["Trip"], 1)
        XCTAssertEqual(backup.rowCountsByEntity.count, 8)
        XCTAssertEqual(try PersistenceController.rowCounts(at: backupURL), backup.rowCountsByEntity)
    }

    func testFuelEvidenceFieldsLightweightMigrateALegacySQLiteStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViimFuelMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Viim.sqlite")

        let legacyModel = PersistenceController.makeManagedObjectModel()
        let newFuelEvidenceFields: Set<String> = [
            "fuelLitersLowerBound",
            "fuelLitersUpperBound",
            "fuelDynamicsCoverageRatio",
            "fuelElevationMultiplier",
            "fuelElevationCoverageRatio",
            "fuelUncertaintyRatio",
            "fuelReferenceResolution",
            "fuelCostLowerBoundMinorUnits",
            "fuelCostUpperBoundMinorUnits"
        ]
        let legacyTripEntity = try XCTUnwrap(legacyModel.entitiesByName["Trip"])
        legacyTripEntity.properties = legacyTripEntity.properties.filter {
            !newFuelEvidenceFields.contains($0.name)
        }

        let legacyContainer = NSPersistentContainer(name: "Viim", managedObjectModel: legacyModel)
        let legacyDescription = NSPersistentStoreDescription(url: storeURL)
        legacyDescription.type = NSSQLiteStoreType
        legacyDescription.shouldAddStoreAsynchronously = false
        legacyContainer.persistentStoreDescriptions = [legacyDescription]
        var legacyLoadError: Error?
        legacyContainer.loadPersistentStores { _, error in legacyLoadError = error }
        XCTAssertNil(legacyLoadError)

        let object = NSManagedObject(entity: legacyTripEntity, insertInto: legacyContainer.viewContext)
        for attribute in legacyTripEntity.attributesByName.values
            where !attribute.isOptional && attribute.defaultValue == nil {
            object.setValue(legacyValue(for: attribute), forKey: attribute.name)
        }
        object.setValue(UUID(), forKey: "id")
        object.setValue(Date(timeIntervalSince1970: 1_783_000_000), forKey: "startDate")
        object.setValue(Date(timeIntervalSince1970: 1_783_000_600), forKey: "endDate")
        object.setValue(VehicleType.voiture.rawValue, forKey: "vehicleType")
        try legacyContainer.viewContext.save()
        let legacyStore = try XCTUnwrap(legacyContainer.persistentStoreCoordinator.persistentStores.first)
        try legacyContainer.persistentStoreCoordinator.remove(legacyStore)

        let migrated = PersistenceController(storeURL: storeURL)
        let request = NSFetchRequest<NSManagedObject>(entityName: "Trip")
        let migratedTrips = try migrated.container.viewContext.fetch(request)

        XCTAssertEqual(migratedTrips.count, 1)
        XCTAssertNil(migratedTrips[0].value(forKey: "fuelLitersLowerBound"))
        XCTAssertNil(migratedTrips[0].value(forKey: "fuelReferenceResolution"))
    }

    func testVersionedBuild33StoreMigratesToCurrentWithoutLosingTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViimBuild33To41-\(UUID().uuidString)", isDirectory: true)
        let backupRoot = directory.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Viim.sqlite")
        let build33Model = PersistenceController.makeManagedObjectModel(version: .build33)
        let legacyContainer = NSPersistentContainer(name: "Viim", managedObjectModel: build33Model)
        let description = NSPersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        legacyContainer.persistentStoreDescriptions = [description]
        var loadError: Error?
        legacyContainer.loadPersistentStores { _, error in loadError = error }
        XCTAssertNil(loadError)

        let tripEntity = try XCTUnwrap(build33Model.entitiesByName["Trip"])
        let trip = NSManagedObject(entity: tripEntity, insertInto: legacyContainer.viewContext)
        for attribute in tripEntity.attributesByName.values
            where !attribute.isOptional && attribute.defaultValue == nil {
            trip.setValue(legacyValue(for: attribute), forKey: attribute.name)
        }
        let tripID = UUID()
        trip.setValue(tripID, forKey: "id")
        trip.setValue(Date(timeIntervalSince1970: 1_788_000_000), forKey: "startDate")
        trip.setValue(Date(timeIntervalSince1970: 1_788_000_600), forKey: "endDate")
        trip.setValue(VehicleType.voiture.rawValue, forKey: "vehicleType")
        try legacyContainer.viewContext.save()
        for store in legacyContainer.persistentStoreCoordinator.persistentStores {
            try legacyContainer.persistentStoreCoordinator.remove(store)
        }

        let result = PersistenceController.bootstrap(
            storeURL: storeURL,
            migrationBackupRootURL: backupRoot
        )
        guard case .ready(let migrated) = result else {
            return XCTFail("Le store Build33 doit migrer vers le modele courant")
        }
        let trips = try migrated.container.viewContext.fetch(
            NSFetchRequest<NSManagedObject>(entityName: "Trip")
        )
        XCTAssertEqual(trips.compactMap { $0.value(forKey: "id") as? UUID }, [tripID])
        XCTAssertNotNil(
            NSEntityDescription.entity(
                forEntityName: "FuelFillUp",
                in: migrated.container.viewContext
            )
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: nil).count,
            1
        )
    }

    func testVersionedBuild41StoreMigratesToBuild49WithoutInventingGeography() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViimBuild41To49-\(UUID().uuidString)", isDirectory: true)
        let backupRoot = directory.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Viim.sqlite")
        let build41Model = PersistenceController.makeManagedObjectModel(version: .build41)
        let legacyContainer = NSPersistentContainer(name: "Viim", managedObjectModel: build41Model)
        let description = NSPersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        legacyContainer.persistentStoreDescriptions = [description]
        var loadError: Error?
        legacyContainer.loadPersistentStores { _, error in loadError = error }
        XCTAssertNil(loadError)

        let tripEntity = try XCTUnwrap(build41Model.entitiesByName["Trip"])
        let trip = NSManagedObject(entity: tripEntity, insertInto: legacyContainer.viewContext)
        for attribute in tripEntity.attributesByName.values
            where !attribute.isOptional && attribute.defaultValue == nil {
            trip.setValue(legacyValue(for: attribute), forKey: attribute.name)
        }
        let tripID = UUID()
        trip.setValue(tripID, forKey: "id")
        trip.setValue(Date(timeIntervalSince1970: 1_788_100_000), forKey: "startDate")
        trip.setValue(Date(timeIntervalSince1970: 1_788_100_600), forKey: "endDate")
        trip.setValue(VehicleType.voiture.rawValue, forKey: "vehicleType")
        try legacyContainer.viewContext.save()
        for store in legacyContainer.persistentStoreCoordinator.persistentStores {
            try legacyContainer.persistentStoreCoordinator.remove(store)
        }

        let result = PersistenceController.bootstrap(
            storeURL: storeURL,
            migrationBackupRootURL: backupRoot
        )
        guard case .ready(let migrated) = result else {
            return XCTFail("Le store Build41 doit migrer vers Build49")
        }
        let trips = try migrated.container.viewContext.fetch(
            NSFetchRequest<NSManagedObject>(entityName: "Trip")
        )
        let migratedTrip = try XCTUnwrap(trips.first)
        XCTAssertEqual(migratedTrip.value(forKey: "id") as? UUID, tripID)
        XCTAssertNil(migratedTrip.value(forKey: "fuelPriceCountryCode"))
        XCTAssertNil(migratedTrip.value(forKey: "fuelPriceGeographyMatchVersion"))
        XCTAssertNil(migratedTrip.value(forKey: "fuelPriceLocationResolvedAt"))
        XCTAssertNil(migratedTrip.value(forKey: "fuelProfileFuelType"))
        XCTAssertNil(migratedTrip.value(forKey: "fuelTripStartLocality"))
        XCTAssertNil(migratedTrip.value(forKey: "fuelTripEndLocality"))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: backupRoot,
                includingPropertiesForKeys: nil
            ).count,
            1
        )
    }

    func testCompletedTripIsStoredOfflineAndIncludedInSummary() throws {
        let store = makeStore()
        let trip = completedTrip(index: 0)
        let routeSamples = samples(start: trip.startedAt)
        let expectedDistanceMeters = try XCTUnwrap(
            TripMetricsCalculator.distanceMetric(
                samples: routeSamples,
                vehicleType: .moto
            ).value
        )

        try store.insertCompletedTrip(
            trip,
            samples: routeSamples,
            vehicleType: .moto,
            isCalibration: false
        )

        let summary = try store.fetchSummary()
        let recentTrip = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)

        XCTAssertEqual(summary.tripsCount, 1)
        XCTAssertEqual(summary.pendingSyncCount, 1)
        XCTAssertEqual(summary.totalKm, expectedDistanceMeters / 1_000, accuracy: 0.001)
        XCTAssertEqual(summary.totalDurationSec, 600)
        XCTAssertNil(summary.avgScore)
        XCTAssertNil(summary.fuelLiters)
        XCTAssertNil(summary.fuelFCFA)
        XCTAssertFalse(recentTrip.isCalibration)
        XCTAssertFalse(recentTrip.synced)
        XCTAssertEqual(recentTrip.vehicleType, .moto)
        XCTAssertEqual(recentTrip.routePoints.count, 5)
        XCTAssertEqual(recentTrip.qualityConfidence, .reliable)
        XCTAssertEqual(recentTrip.qualityReasonCodes, [.complete])
        XCTAssertEqual(recentTrip.qualityFormulaVersion, TripQualityEngine.formulaVersion)
        XCTAssertEqual(recentTrip.validSegmentCount, 4)
        XCTAssertEqual(recentTrip.rejectedSegmentCount, 0)
        XCTAssertNil(recentTrip.fuelFCFA)

        let qualityEvent = try XCTUnwrap(store.fetchQualityTelemetryEvents(limit: 1).first)
        XCTAssertEqual(qualityEvent.tripId, trip.id)
        XCTAssertEqual(qualityEvent.decisionSource, .liveAccepted)
        XCTAssertEqual(qualityEvent.vehicleType, .moto)
        XCTAssertEqual(qualityEvent.qualityConfidence, .reliable)
        XCTAssertEqual(qualityEvent.qualityReasonCodes, [.complete])
        XCTAssertTrue(qualityEvent.acceptedForStorage)
        XCTAssertTrue(qualityEvent.includedInSummaryAtDecision)
        XCTAssertEqual(qualityEvent.sampleCount, 5)
    }

    func testStoredScoreIsIncludedInSummary() throws {
        let store = makeStore()
        let trip = completedTrip(index: 0)
        let scores = TripScores(
            score: 82,
            scoreVitesse: 82,
            scoreFluidite: nil,
            scoreVigilance: nil,
            scoreEco: nil
        )
        try store.insertCompletedTrip(
            trip,
            samples: samples(start: trip.startedAt),
            vehicleType: .voiture,
            isCalibration: false,
            scores: scores
        )

        let summary = try store.fetchSummary()
        let recentTrip = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)

        XCTAssertEqual(summary.avgScore, 82)
        XCTAssertEqual(summary.avgScoreVitesse, 82)
        XCTAssertEqual(recentTrip.score, 82)
        XCTAssertEqual(recentTrip.scoreVitesse, 82)
    }

    func testStoredDistanceUsesFilteredGpsSegmentsInsteadOfReportedAccumulator() throws {
        let store = makeStore()
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let trip = CompletedDetectedTrip(
            id: UUID(),
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            distanceMeters: 9_999,
            sampleCount: 5
        )
        let routeSamples = samples(start: start)
        let expectedDistanceMeters = try XCTUnwrap(
            TripMetricsCalculator.distanceMetric(
                samples: routeSamples,
                vehicleType: .moto
            ).value
        )

        try store.insertCompletedTrip(
            trip,
            samples: routeSamples,
            vehicleType: .moto,
            isCalibration: false
        )

        let summary = try store.fetchSummary()
        let recentTrip = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)

        XCTAssertEqual(recentTrip.distanceKm, expectedDistanceMeters / 1_000, accuracy: 0.001)
        XCTAssertEqual(summary.totalKm, expectedDistanceMeters / 1_000, accuracy: 0.001)
        XCTAssertNotEqual(recentTrip.distanceKm, trip.distanceMeters / 1_000)
    }

    func testRejectedUnreliableTripDoesNotLeavePartialCoreDataObject() throws {
        let store = makeStore()
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let trip = CompletedDetectedTrip(
            id: UUID(),
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            distanceMeters: 12_000,
            sampleCount: 2
        )

        XCTAssertThrowsError(
            try store.insertCompletedTrip(
                trip,
                samples: impossibleJumpSamples(start: start),
                vehicleType: .moto,
                isCalibration: false
            )
        )
        XCTAssertEqual(try store.completedTripsCount(), 0)

        let qualityEvent = try XCTUnwrap(store.fetchQualityTelemetryEvents(limit: 1).first)
        XCTAssertEqual(qualityEvent.tripId, trip.id)
        XCTAssertEqual(qualityEvent.decisionSource, .liveRejected)
        XCTAssertEqual(qualityEvent.qualityConfidence, .rejected)
        XCTAssertTrue(qualityEvent.qualityReasonCodes.contains(.gpsInsufficient))
        XCTAssertFalse(qualityEvent.acceptedForStorage)
    }

    func testRecognizedVehicleStoresNavigationBasedFuelConsumption() throws {
        let store = makeStore()
        let trip = completedTrip(index: 0)
        let fuelProfile = try XCTUnwrap(
            VehicleFuelCatalog.profile(vehicleType: .voiture, brand: "Toyota", model: "Corolla")
        )
        let routeSamples = samples(start: trip.startedAt)
        let expectedDistanceMeters = try XCTUnwrap(
            TripMetricsCalculator.distanceMetric(
                samples: routeSamples,
                vehicleType: .voiture
            ).value
        )
        let scores = TripScores(
            score: 95,
            scoreVitesse: 95,
            scoreFluidite: nil,
            scoreVigilance: nil,
            scoreEco: nil
        )
        let fuelSettings = FuelSettings(
            currency: .cad,
            pricePerLiter: 1.70,
            capturedAt: trip.endedAt
        )

        try store.insertCompletedTrip(
            trip,
            samples: routeSamples,
            vehicleType: .voiture,
            isCalibration: false,
            scores: scores,
            fuelProfile: fuelProfile,
            fuelSettings: fuelSettings
        )

        let summary = try store.fetchSummary()
        let recentTrip = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)
        let fuelMetric = TripMetricsCalculator.fuelCostMetric(for: recentTrip)
        let expectedFuelConsumption = try XCTUnwrap(
            VehicleFuelCatalog.estimateConsumption(
                distanceKm: expectedDistanceMeters / 1_000,
                fuelProfile: fuelProfile,
                dynamics: DrivingDynamicsAnalyzer.dynamics(
                    samples: routeSamples,
                    vehicleType: .voiture,
                    distanceKm: expectedDistanceMeters / 1_000
                ),
                tripDurationSec: trip.duration
            )
        )

        XCTAssertEqual(recentTrip.distanceKm, expectedDistanceMeters / 1_000, accuracy: 0.000_001)
        XCTAssertEqual(recentTrip.fuelLiters ?? -1, expectedFuelConsumption.liters, accuracy: 0.000_001)
        XCTAssertEqual(recentTrip.fuelBaselineLiters ?? -1, expectedFuelConsumption.baselineLiters, accuracy: 0.000_001)
        XCTAssertEqual(recentTrip.fuelDynamicsMultiplier ?? -1, expectedFuelConsumption.dynamicsMultiplier, accuracy: 0.000_001)
        XCTAssertEqual(recentTrip.fuelLitersLowerBound ?? -1, expectedFuelConsumption.lowerBoundLiters, accuracy: 0.000_001)
        XCTAssertEqual(recentTrip.fuelLitersUpperBound ?? -1, expectedFuelConsumption.upperBoundLiters, accuracy: 0.000_001)
        XCTAssertNil(recentTrip.fuelDynamicsCoverageRatio)
        XCTAssertNil(expectedFuelConsumption.dynamicsCoverageRatio)
        XCTAssertEqual(recentTrip.fuelElevationMultiplier ?? -1, expectedFuelConsumption.elevationMultiplier, accuracy: 0.000_001)
        XCTAssertNil(recentTrip.fuelElevationCoverageRatio)
        XCTAssertNil(expectedFuelConsumption.elevationCoverageRatio)
        XCTAssertEqual(recentTrip.fuelReferenceResolution, .indicativeModel)
        XCTAssertEqual(summary.fuelLiters ?? -1, expectedFuelConsumption.liters, accuracy: 0.000_001)
        XCTAssertEqual(summary.fuelLitersLowerBound ?? -1, expectedFuelConsumption.lowerBoundLiters, accuracy: 0.000_001)
        XCTAssertEqual(summary.fuelLitersUpperBound ?? -1, expectedFuelConsumption.upperBoundLiters, accuracy: 0.000_001)
        XCTAssertNil(recentTrip.fuelFCFA)
        XCTAssertNil(summary.fuelFCFA)
        XCTAssertEqual(fuelMetric.value, fuelSettings.costMinorUnits(for: expectedFuelConsumption.liters))
        XCTAssertEqual(recentTrip.fuelCostMinorUnits, fuelMetric.value)
        XCTAssertEqual(
            recentTrip.fuelCostLowerBoundMinorUnits,
            fuelSettings.costMinorUnits(for: expectedFuelConsumption.lowerBoundLiters)
        )
        XCTAssertEqual(
            recentTrip.fuelCostUpperBoundMinorUnits,
            fuelSettings.costMinorUnits(for: expectedFuelConsumption.upperBoundLiters)
        )
        XCTAssertEqual(recentTrip.fuelCurrency, .cad)
        XCTAssertEqual(recentTrip.fuelPricePerLiter, 1.70)
        XCTAssertEqual(recentTrip.fuelPriceSource, .userProvided)
        XCTAssertEqual(recentTrip.fuelProfileName, "Toyota Corolla")
        XCTAssertEqual(recentTrip.fuelProfileLitersPer100Km, 6.8)
        XCTAssertEqual(recentTrip.fuelProfileSource, VehicleFuelCatalog.sourceIdentifier)
        XCTAssertEqual(summary.fuelCostMinorUnits, fuelMetric.value)
        XCTAssertEqual(summary.fuelCostLowerBoundMinorUnits, recentTrip.fuelCostLowerBoundMinorUnits)
        XCTAssertEqual(summary.fuelCostUpperBoundMinorUnits, recentTrip.fuelCostUpperBoundMinorUnits)
        XCTAssertEqual(summary.fuelCurrency, .cad)
        XCTAssertEqual(fuelMetric.confidence, .partial)
        XCTAssertEqual(fuelMetric.reasonCode, .fuelEstimated)
        XCTAssertEqual(fuelMetric.evidence.nature, .estimated)
        XCTAssertEqual(fuelMetric.evidence.validationStatus, .algorithmValidated)
        XCTAssertEqual(fuelMetric.evidence.coverageBasis, .duration)
        XCTAssertEqual(fuelMetric.evidence.sampleCount, recentTrip.routePoints.count)

        let changedCurrentSettings = FuelSettings(currency: .xof, pricePerLiter: 2_000)
        XCTAssertNotEqual(
            changedCurrentSettings.costMinorUnits(for: recentTrip.fuelLiters),
            recentTrip.fuelCostMinorUnits
        )
        XCTAssertEqual(TripMetricsCalculator.fuelCostMetric(for: recentTrip).value, recentTrip.fuelCostMinorUnits)
    }

    func testValidElevationEvidenceIsAppliedAndPersisted() throws {
        let store = makeStore()
        let trip = completedTrip(index: 0)
        let fuelProfile = try XCTUnwrap(
            VehicleFuelCatalog.profile(vehicleType: .voiture, brand: "Toyota", model: "Corolla")
        )
        let routeSamples = samples(start: trip.startedAt).enumerated().map { index, sample in
            LocationSample(
                timestamp: sample.timestamp,
                latitude: sample.latitude,
                longitude: sample.longitude,
                speedKmh: sample.speedKmh,
                horizontalAccuracy: sample.horizontalAccuracy,
                speedAccuracy: sample.speedAccuracy,
                altitudeMeters: 300 + Double(index * 20),
                verticalAccuracy: 5,
                receivedAt: sample.receivedAt
            )
        }

        try store.insertCompletedTrip(
            trip,
            samples: routeSamples,
            vehicleType: .voiture,
            isCalibration: false,
            fuelProfile: fuelProfile
        )

        let saved = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)
        XCTAssertGreaterThan(saved.fuelElevationMultiplier ?? 0, 1)
        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(saved.fuelElevationCoverageRatio),
            ElevationProfileAnalyzer.minimumCoverageRatio
        )
        XCTAssertLessThan(try XCTUnwrap(saved.fuelLitersLowerBound), try XCTUnwrap(saved.fuelLiters))
        XCTAssertGreaterThan(try XCTUnwrap(saved.fuelLitersUpperBound), try XCTUnwrap(saved.fuelLiters))
    }

    func testPriceForAnotherFuelTypeCannotCreateCostSnapshot() throws {
        let store = makeStore()
        let trip = completedTrip(index: 0)
        let userProfile = UserProfile(
            firstName: "Awa",
            phoneNumber: "+22670000000",
            vehicleType: .voiture,
            vehicleBrand: "Toyota",
            vehicleModel: "Corolla",
            vehicleYear: "2024",
            synced: false,
            fuelType: .diesel
        )
        let fuelProfile = try XCTUnwrap(VehicleFuelCatalog.profile(for: userProfile))

        try store.insertCompletedTrip(
            trip,
            samples: samples(start: trip.startedAt),
            vehicleType: .voiture,
            isCalibration: false,
            fuelProfile: fuelProfile,
            fuelSettings: FuelSettings(
                currency: .xof,
                pricePerLiter: 850,
                fuelType: .gasoline
            )
        )

        let saved = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)
        XCTAssertNotNil(saved.fuelLiters)
        XCTAssertNil(saved.fuelCostMinorUnits)
        XCTAssertNil(saved.fuelCurrency)
    }

    func testStaleFuelPriceCannotCreateCostSnapshot() throws {
        let store = makeStore()
        let trip = completedTrip(index: 0)
        let fuelProfile = try XCTUnwrap(
            VehicleFuelCatalog.profile(vehicleType: .voiture, brand: "Toyota", model: "Corolla")
        )

        try store.insertCompletedTrip(
            trip,
            samples: samples(start: trip.startedAt),
            vehicleType: .voiture,
            isCalibration: false,
            fuelProfile: fuelProfile,
            fuelSettings: FuelSettings(
                currency: .cad,
                pricePerLiter: 1.70,
                capturedAt: trip.endedAt.addingTimeInterval(-31 * 24 * 60 * 60)
            )
        )

        let saved = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)
        XCTAssertNotNil(saved.fuelLiters)
        XCTAssertNil(saved.fuelCostMinorUnits)
        XCTAssertNil(saved.fuelPriceCapturedAt)
    }

    func testOfficialLocalFuelPriceEvidenceIsSnapshotted() throws {
        let store = makeStore()
        let trip = completedTrip(index: 0)
        let fuelProfile = try XCTUnwrap(
            VehicleFuelCatalog.profile(vehicleType: .voiture, brand: "Toyota", model: "Corolla")
        )
        let source = "government_of_ontario_fuel_price_survey"
        let sourceURL = try XCTUnwrap(URL(string: "https://www.ontario.ca/v1/files/fuel-prices/fueltypesall.csv"))

        let settings = FuelSettings(
            currency: .cad,
            pricePerLiter: 1.55,
            source: .officialPublicData,
            capturedAt: trip.endedAt.addingTimeInterval(-2 * 24 * 60 * 60),
            fuelType: .gasoline,
            sourceIdentifier: source,
            sourceURL: sourceURL,
            locality: "Toronto",
            locationEvidence: FuelPriceLocationEvidence(
                countryCode: "CA",
                regionCode: "ON",
                locality: "Toronto",
                resolvedAt: trip.endedAt
            )
        )
        try store.insertCompletedTrip(
            trip,
            samples: samples(start: trip.startedAt),
            vehicleType: .voiture,
            isCalibration: false,
            fuelProfile: fuelProfile,
            fuelSettings: settings
        )

        let beforeGeographyMatch = try store.fetchRecentTrips(limit: 1).first
        XCTAssertNil(beforeGeographyMatch?.fuelCostMinorUnits)
        let endpoint = TripEndpointLocality(
            countryCode: "CA",
            regionCode: "ON",
            locality: "Toronto"
        )
        let match = try XCTUnwrap(
            FuelPriceGeographyMatcher.verifiedMatch(
                tripID: trip.id,
                settings: settings,
                start: endpoint,
                end: endpoint,
                matchedAt: trip.endedAt
            )
        )
        let dieselSettings = FuelSettings(
            currency: .cad,
            pricePerLiter: settings.pricePerLiter,
            source: .officialPublicData,
            capturedAt: settings.capturedAt,
            fuelType: .diesel,
            sourceIdentifier: settings.sourceIdentifier,
            sourceURL: settings.sourceURL,
            locality: settings.locality,
            locationEvidence: settings.locationEvidence
        )
        let dieselMatch = try XCTUnwrap(
            FuelPriceGeographyMatcher.verifiedMatch(
                tripID: trip.id,
                settings: dieselSettings,
                start: endpoint,
                end: endpoint,
                matchedAt: trip.endedAt
            )
        )
        XCTAssertFalse(
            try store.applyVerifiedOfficialFuelCost(
                tripID: trip.id,
                settings: dieselSettings,
                match: dieselMatch
            )
        )
        XCTAssertTrue(
            try store.applyVerifiedOfficialFuelCost(
                tripID: trip.id,
                settings: settings,
                match: match
            )
        )

        let saved = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)
        XCTAssertNotNil(saved.fuelCostMinorUnits)
        XCTAssertEqual(saved.fuelPriceSource, .officialPublicData)
        XCTAssertEqual(saved.fuelPriceSourceIdentifier, source)
        XCTAssertEqual(saved.fuelPriceSourceURL, sourceURL)
        XCTAssertEqual(saved.fuelPriceLocality, "Toronto")
        XCTAssertEqual(saved.fuelProfileFuelType, .gasoline)
        XCTAssertEqual(saved.fuelPriceCountryCode, "CA")
        XCTAssertEqual(saved.fuelPriceRegionCode, "ON")
        XCTAssertEqual(saved.fuelPriceRequestedLocality, "Toronto")
        XCTAssertEqual(saved.fuelPriceLocationResolvedAt, trip.endedAt)
        XCTAssertEqual(
            saved.fuelPriceGeographyMatchVersion,
            VerifiedFuelPriceGeographyMatch.version
        )
        XCTAssertEqual(saved.fuelTripStartLocality, "Toronto")
        XCTAssertEqual(saved.fuelTripEndLocality, "Toronto")
        XCTAssertFalse(
            try store.applyVerifiedOfficialFuelCost(
                tripID: trip.id,
                settings: settings,
                match: match
            )
        )

        let request = NSFetchRequest<NSManagedObject>(entityName: "Trip")
        request.predicate = NSPredicate(format: "id == %@", trip.id as CVarArg)
        let rawTrip = try XCTUnwrap(store.context.fetch(request).first)
        rawTrip.setValue(nil, forKey: "fuelPriceGeographyMatchVersion")
        try store.context.save()

        let unprovenLegacyRecord = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)
        XCTAssertNil(unprovenLegacyRecord.fuelCostMinorUnits)
        XCTAssertNil(unprovenLegacyRecord.fuelCurrency)
        XCTAssertEqual(try store.fetchSummary().fuelCostEligibleTripCount, 0)
    }

    func testFetchTripsReturnsAllTripsFromStartOfDay() throws {
        let store = makeStore()

        for index in 0..<6 {
            let trip = completedTrip(index: index)
            try store.insertCompletedTrip(
                trip,
                samples: samples(start: trip.startedAt),
                vehicleType: .voiture,
                isCalibration: false
            )
        }

        let allTrips = try store.fetchTrips(since: completedTrip(index: 0).startedAt)
        let recentTrips = try store.fetchRecentTrips(limit: 3, since: completedTrip(index: 0).startedAt)

        XCTAssertEqual(try store.completedTripsCount(), 6)
        XCTAssertEqual(allTrips.count, 6)
        XCTAssertEqual(recentTrips.count, 3)
        XCTAssertEqual(allTrips.filter(\.isCalibration).count, 0)
    }

    func testDuplicateCompletedTripIsIgnored() throws {
        let store = makeStore()
        let trip = completedTrip(index: 0)

        try store.insertCompletedTrip(
            trip,
            samples: samples(start: trip.startedAt),
            vehicleType: .moto,
            isCalibration: false
        )
        try store.insertCompletedTrip(
            trip,
            samples: samples(start: trip.startedAt),
            vehicleType: .moto,
            isCalibration: false
        )

        XCTAssertEqual(try store.completedTripsCount(), 1)
    }

    func testRecentTripsCanBeFilteredFromStartOfDay() throws {
        let store = makeStore()
        let todayTrip = completedTrip(index: 1)
        let oldTrip = CompletedDetectedTrip(
            id: UUID(),
            startedAt: todayTrip.startedAt.addingTimeInterval(-86_400),
            endedAt: todayTrip.endedAt.addingTimeInterval(-86_400),
            distanceMeters: 900,
            sampleCount: 5
        )

        try store.insertCompletedTrip(
            oldTrip,
            samples: samples(start: oldTrip.startedAt),
            vehicleType: .moto,
            isCalibration: false
        )
        try store.insertCompletedTrip(
            todayTrip,
            samples: samples(start: todayTrip.startedAt),
            vehicleType: .moto,
            isCalibration: false
        )

        let todaysTrips = try store.fetchRecentTrips(limit: 3, since: todayTrip.startedAt)

        XCTAssertEqual(todaysTrips.map(\.id), [todayTrip.id])
    }

    func testBicycleTripsHaveExactZeroFuelConsumptionAndCurrencyCost() throws {
        let store = makeStore()
        let trip = completedTrip(index: 0)

        try store.insertCompletedTrip(
            trip,
            samples: samples(start: trip.startedAt),
            vehicleType: .velo,
            isCalibration: false
        )

        let summary = try store.fetchSummary()
        let recentTrip = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)

        XCTAssertEqual(summary.fuelLiters, 0)
        XCTAssertNil(summary.fuelFCFA)
        XCTAssertEqual(recentTrip.fuelLiters, 0)
        XCTAssertNil(recentTrip.fuelFCFA)
        let metric = TripMetricsCalculator.fuelCostMetric(for: recentTrip)
        XCTAssertEqual(metric.value, 0)
        XCTAssertEqual(metric.confidence, .reliable)
    }

    func testSummaryKeepsProvenCostSubtotalAndReportsCoverage() throws {
        let store = makeStore()
        let profile = try XCTUnwrap(
            VehicleFuelCatalog.profile(vehicleType: .voiture, brand: "Toyota", model: "Corolla")
        )
        let pricedTrip = completedTrip(index: 0)
        let unpricedTrip = completedTrip(index: 1)

        try store.insertCompletedTrip(
            pricedTrip,
            samples: samples(start: pricedTrip.startedAt),
            vehicleType: .voiture,
            isCalibration: false,
            fuelProfile: profile,
            fuelSettings: FuelSettings(
                currency: .cad,
                pricePerLiter: 1.70,
                capturedAt: pricedTrip.endedAt
            )
        )
        try store.insertCompletedTrip(
            unpricedTrip,
            samples: samples(start: unpricedTrip.startedAt),
            vehicleType: .voiture,
            isCalibration: false,
            fuelProfile: profile
        )

        let summary = try store.fetchSummary()
        let pricedRecord = try XCTUnwrap(store.fetchTrips().first { $0.id == pricedTrip.id })

        XCTAssertNotNil(summary.fuelLiters)
        XCTAssertEqual(summary.fuelCostMinorUnits, pricedRecord.fuelCostMinorUnits)
        XCTAssertEqual(summary.fuelCurrency, .cad)
        XCTAssertEqual(summary.fuelCostEligibleTripCount, 1)
        XCTAssertEqual(summary.fuelCostCoverageRatio ?? -1, 0.5, accuracy: 0.000_001)
        let metric = TripMetricsCalculator.summaryFuelCostMetric(summary)
        XCTAssertEqual(metric.value, pricedRecord.fuelCostMinorUnits)
        XCTAssertEqual(metric.evidence.coverageRatio ?? -1, 0.5, accuracy: 0.000_001)
    }

    func testSummaryKeepsProvenFuelSubtotalAndReportsCoverage() throws {
        let store = makeStore()
        let profile = try XCTUnwrap(
            VehicleFuelCatalog.profile(vehicleType: .voiture, brand: "Toyota", model: "Corolla")
        )
        let profiledTrip = completedTrip(index: 0)
        let unknownTrip = completedTrip(index: 1)

        try store.insertCompletedTrip(
            profiledTrip,
            samples: samples(start: profiledTrip.startedAt),
            vehicleType: .voiture,
            isCalibration: false,
            fuelProfile: profile
        )
        try store.insertCompletedTrip(
            unknownTrip,
            samples: samples(start: unknownTrip.startedAt),
            vehicleType: .moto,
            isCalibration: false
        )

        let summary = try store.fetchSummary()
        let profiledRecord = try XCTUnwrap(store.fetchTrips().first { $0.id == profiledTrip.id })

        XCTAssertEqual(summary.fuelLiters, profiledRecord.fuelLiters)
        XCTAssertNil(summary.fuelCostMinorUnits)
        XCTAssertEqual(summary.fuelEligibleTripCount, 1)
        XCTAssertEqual(summary.fuelCoverageRatio ?? -1, 0.5, accuracy: 0.000_001)
    }

    func testMismatchedVehicleProfileDoesNotInventFuelEstimate() throws {
        let store = makeStore()
        let carProfile = try XCTUnwrap(
            VehicleFuelCatalog.profile(vehicleType: .voiture, brand: "Toyota", model: "Corolla")
        )
        let trip = completedTrip(index: 0)

        try store.insertCompletedTrip(
            trip,
            samples: samples(start: trip.startedAt),
            vehicleType: .moto,
            isCalibration: false,
            fuelProfile: carProfile,
            fuelSettings: FuelSettings(currency: .cad, pricePerLiter: 1.70)
        )

        let recentTrip = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)

        XCTAssertNil(recentTrip.fuelLiters)
        XCTAssertNil(recentTrip.fuelCostMinorUnits)
        XCTAssertNil(recentTrip.fuelProfileName)
    }

    func testSummaryAveragesAvailableScoreCriteriaAndReportsCoverage() throws {
        let store = makeStore()
        let completeTrip = completedTrip(index: 0)
        let partialTrip = completedTrip(index: 1)

        try store.insertCompletedTrip(
            completeTrip,
            samples: samples(start: completeTrip.startedAt),
            vehicleType: .voiture,
            isCalibration: false,
            scores: TripScores(
                score: 90,
                scoreVitesse: 90,
                scoreFluidite: 90,
                scoreVigilance: nil,
                scoreEco: 90
            )
        )
        try store.insertCompletedTrip(
            partialTrip,
            samples: samples(start: partialTrip.startedAt),
            vehicleType: .voiture,
            isCalibration: false,
            scores: TripScores(
                score: 80,
                scoreVitesse: 80,
                scoreFluidite: nil,
                scoreVigilance: nil,
                scoreEco: nil
            )
        )

        let summary = try store.fetchSummary()
        let metric = TripMetricsCalculator.summaryScoreMetric(summary)

        XCTAssertEqual(summary.avgScore, 85)
        XCTAssertEqual(summary.avgScoreVitesse, 85)
        XCTAssertEqual(summary.avgScoreFluidite, 90)
        XCTAssertEqual(summary.avgScoreEco, 90)
        XCTAssertEqual(summary.scoreEligibleTripCount, 2)
        XCTAssertEqual(summary.completeScoreTripCount, 1)
        XCTAssertEqual(summary.scoreCoverageRatio, 1)
        XCTAssertEqual(metric.value, 85)
        XCTAssertEqual(metric.confidence, .partial)
        XCTAssertEqual(metric.evidence.sampleCount, 2)
        XCTAssertEqual(metric.evidence.coverageRatio, 1)
    }

    func testSummaryScoreKeepsAvailableSubtotalWhenAnotherTripHasNoScore() throws {
        let store = makeStore()
        let scoredTrip = completedTrip(index: 0)
        let unscoredTrip = completedTrip(index: 1)

        try store.insertCompletedTrip(
            scoredTrip,
            samples: samples(start: scoredTrip.startedAt),
            vehicleType: .voiture,
            isCalibration: false,
            scores: TripScores(score: 88, scoreVitesse: 88, scoreFluidite: 90, scoreVigilance: nil, scoreEco: 86)
        )
        try store.insertCompletedTrip(
            unscoredTrip,
            samples: samples(start: unscoredTrip.startedAt),
            vehicleType: .voiture,
            isCalibration: false,
            scores: .unavailable
        )

        let summary = try store.fetchSummary()
        let metric = TripMetricsCalculator.summaryScoreMetric(summary)

        XCTAssertEqual(summary.avgScore, 88)
        XCTAssertEqual(summary.scoreEligibleTripCount, 1)
        XCTAssertEqual(summary.scoreCoverageRatio ?? -1, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(metric.value, 88)
        XCTAssertEqual(metric.confidence, .partial)
        XCTAssertEqual(metric.evidence.coverageRatio ?? -1, 0.5, accuracy: 0.000_001)
    }

    func testLegacyBicycleTripWithoutStoredFuelDoesNotInventZeroCost() throws {
        let persistenceController = PersistenceController(inMemory: true)
        let context = persistenceController.container.viewContext
        let store = TripStore(context: context)
        let start = Date(timeIntervalSince1970: 1_783_000_000)

        let object = NSManagedObject(
            entity: try XCTUnwrap(NSEntityDescription.entity(forEntityName: "Trip", in: context)),
            insertInto: context
        )
        object.setValue(UUID(), forKey: "id")
        object.setValue(start, forKey: "startDate")
        object.setValue(start.addingTimeInterval(600), forKey: "endDate")
        object.setValue(1.2, forKey: "distanceKm")
        object.setValue(Int64(600), forKey: "durationSec")
        object.setValue(7.2, forKey: "avgSpeedKmh")
        object.setValue(18.0, forKey: "maxSpeedKmh")
        object.setValue(nil, forKey: "score")
        object.setValue(nil, forKey: "scoreVitesse")
        object.setValue(nil, forKey: "scoreFluidite")
        object.setValue(nil, forKey: "scoreVigilance")
        object.setValue(nil, forKey: "scoreEco")
        object.setValue(nil, forKey: "fuelLiters")
        object.setValue(nil, forKey: "fuelFCFA")
        object.setValue(nil, forKey: "polyline")
        object.setValue(false, forKey: "isCalibration")
        object.setValue(VehicleType.velo.rawValue, forKey: "vehicleType")
        object.setValue("conducteur", forKey: "role")
        object.setValue(false, forKey: "synced")
        object.setValue(Date(), forKey: "createdAt")
        try context.save()

        let recentTrip = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)

        XCTAssertNil(recentTrip.fuelLiters)
        XCTAssertNil(recentTrip.fuelFCFA)
        XCTAssertEqual(recentTrip.qualityConfidence, .needsReview)
        XCTAssertEqual(recentTrip.qualityReasonCodes, [.legacyUnverified])
        XCTAssertNil(TripMetricsCalculator.fuelCostMetric(for: recentTrip).value)
        XCTAssertEqual(TripMetricsCalculator.fuelCostMetric(for: recentTrip).confidence, .needsReview)
        XCTAssertEqual(TripMetricsCalculator.fuelCostMetric(for: recentTrip).reasonCode, .tripNeedsReview)
    }

    func testLegacyMotorizedCostWithoutPriceSnapshotStaysUnavailable() throws {
        let persistenceController = PersistenceController(inMemory: true)
        let context = persistenceController.container.viewContext
        let store = TripStore(context: context)
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let routeSamples = samples(start: start)

        try insertLegacyTrip(
            context: context,
            start: start,
            vehicleType: .moto,
            distanceKm: 1.2,
            routePoints: routePoints(from: routeSamples),
            fuelFCFA: 12_345
        )
        _ = try store.recalculateLegacyQualityReports()

        let recentTrip = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)
        XCTAssertTrue(recentTrip.isTrustedForDisplay)
        XCTAssertEqual(recentTrip.fuelFCFA, 12_345)
        XCTAssertNil(recentTrip.fuelCostMinorUnits)

        let metric = TripMetricsCalculator.fuelCostMetric(for: recentTrip)
        XCTAssertNil(metric.value)
        XCTAssertEqual(metric.confidence, .needsInput)
        XCTAssertEqual(metric.reasonCode, .fuelInputMissing)
    }

    func testRecalculatesLegacyQualityFromStoredPolylineAndCorrectsDistance() throws {
        let persistenceController = PersistenceController(inMemory: true)
        let context = persistenceController.container.viewContext
        let store = TripStore(context: context)
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let routeSamples = samples(start: start)
        let expectedDistanceMeters = try XCTUnwrap(
            TripMetricsCalculator.distanceMetric(
                samples: routeSamples,
                vehicleType: .moto
            ).value
        )
        try insertLegacyTrip(
            context: context,
            start: start,
            vehicleType: .moto,
            distanceKm: 9.9,
            routePoints: routePoints(from: routeSamples)
        )

        let updatedCount = try store.recalculateLegacyQualityReports()
        let recentTrip = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)
        let summary = try store.fetchSummary()

        XCTAssertEqual(updatedCount, 1)
        XCTAssertEqual(recentTrip.qualityConfidence, .reliable)
        XCTAssertEqual(recentTrip.qualityFormulaVersion, TripQualityEngine.formulaVersion)
        XCTAssertEqual(recentTrip.distanceKm, expectedDistanceMeters / 1_000, accuracy: 0.001)
        XCTAssertNotEqual(recentTrip.distanceKm, 9.9)
        XCTAssertEqual(summary.tripsCount, 1)
        XCTAssertEqual(summary.totalKm, expectedDistanceMeters / 1_000, accuracy: 0.001)
    }

    func testRecalculatedLegacyTripWithoutSpeedAccuracyDoesNotStoreZeroMaxSpeed() throws {
        let persistenceController = PersistenceController(inMemory: true)
        let context = persistenceController.container.viewContext
        let store = TripStore(context: context)
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let routeSamples = samples(start: start)
        let legacyPolyline = try legacyPolylineDataWithoutSpeedAccuracy(from: routeSamples)

        try insertLegacyTrip(
            context: context,
            start: start,
            vehicleType: .voiture,
            distanceKm: 9.9,
            polylineData: legacyPolyline
        )

        let updatedCount = try store.recalculateLegacyQualityReports()
        let recentTrip = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)

        XCTAssertEqual(updatedCount, 1)
        XCTAssertEqual(
            recentTrip.maxSpeedKmh,
            routeSamples.map(\.speedKmh).max() ?? 0,
            accuracy: 0.01
        )
        XCTAssertNil(TripMetricsCalculator.maxSpeedMetric(for: recentTrip).value)
        XCTAssertNil(recentTrip.scoreVitesse)
    }

    func testRepairsStoredZeroMaxSpeedFromLegacyPolyline() throws {
        let persistenceController = PersistenceController(inMemory: true)
        let context = persistenceController.container.viewContext
        let store = TripStore(context: context)
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let routeSamples = samples(start: start)
        let legacyPolyline = try legacyPolylineDataWithoutSpeedAccuracy(from: routeSamples)

        try insertLegacyTrip(
            context: context,
            start: start,
            vehicleType: .voiture,
            distanceKm: 9.9,
            polylineData: legacyPolyline
        )
        let request = NSFetchRequest<NSManagedObject>(entityName: "Trip")
        let object = try XCTUnwrap(context.fetch(request).first)
        object.setValue(0.0, forKey: "maxSpeedKmh")
        object.setValue(TripQualityEngine.formulaVersion, forKey: "qualityFormulaVersion")
        try context.save()

        let updatedCount = try store.repairStoredMaxSpeedValues()
        let recentTrip = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)

        XCTAssertEqual(updatedCount, 1)
        XCTAssertEqual(
            recentTrip.maxSpeedKmh,
            routeSamples.map(\.speedKmh).max() ?? 0,
            accuracy: 0.01
        )
        XCTAssertNil(recentTrip.scoreVitesse)
        XCTAssertFalse(recentTrip.synced)
    }

    func testSummaryExcludesLegacyTripWithoutAuditableRoute() throws {
        let persistenceController = PersistenceController(inMemory: true)
        let context = persistenceController.container.viewContext
        let store = TripStore(context: context)
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        try insertLegacyTrip(
            context: context,
            start: start,
            vehicleType: .moto,
            distanceKm: 1.2,
            routePoints: []
        )

        XCTAssertEqual(try store.fetchRecentTrips(limit: 1).count, 1)
        let initialSummary = try store.fetchSummary()
        XCTAssertEqual(initialSummary.candidateTripCount, 1)
        XCTAssertEqual(initialSummary.includedTripCount, 0)
        XCTAssertEqual(initialSummary.excludedTripCount, 1)
        XCTAssertEqual(initialSummary.tripsCount, 0)

        let updatedCount = try store.recalculateLegacyQualityReports()
        let recentTrip = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)

        XCTAssertEqual(updatedCount, 1)
        XCTAssertEqual(recentTrip.qualityConfidence, .needsReview)
        XCTAssertEqual(recentTrip.qualityReasonCodes, [.legacyUnverified])
        XCTAssertEqual(try store.fetchSummary().tripsCount, 0)
    }

    func testRecalculatedRejectedLegacyTripIsExcludedFromSummary() throws {
        let persistenceController = PersistenceController(inMemory: true)
        let context = persistenceController.container.viewContext
        let store = TripStore(context: context)
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        try insertLegacyTrip(
            context: context,
            start: start,
            vehicleType: .moto,
            distanceKm: 12,
            routePoints: routePoints(from: impossibleLegacyJumpSamples(start: start))
        )

        let updatedCount = try store.recalculateLegacyQualityReports()
        let recentTrip = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)
        let summary = try store.fetchSummary()

        XCTAssertEqual(updatedCount, 1)
        XCTAssertEqual(recentTrip.qualityConfidence, .rejected)
        XCTAssertTrue(recentTrip.qualityReasonCodes.contains(.impossibleSpeed))
        XCTAssertEqual(summary.candidateTripCount, 1)
        XCTAssertEqual(summary.includedTripCount, 0)
        XCTAssertEqual(summary.excludedTripCount, 1)
        XCTAssertEqual(summary.tripsCount, 0)
        XCTAssertEqual(summary.totalKm, 0)
    }

    func testQualityLearningProfileEnablesProtectiveModeAfterRepeatedGpsRejections() throws {
        let store = makeStore()

        for _ in 0..<5 {
            try store.recordQualityDecision(
                tripId: nil,
                report: rejectedGpsQualityReport(),
                vehicleType: .moto,
                sampleCount: 5,
                source: .liveRejected,
                acceptedForStorage: false
            )
        }

        let profile = try store.fetchQualityLearningProfile()

        XCTAssertEqual(profile.sampleSize, 5)
        XCTAssertEqual(profile.rejectedCount, 5)
        XCTAssertEqual(profile.signal, .gpsDegraded)
        XCTAssertTrue(profile.isProtectiveModeEnabled)
        XCTAssertEqual(profile.minimumSummaryQualityScore, 85)
        XCTAssertTrue(profile.topReasonCodes.contains(.gpsAccuracyTooLow))
    }

    func testProtectiveLearningDoesNotRewriteHistoricalSummaryEligibility() throws {
        let store = makeStore()
        let trip = completedTrip(index: 0)

        try store.insertCompletedTrip(
            trip,
            samples: samples(start: trip.startedAt),
            vehicleType: .moto,
            isCalibration: false,
            qualityReport: partialQualityReport()
        )
        XCTAssertEqual(try store.fetchSummary().tripsCount, 1)

        for _ in 0..<5 {
            try store.recordQualityDecision(
                tripId: nil,
                report: rejectedGpsQualityReport(),
                vehicleType: .moto,
                sampleCount: 5,
                source: .liveRejected,
                acceptedForStorage: false
            )
        }

        let profile = try store.fetchQualityLearningProfile()
        let summary = try store.fetchSummary()

        XCTAssertTrue(profile.isProtectiveModeEnabled)
        XCTAssertEqual(summary.tripsCount, 1)
        XCTAssertGreaterThan(summary.totalKm, 0)
    }

    private func makeStore() -> TripStore {
        let persistenceController = PersistenceController(inMemory: true)
        return TripStore(context: persistenceController.container.viewContext)
    }

    private func legacyValue(for attribute: NSAttributeDescription) -> Any {
        switch attribute.attributeType {
        case .UUIDAttributeType:
            return UUID()
        case .dateAttributeType:
            return Date(timeIntervalSince1970: 1_783_000_000)
        case .stringAttributeType:
            return "legacy"
        case .booleanAttributeType:
            return false
        case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType:
            return 0
        case .floatAttributeType, .doubleAttributeType, .decimalAttributeType:
            return 0
        case .binaryDataAttributeType:
            return Data()
        default:
            return "legacy"
        }
    }

    private func completedTrip(index: Int) -> CompletedDetectedTrip {
        let start = Date(timeIntervalSince1970: 1_783_000_000 + Double(index * 1_000))
        return CompletedDetectedTrip(
            id: UUID(),
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            distanceMeters: 1_200,
            sampleCount: 5
        )
    }

    private func samples(start: Date) -> [LocationSample] {
        [
            sample(latitude: 12.3714, longitude: -1.5197, speed: 0, timestamp: start),
            sample(latitude: 12.3734, longitude: -1.5177, speed: 5, timestamp: start.addingTimeInterval(150)),
            sample(latitude: 12.3754, longitude: -1.5157, speed: 6, timestamp: start.addingTimeInterval(300)),
            sample(latitude: 12.3774, longitude: -1.5137, speed: 5, timestamp: start.addingTimeInterval(450)),
            sample(latitude: 12.3794, longitude: -1.5117, speed: 4, timestamp: start.addingTimeInterval(600))
        ]
    }

    private func impossibleJumpSamples(start: Date) -> [LocationSample] {
        [
            sample(latitude: 12.3714, longitude: -1.5197, speed: 12, timestamp: start),
            sample(latitude: 12.4714, longitude: -1.5197, speed: 12, timestamp: start.addingTimeInterval(10))
        ]
    }

    private func impossibleLegacyJumpSamples(start: Date) -> [LocationSample] {
        [
            sample(latitude: 12.3714, longitude: -1.5197, speed: 12, timestamp: start),
            sample(latitude: 12.4714, longitude: -1.5197, speed: 12, timestamp: start.addingTimeInterval(10)),
            sample(latitude: 12.4724, longitude: -1.5187, speed: 12, timestamp: start.addingTimeInterval(20)),
            sample(latitude: 12.4734, longitude: -1.5177, speed: 12, timestamp: start.addingTimeInterval(30)),
            sample(latitude: 12.4744, longitude: -1.5167, speed: 12, timestamp: start.addingTimeInterval(40))
        ]
    }

    private func sample(latitude: Double, longitude: Double, speed: CLLocationSpeed, timestamp: Date) -> LocationSample {
        LocationSample(
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            speedKmh: speed * 3.6,
            horizontalAccuracy: 5,
            speedAccuracy: 1
        )
    }

    private func routePoints(from samples: [LocationSample]) -> [TripRoutePoint] {
        samples.map { sample in
            TripRoutePoint(
                timestamp: sample.timestamp,
                latitude: sample.latitude,
                longitude: sample.longitude,
                speedKmh: sample.speedKmh,
                horizontalAccuracy: sample.horizontalAccuracy,
                speedAccuracy: sample.speedAccuracy
            )
        }
    }

    private func partialQualityReport() -> TripQualityReport {
        TripQualityReport(
            score: 70,
            confidence: .partial,
            reasonCodes: [.gpsAccuracyTooLow],
            activeDurationSec: 600,
            stationaryTailSec: 0,
            gpsAccuracyAvg: 45,
            gpsAccuracyP95: 95,
            rejectedSegmentCount: 0,
            validSegmentCount: 4,
            maxSampleGapSec: 150,
            p95SampleGapSec: 150,
            coverageRatio: 1,
            burstCount: 1,
            motionAgreementRate: nil,
            formulaVersion: TripQualityEngine.formulaVersion
        )
    }

    private func rejectedGpsQualityReport() -> TripQualityReport {
        TripQualityReport(
            score: 0,
            confidence: .rejected,
            reasonCodes: [.gpsAccuracyTooLow, .gpsInsufficient],
            activeDurationSec: 600,
            stationaryTailSec: 0,
            gpsAccuracyAvg: 120,
            gpsAccuracyP95: 150,
            rejectedSegmentCount: 0,
            validSegmentCount: 0,
            maxSampleGapSec: 0,
            p95SampleGapSec: 0,
            coverageRatio: 0,
            burstCount: 0,
            motionAgreementRate: nil,
            formulaVersion: TripQualityEngine.formulaVersion
        )
    }

    private func insertLegacyTrip(
        context: NSManagedObjectContext,
        start: Date,
        vehicleType: VehicleType,
        distanceKm: Double,
        routePoints: [TripRoutePoint],
        fuelFCFA: Int? = nil
    ) throws {
        let polyline = routePoints.isEmpty ? nil : try JSONEncoder().encode(routePoints)
        try insertLegacyTrip(
            context: context,
            start: start,
            vehicleType: vehicleType,
            distanceKm: distanceKm,
            polylineData: polyline,
            fuelFCFA: fuelFCFA
        )
    }

    private func insertLegacyTrip(
        context: NSManagedObjectContext,
        start: Date,
        vehicleType: VehicleType,
        distanceKm: Double,
        polylineData: Data?,
        fuelFCFA: Int? = nil
    ) throws {
        let object = NSManagedObject(
            entity: try XCTUnwrap(NSEntityDescription.entity(forEntityName: "Trip", in: context)),
            insertInto: context
        )
        object.setValue(UUID(), forKey: "id")
        object.setValue(start, forKey: "startDate")
        object.setValue(start.addingTimeInterval(600), forKey: "endDate")
        object.setValue(distanceKm, forKey: "distanceKm")
        object.setValue(Int64(600), forKey: "durationSec")
        object.setValue(distanceKm / (600.0 / 3_600), forKey: "avgSpeedKmh")
        object.setValue(18.0, forKey: "maxSpeedKmh")
        object.setValue(nil, forKey: "score")
        object.setValue(nil, forKey: "scoreVitesse")
        object.setValue(nil, forKey: "scoreFluidite")
        object.setValue(nil, forKey: "scoreVigilance")
        object.setValue(nil, forKey: "scoreEco")
        object.setValue(nil, forKey: "fuelLiters")
        object.setValue(fuelFCFA.map { Int64($0) }, forKey: "fuelFCFA")
        object.setValue(polylineData, forKey: "polyline")
        object.setValue(Int64(0), forKey: "qualityScore")
        object.setValue(TripQualityConfidence.needsReview.rawValue, forKey: "qualityConfidence")
        object.setValue(TripQualityReasonCode.legacyUnverified.rawValue, forKey: "qualityReasonCodes")
        object.setValue(Int64(0), forKey: "activeDurationSec")
        object.setValue(Int64(0), forKey: "stationaryTailSec")
        object.setValue(-1.0, forKey: "gpsAccuracyAvg")
        object.setValue(-1.0, forKey: "gpsAccuracyP95")
        object.setValue(Int64(0), forKey: "rejectedSegmentCount")
        object.setValue(Int64(0), forKey: "validSegmentCount")
        object.setValue(nil, forKey: "motionAgreementRate")
        object.setValue(TripQualityReport.legacyUnverified.formulaVersion, forKey: "qualityFormulaVersion")
        object.setValue(false, forKey: "isCalibration")
        object.setValue(vehicleType.rawValue, forKey: "vehicleType")
        object.setValue("conducteur", forKey: "role")
        object.setValue(false, forKey: "synced")
        object.setValue(Date(), forKey: "createdAt")
        try context.save()
    }

    private func legacyPolylineDataWithoutSpeedAccuracy(from samples: [LocationSample]) throws -> Data {
        let points = samples.map { sample in
            [
                "timestamp": sample.timestamp.timeIntervalSinceReferenceDate,
                "latitude": sample.latitude,
                "longitude": sample.longitude,
                "speedKmh": sample.speedKmh,
                "horizontalAccuracy": sample.horizontalAccuracy
            ]
        }
        return try JSONSerialization.data(withJSONObject: points)
    }
}
