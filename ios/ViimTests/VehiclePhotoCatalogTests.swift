import XCTest
import UIKit
@testable import Viim

final class VehiclePhotoCatalogTests: XCTestCase {
    func testToyotaCarModelsResolveToExactAssets() {
        XCTAssertEqual(asset(.voiture, "Toyota", "Corolla"), "VehiclePhotoToyotaCorolla")
        XCTAssertEqual(asset(.voiture, "Toyota", "Corolla Altis"), "VehiclePhotoToyotaCorolla")
        XCTAssertEqual(asset(.voiture, "Toyota", "Hilux E"), "VehiclePhotoToyotaHilux")
        XCTAssertEqual(asset(.voiture, "Toyota", "RAV 4"), "VehiclePhotoToyotaRAV4")
        XCTAssertEqual(asset(.voiture, "Toyota", "Yaris"), "VehiclePhotoToyotaYaris")
        XCTAssertEqual(asset(.voiture, "Renault", "Duster"), "VehiclePhotoRenaultDuster")
        XCTAssertEqual(asset(.voiture, "Kia", "Picanto"), "VehiclePhotoKiaPicanto")
        XCTAssertEqual(asset(.voiture, "Nissan", "Navara"), "VehiclePhotoNissanNavara")
        XCTAssertEqual(asset(.voiture, "Toyota", "Land Cruiser Prado"), "VehiclePhotoToyotaPrado")
        XCTAssertEqual(asset(.voiture, "Toyota", "Land Cruiser 70"), "VehiclePhotoToyotaLandCruiser")
    }

    func testMotoModelsResolveToExactAssets() {
        XCTAssertEqual(asset(.moto, "Yamaha", "Crypton"), "VehiclePhotoYamahaCrypton")
        XCTAssertEqual(asset(.moto, "Yamaha", "YBR 125"), "VehiclePhotoYamahaYBR")
        XCTAssertEqual(asset(.moto, "Yamaha", "FZ-S 150"), "VehiclePhotoYamahaFZS")
        XCTAssertEqual(asset(.moto, "Honda", "CB125F"), "VehiclePhotoHondaCB125F")
        XCTAssertEqual(asset(.moto, "Bajaj", "Boxer BM 150"), "VehiclePhotoBajajBoxer")
        XCTAssertEqual(asset(.moto, "TVS", "Apache RTR 200"), "VehiclePhotoTVSApache")
        XCTAssertEqual(asset(.moto, "Honda", "CG 125"), "VehiclePhotoHondaCG125")
        XCTAssertEqual(asset(.moto, "Suzuki", "GN 125"), "VehiclePhotoSuzukiGN125")
        XCTAssertEqual(
            VehiclePhotoCatalog.resolve(
                vehicleType: .moto,
                brand: "Honda",
                model: "Wave 110",
                year: "2026"
            )?.assetName,
            "VehiclePhotoHondaWave110"
        )
    }

    func testMatchingHandlesBrandAndModelTypedTogether() {
        XCTAssertEqual(asset(.voiture, "", "Toyota Corolla"), "VehiclePhotoToyotaCorolla")
        XCTAssertEqual(asset(.moto, "", "Yamaha Crypton"), "VehiclePhotoYamahaCrypton")
    }

    func testUnknownOrWrongTypeDoesNotReturnMisleadingPhoto() {
        XCTAssertNil(VehiclePhotoCatalog.resolve(vehicleType: .voiture, brand: "Yamaha", model: "YBR 125"))
        XCTAssertNil(VehiclePhotoCatalog.resolve(vehicleType: .moto, brand: "Toyota", model: "Hilux"))
        XCTAssertNil(VehiclePhotoCatalog.resolve(vehicleType: .voiture, brand: "Mercedes", model: "Classe C"))
        XCTAssertNil(VehiclePhotoCatalog.resolve(vehicleType: .velo, brand: "Trek", model: "Marlin"))
        XCTAssertNil(VehiclePhotoCatalog.resolve(vehicleType: .voiture, brand: "Toyota", model: "RAV4 Prime"))
        XCTAssertNil(VehiclePhotoCatalog.resolve(vehicleType: .moto, brand: "Bajaj", model: "Boxer BM 100"))
        XCTAssertNil(VehiclePhotoCatalog.resolve(vehicleType: .voiture, brand: "Dacia", model: "Duster"))
        XCTAssertNil(VehiclePhotoCatalog.resolve(vehicleType: .voiture, brand: "Nissan", model: "Frontier"))
        XCTAssertNil(VehiclePhotoCatalog.resolve(vehicleType: .voiture, brand: "Kia", model: "Morning"))
        XCTAssertNil(VehiclePhotoCatalog.resolve(vehicleType: .voiture, brand: "Toyota", model: "Vitz"))
    }

    func testTrimSpecificPhotosNeverMatchAnAmbiguousSiblingModel() {
        XCTAssertNil(VehiclePhotoCatalog.resolve(vehicleType: .voiture, brand: "Toyota", model: "Land Cruiser"))
        XCTAssertNil(VehiclePhotoCatalog.resolve(vehicleType: .voiture, brand: "Toyota", model: "Hilux GR"))
        XCTAssertNil(VehiclePhotoCatalog.resolve(vehicleType: .voiture, brand: "Toyota", model: "Yaris Sedan"))
        XCTAssertNil(VehiclePhotoCatalog.resolve(vehicleType: .moto, brand: "Yamaha", model: "YBR"))
        XCTAssertNil(VehiclePhotoCatalog.resolve(vehicleType: .moto, brand: "Yamaha", model: "FZ 150"))
        XCTAssertNil(VehiclePhotoCatalog.resolve(vehicleType: .moto, brand: "Bajaj", model: "Boxer"))
        XCTAssertNil(VehiclePhotoCatalog.resolve(vehicleType: .moto, brand: "TVS", model: "Apache"))
        XCTAssertNil(VehiclePhotoCatalog.resolve(vehicleType: .moto, brand: "Honda", model: "CG"))
        XCTAssertNil(VehiclePhotoCatalog.resolve(vehicleType: .moto, brand: "Honda", model: "Wave 110"))
        XCTAssertNil(
            VehiclePhotoCatalog.resolve(
                vehicleType: .moto,
                brand: "Honda",
                model: "Wave 110",
                year: "2025"
            )
        )
    }

    func testAllCatalogEntriesPointToBundledAssets() {
        let catalogedNames = VehiclePhotoCatalog.catalogedAssetNames()
        for assetName in catalogedNames {
            XCTAssertNotNil(UIImage(named: assetName), "Asset manquant: \(assetName)")
        }
    }

    func testEveryDisplayablePhotoHasCompleteAuditableAttribution() {
        let assets = VehiclePhotoCatalog.catalogedAssetNames()
        let attributions = VehiclePhotoCatalog.catalogedAttributions()

        XCTAssertEqual(Set(attributions.map(\.assetName)), assets)
        XCTAssertEqual(attributions.count, assets.count)
        XCTAssertEqual(Set(attributions.map(\.sourceRevisionSHA1)).count, attributions.count)

        for attribution in attributions {
            XCTAssertTrue(attribution.isEligibleForDisplay, attribution.assetName)
            XCTAssertEqual(attribution.creationMethod, .photograph)
            XCTAssertEqual(attribution.sourceURL.scheme, "https")
            XCTAssertEqual(attribution.sourceURL.host, "commons.wikimedia.org")
            XCTAssertEqual(attribution.sourceRevisionSHA1.count, 40)
            XCTAssertTrue(attribution.sourceRevisionSHA1.allSatisfy { $0.isHexDigit })
            XCTAssertFalse(attribution.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(attribution.modifications.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    func testResolvedPhotoCarriesItsSourceAndLicenseIntoTheUI() throws {
        let resolution = try XCTUnwrap(
            VehiclePhotoCatalog.resolve(
                vehicleType: .moto,
                brand: "Bajaj",
                model: "Boxer BM 150"
            )
        )

        XCTAssertEqual(resolution.attribution.assetName, resolution.assetName)
        XCTAssertEqual(resolution.attribution.author, "Axxter99")
        XCTAssertEqual(resolution.attribution.license.displayName, "CC BY-SA 4.0")
        XCTAssertEqual(
            resolution.attribution.sourceURL.absoluteString,
            "https://commons.wikimedia.org/wiki/File:Bajaj_Boxer_BM_150.jpg"
        )
        XCTAssertTrue(resolution.attribution.isEligibleForDisplay)
    }

    private func asset(_ type: VehicleType, _ brand: String, _ model: String) -> String? {
        VehiclePhotoCatalog.resolve(vehicleType: type, brand: brand, model: model)?.assetName
    }
}
