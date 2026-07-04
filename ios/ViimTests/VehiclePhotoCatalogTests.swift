import XCTest
import UIKit
@testable import Viim

final class VehiclePhotoCatalogTests: XCTestCase {
    func testToyotaCarModelsResolveToExactAssets() {
        XCTAssertEqual(asset(.voiture, "Toyota", "Corolla"), "VehiclePhotoToyotaCorolla")
        XCTAssertEqual(asset(.voiture, "Toyota", "Corolla Altis"), "VehiclePhotoToyotaCorolla")
        XCTAssertEqual(asset(.voiture, "Toyota", "Hilux E"), "VehiclePhotoToyotaHilux")
        XCTAssertEqual(asset(.voiture, "Toyota", "RAV 4"), "VehiclePhotoToyotaRAV4")
        XCTAssertEqual(asset(.voiture, "Toyota", "Land Cruiser Prado"), "VehiclePhotoToyotaPrado")
        XCTAssertEqual(asset(.voiture, "Toyota", "Land Cruiser 70"), "VehiclePhotoToyotaLandCruiser")
    }

    func testMotoModelsResolveToExactAssets() {
        XCTAssertEqual(asset(.moto, "Yamaha", "Crypton"), "VehiclePhotoYamahaCrypton")
        XCTAssertEqual(asset(.moto, "Yamaha", "YBR 125"), "VehiclePhotoYamahaYBR")
        XCTAssertEqual(asset(.moto, "Bajaj", "Boxer BM 150"), "VehiclePhotoBajajBoxer")
        XCTAssertEqual(asset(.moto, "TVS", "Apache RTR 200"), "VehiclePhotoTVSApache")
        XCTAssertEqual(asset(.moto, "Honda", "CG 125"), "VehiclePhotoHondaCG125")
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
    }

    func testAllCatalogEntriesPointToBundledAssets() {
        let catalogedNames = VehiclePhotoCatalog.catalogedAssetNames()
        for assetName in catalogedNames {
            XCTAssertNotNil(UIImage(named: assetName), "Asset manquant: \(assetName)")
        }
    }

    private func asset(_ type: VehicleType, _ brand: String, _ model: String) -> String? {
        VehiclePhotoCatalog.resolve(vehicleType: type, brand: brand, model: model)?.assetName
    }
}

final class BurkinaPhoneNumberTests: XCTestCase {
    func testNormalizesCommonBurkinaFormats() {
        XCTAssertEqual(BurkinaPhoneNumber.normalized("+226 70 00 00 00"), "+22670000000")
        XCTAssertEqual(BurkinaPhoneNumber.normalized("22670000000"), "+22670000000")
        XCTAssertEqual(BurkinaPhoneNumber.normalized("0022670000000"), "+22670000000")
        XCTAssertEqual(BurkinaPhoneNumber.normalized("70 00 00 00"), "+22670000000")
    }

    func testRejectsForeignOrIncompleteNumbers() {
        XCTAssertNil(BurkinaPhoneNumber.normalized("+2250700000000"))
        XCTAssertNil(BurkinaPhoneNumber.normalized("+2267000"))
        XCTAssertNil(BurkinaPhoneNumber.normalized(""))
    }

    func testEmergencyContactNormalizesNameAndPhone() {
        let contact = EmergencyContact(name: "  Contact famille  ", phoneNumber: "+226 70 00 00 00")

        XCTAssertEqual(contact.normalizedForBurkina?.name, "Contact famille")
        XCTAssertEqual(contact.normalizedForBurkina?.phoneNumber, "+22670000000")
    }
}
