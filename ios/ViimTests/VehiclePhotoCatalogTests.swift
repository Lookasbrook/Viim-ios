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
        XCTAssertEqual(asset(.moto, "Yamaha", "XTZ 125"), "VehiclePhotoYamahaXTZ125")
        XCTAssertEqual(asset(.moto, "Yamaha", "FZ-S 150"), "VehiclePhotoYamahaFZS")
        XCTAssertEqual(asset(.moto, "Honda", "CB125F"), "VehiclePhotoHondaCB125F")
        XCTAssertEqual(asset(.moto, "Bajaj", "Boxer BM 150"), "VehiclePhotoBajajBoxer")
        XCTAssertEqual(asset(.moto, "TVS", "Apache RTR 200"), "VehiclePhotoTVSApache")
        XCTAssertEqual(asset(.moto, "Honda", "CG 125"), "VehiclePhotoHondaCG125")
        XCTAssertEqual(asset(.moto, "Suzuki", "GN 125"), "VehiclePhotoSuzukiGN125")
        XCTAssertEqual(asset(.moto, "Suzuki", "Gixxer 155"), "VehiclePhotoSuzukiGixxer155")
        XCTAssertEqual(asset(.moto, "Bajaj", "Pulsar 150"), "VehiclePhotoBajajPulsar150")
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

    func testRecentCarGenerationsResolveOnlyInsideTheirVerifiedYearRange() {
        let cases: [(brand: String, model: String, year: String, assetName: String)] = [
            ("Toyota", "Fortuner", "2018", "VehiclePhotoToyotaFortuner"),
            ("Nissan", "X-Trail", "2024", "VehiclePhotoNissanXTrail"),
            ("Hyundai", "Tucson", "2025", "VehiclePhotoHyundaiTucson"),
            ("Kia", "Sportage", "2023", "VehiclePhotoKiaSportage")
        ]

        for item in cases {
            XCTAssertEqual(
                VehiclePhotoCatalog.resolve(
                    vehicleType: .voiture,
                    brand: item.brand,
                    model: item.model,
                    year: item.year
                )?.assetName,
                item.assetName
            )
            XCTAssertNil(
                VehiclePhotoCatalog.resolve(
                    vehicleType: .voiture,
                    brand: item.brand,
                    model: item.model
                ),
                "Une photo de generation ne doit pas etre affichee sans annee."
            )
        }

        XCTAssertNil(VehiclePhotoCatalog.resolve(vehicleType: .voiture, brand: "Toyota", model: "Fortuner", year: "2015"))
        XCTAssertNil(VehiclePhotoCatalog.resolve(vehicleType: .voiture, brand: "Nissan", model: "X-Trail", year: "2021"))
        XCTAssertNil(VehiclePhotoCatalog.resolve(vehicleType: .voiture, brand: "Hyundai", model: "Tucson", year: "2020"))
        XCTAssertNil(VehiclePhotoCatalog.resolve(vehicleType: .voiture, brand: "Kia", model: "Sportage", year: "2021"))
    }

    func testToyotaCorollaResolvesToItsGenerationByYear() {
        // Vehicule reel de l'utilisateur (profil appareil 2026-09-09) :
        // Toyota / "Corolla Le" / 2015 -> E170, pas l'Altis E210 de 2022.
        XCTAssertEqual(
            VehiclePhotoCatalog.resolve(
                vehicleType: .voiture,
                brand: "Toyota",
                model: "Corolla Le",
                year: "2015"
            )?.assetName,
            "VehiclePhotoToyotaCorollaE170"
        )

        for year in ["2014", "2017", "2019"] {
            XCTAssertEqual(
                VehiclePhotoCatalog.resolve(vehicleType: .voiture, brand: "Toyota", model: "Corolla", year: year)?.assetName,
                "VehiclePhotoToyotaCorollaE170",
                "Corolla \(year) doit resoudre vers la generation E170."
            )
        }

        // Hors de la plage E170 : repli sur l'entree Corolla generique (Altis).
        XCTAssertEqual(
            VehiclePhotoCatalog.resolve(vehicleType: .voiture, brand: "Toyota", model: "Corolla", year: "2022")?.assetName,
            "VehiclePhotoToyotaCorolla"
        )
        // Sans annee, aucune photo de generation : comportement inchange.
        XCTAssertEqual(
            VehiclePhotoCatalog.resolve(vehicleType: .voiture, brand: "Toyota", model: "Corolla")?.assetName,
            "VehiclePhotoToyotaCorolla"
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
        XCTAssertNil(VehiclePhotoCatalog.resolve(vehicleType: .moto, brand: "Yamaha", model: "XTZ"))
        XCTAssertNil(VehiclePhotoCatalog.resolve(vehicleType: .moto, brand: "Suzuki", model: "Gixxer"))
        XCTAssertNil(VehiclePhotoCatalog.resolve(vehicleType: .moto, brand: "Bajaj", model: "Pulsar"))
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

    // MARK: - Garde anti-regression de couverture (incident 2026-09-09)

    /// Chaque combinaison ici est un vehicule que Viim s'engage a illustrer
    /// avec une vraie photo. Retirer un alias canonique ou renommer un asset
    /// casse ce test AVANT qu'un utilisateur ne voie sa carte retomber sur la
    /// silhouette generique sans que rien ne l'ait signale.
    private static let guaranteedCoverage: [(type: VehicleType, brand: String, model: String, year: String?)] = [
        (.voiture, "Toyota", "Land Cruiser Prado", nil),
        (.voiture, "Toyota", "Land Cruiser 70", nil),
        (.voiture, "Toyota", "Corolla", nil),
        (.voiture, "Toyota", "Corolla Altis", nil),
        (.voiture, "Toyota", "Corolla Le", "2015"),
        (.voiture, "Toyota", "Corolla", "2016"),
        (.voiture, "Toyota", "Hilux", nil),
        (.voiture, "Toyota", "RAV4", nil),
        (.voiture, "Toyota", "Yaris", nil),
        (.voiture, "Toyota", "Fortuner", "2019"),
        (.voiture, "Nissan", "X-Trail", "2023"),
        (.voiture, "Nissan", "Navara", nil),
        (.voiture, "Hyundai", "Tucson", "2022"),
        (.voiture, "Kia", "Sportage", "2023"),
        (.voiture, "Kia", "Picanto", nil),
        (.voiture, "Renault", "Duster", nil),
        (.moto, "Yamaha", "Crypton", nil),
        (.moto, "Yamaha", "YBR 125", nil),
        (.moto, "Yamaha", "XTZ 125", nil),
        (.moto, "Yamaha", "FZ-S", nil),
        (.moto, "Bajaj", "Boxer BM 150", nil),
        (.moto, "Bajaj", "Pulsar 150", nil),
        (.moto, "TVS", "Apache RTR 200", nil),
        (.moto, "Honda", "CG 125", nil),
        (.moto, "Honda", "CB125F", nil),
        (.moto, "Honda", "Wave 110", "2026"),
        (.moto, "Suzuki", "GN 125", nil),
        (.moto, "Suzuki", "Gixxer 155", nil)
    ]

    /// Vehicules courants (notamment au Burkina Faso) pour lesquels aucune photo
    /// verifiee n'est encore embarquee. Ils DOIVENT resoudre a `nil` : afficher
    /// une generation voisine serait une donnee fausse. Quand une photo Commons
    /// licite est ajoutee, deplacer la ligne vers `guaranteedCoverage`.
    private static let knownPhotoGaps: [(type: VehicleType, brand: String, model: String)] = [
        (.voiture, "Toyota", "Land Cruiser"),
        (.voiture, "Toyota", "Land Cruiser 200"),
        (.voiture, "Toyota", "Land Cruiser 100"),
        (.moto, "Yamaha", "FZ 150"),
        (.voiture, "Mercedes", "Classe C"),
        (.voiture, "Peugeot", "206")
    ]

    func testGuaranteedCoverageVehiclesAlwaysResolveToAnEligiblePhoto() {
        for item in Self.guaranteedCoverage {
            let resolution = VehiclePhotoCatalog.resolve(
                vehicleType: item.type,
                brand: item.brand,
                model: item.model,
                year: item.year
            )
            XCTAssertNotNil(
                resolution,
                "Couverture perdue pour \(item.brand) \(item.model): la carte vehicule retombera sur la silhouette."
            )
            XCTAssertTrue(
                resolution?.attribution.isEligibleForDisplay ?? false,
                "Attribution incomplete pour \(item.brand) \(item.model)."
            )
            XCTAssertEqual(resolution?.assetName, resolution?.attribution.assetName)
        }
    }

    func testKnownPhotoGapsStayNilUntilAVerifiedPhotoIsAdded() {
        for item in Self.knownPhotoGaps {
            XCTAssertNil(
                VehiclePhotoCatalog.resolve(
                    vehicleType: item.type,
                    brand: item.brand,
                    model: item.model
                ),
                "\(item.brand) \(item.model) a une photo maintenant: le retirer de knownPhotoGaps et l'ajouter a guaranteedCoverage."
            )
        }
    }

    private func asset(_ type: VehicleType, _ brand: String, _ model: String) -> String? {
        VehiclePhotoCatalog.resolve(vehicleType: type, brand: brand, model: model)?.assetName
    }
}
