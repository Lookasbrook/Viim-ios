import XCTest
@testable import Viim

final class VehicleFuelCatalogTests: XCTestCase {
    func testToyotaCorollaGetsNavigationBasedFuelConsumptionEstimate() {
        let profile = VehicleFuelCatalog.profile(
            vehicleType: .voiture,
            brand: "Toyota",
            model: "Corolla"
        )

        let estimate = VehicleFuelCatalog.estimateConsumption(
            distanceKm: 12,
            fuelProfile: profile
        )

        XCTAssertEqual(profile?.canonicalName, "Toyota Corolla")
        XCTAssertEqual(profile?.litersPer100Km, 6.8)
        XCTAssertEqual(estimate?.confidence, .partial)
        XCTAssertEqual(estimate?.liters ?? -1, 0.816, accuracy: 0.0001)

        let cadSettings = FuelSettings(currency: .cad, pricePerLiter: 1.70)
        XCTAssertEqual(cadSettings.costMinorUnits(for: estimate?.liters), 139)
    }

    func testGpsDynamicsChangeModeledConsumptionWithinCredibleBounds() throws {
        let profile = try XCTUnwrap(
            VehicleFuelCatalog.profile(
                vehicleType: .voiture,
                brand: "Toyota",
                model: "Corolla"
            )
        )

        let smoothDynamics = DrivingDynamics(
            meanMovingSpeedKmh: 65,
            idleRatio: 0.05,
            hardAccelerationCount: 0,
            hardBrakingCount: 0,
            accelerationRms: 0.4,
            analyzedDurationSec: 600,
            distanceKm: 12
        )
        let aggressiveDynamics = DrivingDynamics(
            meanMovingSpeedKmh: 18,
            idleRatio: 0.35,
            hardAccelerationCount: 6,
            hardBrakingCount: 5,
            accelerationRms: 1.4,
            analyzedDurationSec: 600,
            distanceKm: 12
        )

        let smooth = try XCTUnwrap(
            VehicleFuelCatalog.estimateConsumption(
                distanceKm: 12,
                fuelProfile: profile,
                dynamics: smoothDynamics,
                tripDurationSec: 600
            )
        )
        let aggressive = try XCTUnwrap(
            VehicleFuelCatalog.estimateConsumption(
                distanceKm: 12,
                fuelProfile: profile,
                dynamics: aggressiveDynamics,
                tripDurationSec: 600
            )
        )
        let baseline = try XCTUnwrap(
            VehicleFuelCatalog.estimateConsumption(
                distanceKm: 12,
                fuelProfile: profile
            )
        )

        XCTAssertLessThan(smooth.liters, baseline.liters)
        XCTAssertGreaterThan(aggressive.liters, baseline.liters)
        XCTAssertGreaterThan(aggressive.liters, smooth.liters)
        XCTAssertEqual(smooth.dynamicsMultiplier, smoothDynamics.fuelConsumptionMultiplier, accuracy: 0.000_001)
        XCTAssertEqual(aggressive.dynamicsMultiplier, 1.5, accuracy: 0.000_001)
        XCTAssertEqual(aggressive.liters, aggressive.baselineLiters * 1.5, accuracy: 0.000_001)
        XCTAssertEqual(baseline.dynamicsMultiplier, 1, accuracy: 0.000_001)
    }

    func testEstimatePublishesAConservativeRangeAndSensorCoverage() throws {
        let profile = try XCTUnwrap(
            VehicleFuelCatalog.profile(
                vehicleType: .voiture,
                brand: "Toyota",
                model: "Corolla"
            )
        )
        let dynamics = DrivingDynamics(
            meanMovingSpeedKmh: 24,
            idleRatio: 0.20,
            hardAccelerationCount: 3,
            hardBrakingCount: 2,
            accelerationRms: 0.9,
            analyzedDurationSec: 540,
            distanceKm: 12
        )
        let elevation = ElevationProfile(
            gainMeters: 180,
            lossMeters: 40,
            analyzedDistanceMeters: 10_800,
            coverageRatio: 0.90
        )

        let estimate = try XCTUnwrap(
            VehicleFuelCatalog.estimateConsumption(
                distanceKm: 12,
                fuelProfile: profile,
                dynamics: dynamics,
                tripDurationSec: 600,
                elevationProfile: elevation
            )
        )

        XCTAssertLessThan(estimate.lowerBoundLiters, estimate.liters)
        XCTAssertGreaterThan(estimate.upperBoundLiters, estimate.liters)
        XCTAssertEqual(estimate.referenceResolution, .indicativeModel)
        XCTAssertEqual(try XCTUnwrap(estimate.dynamicsCoverageRatio), 0.90, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(estimate.elevationCoverageRatio), 0.90, accuracy: 0.000_001)
        XCTAssertTrue(estimate.usedDynamics)
        XCTAssertTrue(estimate.usedElevation)
        XCTAssertGreaterThan(estimate.elevationMultiplier, 1)
        XCTAssertEqual(estimate.formulaVersion, VehicleFuelCatalog.formulaVersion)
    }

    func testInsufficientDynamicsCoverageIsDisclosedEvenWhenBaselineIsUsed() throws {
        let profile = try XCTUnwrap(
            VehicleFuelCatalog.profile(vehicleType: .voiture, brand: "Toyota", model: "Corolla")
        )
        let dynamics = DrivingDynamics(
            meanMovingSpeedKmh: 18,
            idleRatio: 0.35,
            hardAccelerationCount: 6,
            hardBrakingCount: 5,
            accelerationRms: 1.4,
            analyzedDurationSec: 79,
            distanceKm: 12
        )

        let estimate = try XCTUnwrap(
            VehicleFuelCatalog.estimateConsumption(
                distanceKm: 12,
                fuelProfile: profile,
                dynamics: dynamics,
                tripDurationSec: 100
            )
        )

        XCTAssertFalse(estimate.usedDynamics)
        XCTAssertEqual(estimate.dynamicsMultiplier, 1, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(estimate.dynamicsCoverageRatio), 0.79, accuracy: 0.000_001)
        XCTAssertGreaterThan(estimate.uncertaintyRatio, 0.4)
    }

    func testOfficialVariantRangeIsNarrowerThanIndicativeModelRange() throws {
        let official = VehicleFuelProfile(
            vehicleType: .voiture,
            fuelType: .gasoline,
            canonicalName: "Toyota Corolla 2024",
            litersPer100Km: 6.7,
            confidence: .partial,
            sourceIdentifier: "fueleconomy.gov.vehicle#47343",
            referenceResolution: .officialVariant
        )
        let indicative = VehicleFuelProfile(
            vehicleType: .voiture,
            fuelType: nil,
            canonicalName: "Toyota Corolla",
            litersPer100Km: 6.7,
            confidence: .partial,
            sourceIdentifier: VehicleFuelCatalog.sourceIdentifier,
            referenceResolution: .indicativeModel
        )

        let officialEstimate = try XCTUnwrap(
            VehicleFuelCatalog.estimateConsumption(distanceKm: 100, fuelProfile: official)
        )
        let indicativeEstimate = try XCTUnwrap(
            VehicleFuelCatalog.estimateConsumption(distanceKm: 100, fuelProfile: indicative)
        )

        XCTAssertLessThan(officialEstimate.uncertaintyRatio, indicativeEstimate.uncertaintyRatio)
        XCTAssertLessThan(
            officialEstimate.upperBoundLiters - officialEstimate.lowerBoundLiters,
            indicativeEstimate.upperBoundLiters - indicativeEstimate.lowerBoundLiters
        )
    }

    func testInvalidOrMismatchedDynamicsFallsBackToCatalogBaseline() throws {
        let profile = try XCTUnwrap(
            VehicleFuelCatalog.profile(
                vehicleType: .voiture,
                brand: "Toyota",
                model: "Corolla"
            )
        )
        let invalidDynamics = DrivingDynamics(
            meanMovingSpeedKmh: .nan,
            idleRatio: 0.2,
            hardAccelerationCount: 2,
            hardBrakingCount: 1,
            accelerationRms: 0.8,
            analyzedDurationSec: 600,
            distanceKm: 12
        )
        let mismatchedDynamics = DrivingDynamics(
            meanMovingSpeedKmh: 18,
            idleRatio: 0.35,
            hardAccelerationCount: 6,
            hardBrakingCount: 5,
            accelerationRms: 1.4,
            analyzedDurationSec: 600,
            distanceKm: 2
        )

        let invalidEstimate = try XCTUnwrap(
            VehicleFuelCatalog.estimateConsumption(
                distanceKm: 12,
                fuelProfile: profile,
                dynamics: invalidDynamics,
                tripDurationSec: 600
            )
        )
        let mismatchedEstimate = try XCTUnwrap(
            VehicleFuelCatalog.estimateConsumption(
                distanceKm: 12,
                fuelProfile: profile,
                dynamics: mismatchedDynamics,
                tripDurationSec: 600
            )
        )

        XCTAssertEqual(invalidEstimate.liters, invalidEstimate.baselineLiters, accuracy: 0.000_001)
        XCTAssertEqual(invalidEstimate.dynamicsMultiplier, 1, accuracy: 0.000_001)
        XCTAssertEqual(mismatchedEstimate.liters, mismatchedEstimate.baselineLiters, accuracy: 0.000_001)
        XCTAssertEqual(mismatchedEstimate.dynamicsMultiplier, 1, accuracy: 0.000_001)
    }

    func testDynamicsWithInsufficientTripCoverageFallsBackToCatalogBaseline() throws {
        let profile = try XCTUnwrap(
            VehicleFuelCatalog.profile(vehicleType: .voiture, brand: "Toyota", model: "Corolla")
        )
        let shortDynamics = DrivingDynamics(
            meanMovingSpeedKmh: 18,
            idleRatio: 0.35,
            hardAccelerationCount: 6,
            hardBrakingCount: 5,
            accelerationRms: 1.4,
            analyzedDurationSec: 61,
            distanceKm: 12
        )

        let estimate = try XCTUnwrap(
            VehicleFuelCatalog.estimateConsumption(
                distanceKm: 12,
                fuelProfile: profile,
                dynamics: shortDynamics,
                tripDurationSec: 3_600
            )
        )

        XCTAssertEqual(estimate.dynamicsMultiplier, 1, accuracy: 0.000_001)
        XCTAssertEqual(estimate.liters, estimate.baselineLiters, accuracy: 0.000_001)
    }

    func testDynamicsRequiresEightyPercentOfTripDuration() throws {
        let profile = try XCTUnwrap(
            VehicleFuelCatalog.profile(vehicleType: .voiture, brand: "Toyota", model: "Corolla")
        )
        let incompleteDynamics = DrivingDynamics(
            meanMovingSpeedKmh: 18,
            idleRatio: 0.35,
            hardAccelerationCount: 6,
            hardBrakingCount: 5,
            accelerationRms: 1.4,
            analyzedDurationSec: 79,
            distanceKm: 12
        )
        let sufficientlyCoveredDynamics = DrivingDynamics(
            meanMovingSpeedKmh: 18,
            idleRatio: 0.35,
            hardAccelerationCount: 6,
            hardBrakingCount: 5,
            accelerationRms: 1.4,
            analyzedDurationSec: 80,
            distanceKm: 12
        )

        let incomplete = try XCTUnwrap(
            VehicleFuelCatalog.estimateConsumption(
                distanceKm: 12,
                fuelProfile: profile,
                dynamics: incompleteDynamics,
                tripDurationSec: 100
            )
        )
        let sufficientlyCovered = try XCTUnwrap(
            VehicleFuelCatalog.estimateConsumption(
                distanceKm: 12,
                fuelProfile: profile,
                dynamics: sufficientlyCoveredDynamics,
                tripDurationSec: 100
            )
        )

        XCTAssertEqual(VehicleFuelCatalog.minimumDynamicsCoverageRatio, 0.80)
        XCTAssertEqual(incomplete.dynamicsMultiplier, 1, accuracy: 0.000_001)
        XCTAssertGreaterThan(sufficientlyCovered.dynamicsMultiplier, 1)
    }

    func testMissingTripDurationCannotApplyDynamics() throws {
        let profile = try XCTUnwrap(
            VehicleFuelCatalog.profile(vehicleType: .voiture, brand: "Toyota", model: "Corolla")
        )
        let partialDynamics = DrivingDynamics(
            meanMovingSpeedKmh: 18,
            idleRatio: 0.35,
            hardAccelerationCount: 6,
            hardBrakingCount: 5,
            accelerationRms: 1.4,
            analyzedDurationSec: 61,
            distanceKm: 12
        )

        let estimate = try XCTUnwrap(
            VehicleFuelCatalog.estimateConsumption(
                distanceKm: 12,
                fuelProfile: profile,
                dynamics: partialDynamics
            )
        )

        XCTAssertEqual(estimate.dynamicsMultiplier, 1, accuracy: 0.000_001)
        XCTAssertEqual(estimate.liters, estimate.baselineLiters, accuracy: 0.000_001)
    }

    func testDynamicsMultiplierStaysWithinCredibleBounds() {
        let extremeDynamics = DrivingDynamics(
            meanMovingSpeedKmh: 10,
            idleRatio: 0.9,
            hardAccelerationCount: 50,
            hardBrakingCount: 50,
            accelerationRms: 5,
            analyzedDurationSec: 600,
            distanceKm: 5
        )
        let ghostDynamics = DrivingDynamics(
            meanMovingSpeedKmh: 70,
            idleRatio: 0,
            hardAccelerationCount: 0,
            hardBrakingCount: 0,
            accelerationRms: 0,
            analyzedDurationSec: 600,
            distanceKm: 5
        )

        XCTAssertEqual(extremeDynamics.fuelConsumptionMultiplier, 1.5, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(ghostDynamics.fuelConsumptionMultiplier, 0.85)
    }

	    func testUnknownFuelProfileDoesNotInventCost() {
	        let profile = VehicleFuelCatalog.profile(
	            vehicleType: .voiture,
	            brand: "Marque inconnue",
	            model: "Modele inconnu"
	        )

	        XCTAssertNil(profile)
	        XCTAssertNil(VehicleFuelCatalog.estimateConsumption(distanceKm: 12, fuelProfile: profile))
	    }

	    func testCatalogSuggestsButDoesNotSilentlyCanonicalizeUserTypos() {
	        let canonicalSuggestion = VehicleFuelCatalog.canonicalSuggestion(
	            vehicleType: .voiture,
	            brand: "toyota",
	            model: "coral"
	        )
            let suggestions = VehicleFuelCatalog.suggestions(
                vehicleType: .voiture,
                query: "toyota coral",
                limit: 3
            )

            XCTAssertNil(canonicalSuggestion)
            XCTAssertNil(VehicleFuelCatalog.profile(vehicleType: .voiture, brand: "toyota", model: "coral"))
	        XCTAssertEqual(suggestions.first?.brand, "Toyota")
	        XCTAssertEqual(suggestions.first?.model, "Corolla")
	    }

	    func testWestAfricanCommonCarsAreCovered() {
	        XCTAssertEqual(VehicleFuelCatalog.profile(vehicleType: .voiture, brand: "Toyota", model: "Yaris")?.litersPer100Km, 5.8)
	        XCTAssertEqual(VehicleFuelCatalog.profile(vehicleType: .voiture, brand: "Hyundai", model: "Tucson")?.litersPer100Km, 8.0)
	        XCTAssertEqual(VehicleFuelCatalog.profile(vehicleType: .voiture, brand: "Kia", model: "Picanto")?.litersPer100Km, 5.3)
	        XCTAssertEqual(VehicleFuelCatalog.profile(vehicleType: .voiture, brand: "Nissan", model: "X-Trail")?.litersPer100Km, 8.0)
	        XCTAssertEqual(VehicleFuelCatalog.profile(vehicleType: .voiture, brand: "Renault", model: "Duster")?.litersPer100Km, 7.2)
	        XCTAssertEqual(VehicleFuelCatalog.profile(vehicleType: .voiture, brand: "Mercedes", model: "C200")?.canonicalName, "Mercedes-Benz Classe C")
	    }

	    func testBurkinaCommonMotorcyclesAreCovered() {
	        XCTAssertEqual(VehicleFuelCatalog.profile(vehicleType: .moto, brand: "Bajaj", model: "Boxer")?.litersPer100Km, 2.2)
	        XCTAssertEqual(VehicleFuelCatalog.profile(vehicleType: .moto, brand: "TVS", model: "HLX 125")?.litersPer100Km, 2.0)
	        XCTAssertEqual(VehicleFuelCatalog.profile(vehicleType: .moto, brand: "Haojue", model: "HJ125")?.litersPer100Km, 2.2)
	        XCTAssertEqual(VehicleFuelCatalog.profile(vehicleType: .moto, brand: "Apsonic", model: "AP 150")?.litersPer100Km, 2.5)
	        XCTAssertEqual(VehicleFuelCatalog.profile(vehicleType: .moto, brand: "Dayun", model: "DY 125")?.litersPer100Km, 2.2)
	        XCTAssertEqual(VehicleFuelCatalog.profile(vehicleType: .moto, brand: "Honda", model: "Wave 110")?.litersPer100Km, 1.8)
	    }

    func testAutocompleteReturnsCanonicalVehicleSuggestions() {
	        let suggestions = VehicleFuelCatalog.suggestions(
	            vehicleType: .moto,
	            query: "boxer 150",
	            limit: 3
	        )

	        XCTAssertEqual(suggestions.first?.brand, "Bajaj")
	        XCTAssertEqual(suggestions.first?.model, "Boxer BM 150")
	    }

    func testSpecificMotorcycleVariantsAreNotShadowedByGenericEntries() {
        XCTAssertEqual(
            VehicleFuelCatalog.profile(vehicleType: .moto, brand: "Bajaj", model: "Boxer BM 100")?.litersPer100Km,
            1.8
        )
        XCTAssertEqual(
            VehicleFuelCatalog.profile(vehicleType: .moto, brand: "TVS", model: "HLX 150")?.litersPer100Km,
            2.2
        )
        XCTAssertEqual(
            VehicleFuelCatalog.profile(vehicleType: .moto, brand: "Bajaj", model: "Pulsar NS 200")?.litersPer100Km,
            3.0
        )
        XCTAssertEqual(
            VehicleFuelCatalog.profile(vehicleType: .moto, brand: "TVS", model: "Apache RTR 200")?.litersPer100Km,
            3.0
        )
    }

    func testShortNumericAliasDoesNotMatchDifferentCarModel() {
        XCTAssertNil(
            VehicleFuelCatalog.profile(vehicleType: .voiture, brand: "Mazda", model: "CX-30")
        )
    }

    func testIndicativeModelReferenceDoesNotPretendFuelTypeWasResolved() throws {
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

        let resolved = try XCTUnwrap(VehicleFuelCatalog.profile(for: userProfile))

        XCTAssertNil(resolved.fuelType)
        XCTAssertEqual(resolved.confidence, .partial)
    }

    func testOfficialVariantOverridesIndicativeModelOnlyWhenEveryIdentityFieldMatches() throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://www.fueleconomy.gov/ws/rest/vehicle/47343"))
        let specification = try XCTUnwrap(
            VerifiedVehicleSpecification(
                sourceIdentifier: "fueleconomy.gov.vehicle",
                sourceRecordID: "47343",
                sourceURL: sourceURL,
                retrievedAt: Date(timeIntervalSince1970: 1_800_000_000),
                year: 2024,
                make: "Toyota",
                model: "Corolla",
                variant: "Auto (AV-S10), 4 cyl, 2.0 L, SIDI & PFI",
                engineDescription: "2.0 L · 4 cyl · SIDI & PFI",
                transmission: "Automatic (AV-S10)",
                fuelType: .gasoline,
                cityLitersPer100Km: 235.214583 / 32,
                highwayLitersPer100Km: 235.214583 / 41,
                combinedLitersPer100Km: 235.214583 / 35
            )
        )
        let exactProfile = UserProfile(
            firstName: "Awa",
            phoneNumber: "+14185550123",
            vehicleType: .voiture,
            vehicleBrand: "Toyota",
            vehicleModel: "Corolla",
            vehicleYear: "2024",
            synced: false,
            fuelType: .gasoline,
            vehicleSpecification: specification
        )
        var wrongFuelProfile = exactProfile
        wrongFuelProfile.fuelType = .diesel
        var wrongYearProfile = exactProfile
        wrongYearProfile.vehicleSpecification = VerifiedVehicleSpecification(
            sourceIdentifier: specification.sourceIdentifier,
            sourceRecordID: specification.sourceRecordID,
            sourceURL: specification.sourceURL,
            retrievedAt: specification.retrievedAt,
            year: 2023,
            make: specification.make,
            model: specification.model,
            variant: specification.variant,
            engineDescription: specification.engineDescription,
            transmission: specification.transmission,
            fuelType: specification.fuelType,
            cityLitersPer100Km: specification.cityLitersPer100Km,
            highwayLitersPer100Km: specification.highwayLitersPer100Km,
            combinedLitersPer100Km: specification.combinedLitersPer100Km
        )

        let resolved = try XCTUnwrap(VehicleFuelCatalog.profile(for: exactProfile))

        XCTAssertEqual(resolved.litersPer100Km, specification.combinedLitersPer100Km, accuracy: 0.000_001)
        XCTAssertEqual(resolved.fuelType, .gasoline)
        XCTAssertEqual(resolved.sourceIdentifier, "fueleconomy.gov.vehicle#47343")
        XCTAssertEqual(resolved.referenceResolution, .officialVariant)
        XCTAssertNil(VehicleFuelCatalog.profile(for: wrongFuelProfile))
        XCTAssertNil(wrongYearProfile.vehicleSpecification?.matched(to: wrongYearProfile))
    }

    func testLegacyProfileDecodesWithoutInventingVerifiedSpecification() throws {
        let legacyJSON = #"{"firstName":"Awa","phoneNumber":"+22670000000","vehicleType":"voiture","vehicleBrand":"Toyota","vehicleModel":"Corolla","vehicleYear":"2024","synced":false,"fuelType":"gasoline"}"#

        let decoded = try JSONDecoder().decode(UserProfile.self, from: Data(legacyJSON.utf8))

        XCTAssertNil(decoded.vehicleSpecification)
        XCTAssertEqual(decoded.vehicleDisplayName, "Toyota Corolla 2024")
    }

    func testChangingFuelTypeInvalidatesVerifiedVehicleSpecification() throws {
        let suiteName = "VehicleFuelCatalogTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let specification = try XCTUnwrap(
            VerifiedVehicleSpecification(
                sourceIdentifier: "fueleconomy.gov.vehicle",
                sourceRecordID: "47343",
                sourceURL: URL(string: "https://www.fueleconomy.gov/ws/rest/vehicle/47343")!,
                retrievedAt: Date(timeIntervalSince1970: 1_800_000_000),
                year: 2024,
                make: "Toyota",
                model: "Corolla",
                variant: "Automatic",
                engineDescription: "2.0 L",
                transmission: "Automatic",
                fuelType: .gasoline,
                cityLitersPer100Km: 7.3,
                highwayLitersPer100Km: 5.7,
                combinedLitersPer100Km: 6.7
            )
        )
        let profile = UserProfile(
            firstName: "Awa",
            phoneNumber: "+14185550123",
            vehicleType: .voiture,
            vehicleBrand: "Toyota",
            vehicleModel: "Corolla",
            vehicleYear: "2024",
            synced: false,
            fuelType: .gasoline,
            vehicleSpecification: specification
        )
        defaults.set(try JSONEncoder().encode(profile), forKey: "viim.userProfile.v1")
        let store = OnboardingStore(userDefaults: defaults)

        try store.updateVehicleFuelType(.diesel)

        XCTAssertEqual(store.profile?.fuelType, .diesel)
        XCTAssertNil(store.profile?.vehicleSpecification)
    }

	    func testBicycleFuelEstimateIsExactZero() {
	        let profile = VehicleFuelCatalog.profile(
            vehicleType: .velo,
            brand: "Trek",
            model: "Marlin"
        )

        let estimate = VehicleFuelCatalog.estimateConsumption(
            distanceKm: 12,
            fuelProfile: profile
        )

        XCTAssertEqual(profile?.confidence, .reliable)
        XCTAssertEqual(estimate?.liters, 0)
        XCTAssertEqual(estimate?.lowerBoundLiters, 0)
        XCTAssertEqual(estimate?.upperBoundLiters, 0)
        XCTAssertEqual(estimate?.uncertaintyRatio, 0)
        XCTAssertEqual(estimate?.referenceResolution, .bicycleZero)
        XCTAssertEqual(estimate?.confidence, .reliable)
    }

    func testSupportedCurrenciesConvertLitersIntoTheirOwnMinorUnits() {
        XCTAssertEqual(FuelSettings(currency: .xof, pricePerLiter: 850).costMinorUnits(for: 1.25), 1_063)
        XCTAssertEqual(FuelSettings(currency: .cad, pricePerLiter: 1.70).costMinorUnits(for: 1.25), 213)
        XCTAssertEqual(FuelSettings(currency: .usd, pricePerLiter: 1.00).costMinorUnits(for: 1.25), 125)
        XCTAssertEqual(FuelSettings(currency: .eur, pricePerLiter: 1.80).costMinorUnits(for: 1.25), 225)
    }

    func testSelectedCurrencyAndFuelPricePersistAcrossStoreRelaunch() throws {
        let suiteName = "VehicleFuelCatalogTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = OnboardingStore(
            userDefaults: defaults,
            locale: Locale(identifier: "fr_BF")
        )
        try store.updateFuelSettings(
            FuelSettings(currency: .cad, pricePerLiter: 1.67)
        )

        let relaunchedStore = OnboardingStore(
            userDefaults: defaults,
            locale: Locale(identifier: "fr_BF")
        )
        XCTAssertEqual(relaunchedStore.fuelSettings, FuelSettings(currency: .cad, pricePerLiter: 1.67))
    }

    func testDefaultFuelPriceIsExplicitlyUnverified() {
        let settings = FuelSettings.defaults(for: Locale(identifier: "fr_CA"))

        XCTAssertEqual(settings.currency, .cad)
        XCTAssertEqual(settings.source, .unverifiedDefault)
        XCTAssertFalse(settings.canSnapshotCost)
        XCTAssertNil(settings.costMinorUnits(for: 1.25))
    }

    func testFuelPriceMustBeDatedAndRecentToSnapshotCost() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let undated = FuelSettings(currency: .cad, pricePerLiter: 1.70)
        let fresh = FuelSettings(
            currency: .cad,
            pricePerLiter: 1.70,
            capturedAt: now.addingTimeInterval(-29 * 24 * 60 * 60)
        )
        let stale = FuelSettings(
            currency: .cad,
            pricePerLiter: 1.70,
            capturedAt: now.addingTimeInterval(-31 * 24 * 60 * 60)
        )

        XCTAssertFalse(undated.canSnapshotCost(at: now))
        XCTAssertTrue(fresh.canSnapshotCost(at: now))
        XCTAssertFalse(stale.canSnapshotCost(at: now))
    }

    func testRecentOfficialPublicPriceCanSnapshotCost() {
        let observedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let settings = FuelSettings(
            currency: .cad,
            pricePerLiter: 1.55,
            source: .officialPublicData,
            capturedAt: observedAt,
            fuelType: .gasoline,
            sourceIdentifier: "government_of_ontario_fuel_price_survey",
            sourceURL: URL(string: "https://www.ontario.ca/v1/files/fuel-prices/fueltypesall.csv"),
            locality: "Toronto"
        )

        XCTAssertTrue(settings.canSnapshotCost(at: observedAt.addingTimeInterval(7 * 24 * 60 * 60)))
        XCTAssertFalse(settings.canSnapshotCost(at: observedAt.addingTimeInterval(15 * 24 * 60 * 60)))
        XCTAssertEqual(settings.costMinorUnits(for: 10), 1_550)
    }

    func testOfficialPriceRequiresCompleteHttpsEvidence() {
        let observedAt = Date(timeIntervalSince1970: 1_800_000_000)
        func settings(
            identifier: String? = "government_of_ontario_fuel_price_survey",
            url: URL? = URL(string: "https://www.ontario.ca/v1/files/fuel-prices/fueltypesall.csv"),
            locality: String? = "Toronto",
            currency: SupportedCurrency = .cad,
            price: Double = 1.553
        ) -> FuelSettings {
            FuelSettings(
                currency: currency,
                pricePerLiter: price,
                source: .officialPublicData,
                capturedAt: observedAt,
                fuelType: .gasoline,
                sourceIdentifier: identifier,
                sourceURL: url,
                locality: locality
            )
        }

        XCTAssertTrue(settings().canSnapshotCost(at: observedAt))
        XCTAssertFalse(settings(identifier: nil).canSnapshotCost(at: observedAt))
        XCTAssertFalse(settings(url: nil).canSnapshotCost(at: observedAt))
        XCTAssertFalse(settings(url: URL(string: "http://example.com/fuel.csv")).canSnapshotCost(at: observedAt))
        XCTAssertFalse(settings(url: URL(string: "https://example.com/v1/files/fuel-prices/fueltypesall.csv")).canSnapshotCost(at: observedAt))
        XCTAssertFalse(settings(url: URL(string: "https://www.ontario.ca/fuel.csv")).canSnapshotCost(at: observedAt))
        XCTAssertFalse(settings(currency: .usd).canSnapshotCost(at: observedAt))
        XCTAssertFalse(settings(price: 5.01).canSnapshotCost(at: observedAt))
        XCTAssertFalse(settings(locality: nil).canSnapshotCost(at: observedAt))
    }

    func testUnchangedThreeDecimalOfficialPricePreservesProvenance() throws {
        let observedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let official = FuelSettings(
            currency: .cad,
            pricePerLiter: 1.553,
            source: .officialPublicData,
            capturedAt: observedAt,
            fuelType: .gasoline,
            sourceIdentifier: "government_of_ontario_fuel_price_survey",
            sourceURL: URL(string: "https://www.ontario.ca/v1/files/fuel-prices/fueltypesall.csv"),
            locality: "Toronto"
        )
        let rendered = FuelPriceEditorPolicy.priceText(
            official.pricePerLiter,
            locale: Locale(identifier: "en_CA")
        )
        let parsed = try XCTUnwrap(Double(rendered))

        let unchanged = FuelPriceEditorPolicy.settingsForSave(
            currentSettings: official,
            selectedFuelType: .gasoline,
            selectedCurrency: .cad,
            parsedPrice: parsed,
            now: observedAt.addingTimeInterval(3_600)
        )
        let edited = FuelPriceEditorPolicy.settingsForSave(
            currentSettings: official,
            selectedFuelType: .gasoline,
            selectedCurrency: .cad,
            parsedPrice: 1.600,
            now: observedAt.addingTimeInterval(3_600)
        )

        XCTAssertEqual(rendered, "1.553")
        XCTAssertEqual(unchanged, official)
        XCTAssertEqual(edited.source, .userProvided)
        XCTAssertNil(edited.sourceIdentifier)
        XCTAssertNil(edited.sourceURL)
        XCTAssertNil(edited.locality)
    }

    func testFuelPriceLookupCannotOverwriteNewerStoreState() {
        let profile = UserProfile(
            firstName: "Awa",
            phoneNumber: "+14185550123",
            vehicleType: .voiture,
            vehicleBrand: "Toyota",
            vehicleModel: "Corolla",
            vehicleYear: "2024",
            synced: false,
            fuelType: .gasoline
        )
        let initial = FuelSettings(
            currency: .cad,
            pricePerLiter: 1.55,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
            fuelType: .gasoline
        )
        let request = FuelPriceLookupRequest(
            id: UUID(),
            profile: profile,
            settings: initial,
            fuelType: .gasoline
        )
        let newer = FuelSettings(
            currency: .cad,
            pricePerLiter: 1.60,
            capturedAt: Date(timeIntervalSince1970: 1_800_003_600),
            fuelType: .gasoline
        )

        XCTAssertTrue(
            request.canCommit(
                activeRequestID: request.id,
                currentProfile: profile,
                currentSettings: initial,
                selectedFuelType: .gasoline
            )
        )
        XCTAssertFalse(
            request.canCommit(
                activeRequestID: request.id,
                currentProfile: profile,
                currentSettings: newer,
                selectedFuelType: .gasoline
            )
        )
        XCTAssertFalse(
            request.canCommit(
                activeRequestID: UUID(),
                currentProfile: profile,
                currentSettings: initial,
                selectedFuelType: .gasoline
            )
        )
    }

    func testFuelPriceLookupUsesRegionWhenReverseGeocoderHasNoCity() {
        XCTAssertEqual(
            FuelPriceLookupRequest.coarseLocality(locality: nil, regionCode: "Ontario"),
            "Ontario"
        )
        XCTAssertEqual(
            FuelPriceLookupRequest.coarseLocality(locality: "  Toronto  ", regionCode: "Ontario"),
            "Toronto"
        )
        XCTAssertNil(FuelPriceLookupRequest.coarseLocality(locality: nil, regionCode: "  "))
    }

    func testFuelPriceLookupReusesOnlyMatchingFreshOfficialEvidence() throws {
        let now = Date(timeIntervalSince1970: 1_788_409_800)
        let profile = UserProfile(
            firstName: "Awa",
            phoneNumber: "+14185550123",
            vehicleType: .voiture,
            vehicleBrand: "Toyota",
            vehicleModel: "Corolla",
            vehicleYear: "2024",
            synced: false,
            fuelType: .gasoline
        )
        let official = FuelSettings(
            currency: .cad,
            pricePerLiter: 1.55,
            source: .officialPublicData,
            capturedAt: now.addingTimeInterval(-6 * 24 * 60 * 60),
            fuelType: .gasoline,
            sourceIdentifier: "government_of_ontario_fuel_price_survey",
            sourceURL: try XCTUnwrap(URL(string: "https://www.ontario.ca/v1/files/fuel-prices/fueltypesall.csv")),
            locality: "Toronto"
        )
        let request = FuelPriceLookupRequest(
            id: UUID(),
            profile: profile,
            settings: official,
            fuelType: .gasoline
        )

        XCTAssertTrue(
            request.canReuseCachedOfficialPrice(
                activeRequestID: request.id,
                currentProfile: profile,
                currentSettings: official,
                selectedFuelType: .gasoline,
                at: now
            )
        )
        XCTAssertFalse(
            request.canReuseCachedOfficialPrice(
                activeRequestID: request.id,
                currentProfile: profile,
                currentSettings: official,
                selectedFuelType: .diesel,
                at: now
            )
        )
        XCTAssertFalse(
            request.canReuseCachedOfficialPrice(
                activeRequestID: request.id,
                currentProfile: profile,
                currentSettings: official,
                selectedFuelType: .gasoline,
                at: now.addingTimeInterval(15 * 24 * 60 * 60)
            )
        )
    }

    func testFuelConfigurationUpdatesProfileAndMatchingEvidenceTogether() throws {
        let suiteName = "VehicleFuelCatalogTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let profile = UserProfile(
            firstName: "Awa",
            phoneNumber: "+14185550123",
            vehicleType: .voiture,
            vehicleBrand: "Toyota",
            vehicleModel: "Corolla",
            vehicleYear: "2024",
            synced: false,
            fuelType: .gasoline
        )
        defaults.set(try JSONEncoder().encode(profile), forKey: "viim.userProfile.v1")
        let store = OnboardingStore(userDefaults: defaults)
        let dieselSettings = FuelSettings(
            currency: .cad,
            pricePerLiter: 1.70,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
            fuelType: .diesel
        )

        try store.updateFuelConfiguration(fuelType: .diesel, settings: dieselSettings)

        XCTAssertEqual(store.profile?.fuelType, .diesel)
        XCTAssertEqual(store.fuelSettings, dieselSettings)
    }

    func testElectricVehicleDoesNotInventLiquidFuelConsumption() {
        let profile = UserProfile(
            firstName: "Awa",
            phoneNumber: "+22670000000",
            vehicleType: .voiture,
            vehicleBrand: "Toyota",
            vehicleModel: "Corolla",
            vehicleYear: "2024",
            synced: false,
            fuelType: .electric
        )

        XCTAssertNil(VehicleFuelCatalog.profile(for: profile))
    }

    func testChangingFuelTypeInvalidatesPriceForPreviousFuel() throws {
        let suiteName = "VehicleFuelCatalogTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let profile = UserProfile(
            firstName: "Awa",
            phoneNumber: "+22670000000",
            vehicleType: .voiture,
            vehicleBrand: "Toyota",
            vehicleModel: "Corolla",
            vehicleYear: "2024",
            synced: false,
            fuelType: .gasoline
        )
        defaults.set(try JSONEncoder().encode(profile), forKey: "viim.userProfile.v1")
        let store = OnboardingStore(userDefaults: defaults)
        try store.updateFuelSettings(
            FuelSettings(currency: .xof, pricePerLiter: 850, fuelType: .gasoline)
        )

        try store.updateVehicleFuelType(.diesel)

        XCTAssertEqual(store.profile?.fuelType, .diesel)
        XCTAssertEqual(store.fuelSettings.fuelType, .diesel)
        XCTAssertEqual(store.fuelSettings.source, .unverifiedDefault)
        XCTAssertFalse(store.fuelSettings.canSnapshotCost)
    }

    func testVehicleCatalogLookupCannotOverwriteChangedProfile() {
        let profile = UserProfile(
            firstName: "Awa",
            phoneNumber: "+14185550123",
            vehicleType: .voiture,
            vehicleBrand: "Toyota",
            vehicleModel: "Corolla",
            vehicleYear: "2024",
            synced: false,
            fuelType: .gasoline
        )
        let request = VehicleCatalogLookupRequest(id: UUID(), profile: profile)
        var changedProfile = profile
        changedProfile.fuelType = .diesel

        XCTAssertTrue(
            request.canCommit(activeRequestID: request.id, currentProfile: profile)
        )
        XCTAssertFalse(
            request.canCommit(activeRequestID: request.id, currentProfile: changedProfile)
        )
        XCTAssertFalse(
            request.canCommit(activeRequestID: UUID(), currentProfile: profile)
        )
    }

    func testStoreRejectsMismatchedOfficialSpecificationWithoutOverwritingProfile() throws {
        let suiteName = "VehicleFuelCatalogTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let profile = UserProfile(
            firstName: "Awa",
            phoneNumber: "+14185550123",
            vehicleType: .voiture,
            vehicleBrand: "Toyota",
            vehicleModel: "Corolla",
            vehicleYear: "2024",
            synced: false,
            fuelType: .gasoline
        )
        defaults.set(try JSONEncoder().encode(profile), forKey: "viim.userProfile.v1")
        let store = OnboardingStore(userDefaults: defaults)
        let mismatchedSpecification = try XCTUnwrap(
            VerifiedVehicleSpecification(
                sourceIdentifier: "fueleconomy.gov.vehicle",
                sourceRecordID: "47345",
                sourceURL: URL(string: "https://www.fueleconomy.gov/ws/rest/vehicle/47345")!,
                retrievedAt: Date(timeIntervalSince1970: 1_800_000_000),
                year: 2024,
                make: "Toyota",
                model: "Camry",
                variant: "2024 Toyota Camry",
                engineDescription: "2.5 L, 4 cyl",
                transmission: "Automatic 8-spd",
                fuelType: .gasoline,
                cityLitersPer100Km: 8.4,
                highwayLitersPer100Km: 6.1,
                combinedLitersPer100Km: 7.4
            )
        )

        XCTAssertThrowsError(try store.updateVehicleSpecification(mismatchedSpecification)) { error in
            XCTAssertEqual(error as? VehicleSpecificationError, .identityMismatch)
        }
        XCTAssertNil(store.profile?.vehicleSpecification)
        XCTAssertEqual(store.profile, profile)
    }

    func testEmergencyNumbersAreCountrySpecificAndUnknownCountryDoesNotGuess() {
        XCTAssertEqual(
            EmergencyNumberCatalog.numbers(for: .burkinaFaso),
            EmergencyNumbers(firefighters: "18", police: "17", sourceIdentifier: "police.gov.bf")
        )
        XCTAssertEqual(
            EmergencyNumberCatalog.numbers(for: .canada),
            EmergencyNumbers(firefighters: "911", police: "911", sourceIdentifier: "canada.ca")
        )
        XCTAssertNil(EmergencyNumberCatalog.numbers(for: .other).firefighters)
        XCTAssertNil(EmergencyNumberCatalog.numbers(for: .other).police)
    }

    func testCountryAndPhoneCallingCodeMustStayConsistent() {
        XCTAssertTrue(SupportedCountry.burkinaFaso.matches(phoneNumber: "+22670000000"))
        XCTAssertTrue(SupportedCountry.canada.matches(phoneNumber: "+14185550123"))
        XCTAssertTrue(SupportedCountry.other.matches(phoneNumber: "+33612345678"))
        XCTAssertFalse(SupportedCountry.canada.matches(phoneNumber: "+22670000000"))
        XCTAssertFalse(SupportedCountry.other.matches(phoneNumber: "+14185550123"))
    }

    func testLegacyProfileCountryFallbackNeverTreatsUnknownCallingCodeAsBurkinaFaso() {
        func profile(phoneNumber: String) -> UserProfile {
            UserProfile(
                firstName: "Awa",
                phoneNumber: phoneNumber,
                vehicleType: .moto,
                vehicleBrand: "Bajaj",
                vehicleModel: "Boxer",
                vehicleYear: "2024",
                synced: false
            )
        }

        XCTAssertEqual(profile(phoneNumber: "+22670000000").country, .burkinaFaso)
        XCTAssertEqual(profile(phoneNumber: "+14185550123").country, .canada)
        XCTAssertEqual(profile(phoneNumber: "+33612345678").country, .other)
    }
}
