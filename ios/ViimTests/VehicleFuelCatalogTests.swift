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

    func testGpsDynamicsDoNotChangeFinancialConsumptionEstimate() throws {
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
                dynamics: smoothDynamics
            )
        )
        let aggressive = try XCTUnwrap(
            VehicleFuelCatalog.estimateConsumption(
                distanceKm: 12,
                fuelProfile: profile,
                dynamics: aggressiveDynamics
            )
        )
        let baseline = try XCTUnwrap(
            VehicleFuelCatalog.estimateConsumption(
                distanceKm: 12,
                fuelProfile: profile
            )
        )

        XCTAssertEqual(smooth.liters, baseline.liters, accuracy: 0.000_001)
        XCTAssertEqual(aggressive.liters, baseline.liters, accuracy: 0.000_001)
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
