import Foundation

struct VehiclePhotoResolution: Equatable {
    let assetName: String
    let canonicalName: String
    let attribution: VehiclePhotoAttribution
}

enum VehiclePhotoCreationMethod: String, Equatable {
    /// Photographie d'un vehicule reel, publiee par son auteur. Aucune image
    /// generee ou completee par IA n'est admise dans ce catalogue.
    case photograph
}

enum VehiclePhotoLicense: String, Equatable {
    case ccBy40
    case ccBySA40
    case ccBySA30DE
    case cc0
    case publicDomain

    var displayName: String {
        switch self {
        case .ccBy40: "CC BY 4.0"
        case .ccBySA40: "CC BY-SA 4.0"
        case .ccBySA30DE: "CC BY-SA 3.0 DE"
        case .cc0: "CC0 1.0"
        case .publicDomain: "Domaine public"
        }
    }

    var url: URL {
        switch self {
        case .ccBy40:
            URL(string: "https://creativecommons.org/licenses/by/4.0/")!
        case .ccBySA40:
            URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!
        case .ccBySA30DE:
            URL(string: "https://creativecommons.org/licenses/by-sa/3.0/de/")!
        case .cc0:
            URL(string: "https://creativecommons.org/publicdomain/zero/1.0/")!
        case .publicDomain:
            URL(string: "https://commons.wikimedia.org/wiki/Commons:Copyright_tags#Public_domain")!
        }
    }
}

struct VehiclePhotoAttribution: Equatable {
    let assetName: String
    let author: String
    let sourceURL: URL
    let license: VehiclePhotoLicense
    /// SHA-1 de la revision source retournee par l'API Wikimedia lors du
    /// controle. L'image embarquee est une copie redimensionnee.
    let sourceRevisionSHA1: String
    let verifiedAt: Date
    let modifications: String
    let creationMethod: VehiclePhotoCreationMethod

    var isEligibleForDisplay: Bool {
        let trimmedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModifications = modifications.trimmingCharacters(in: .whitespacesAndNewlines)
        return !assetName.isEmpty &&
            !trimmedAuthor.isEmpty &&
            sourceURL.scheme?.lowercased() == "https" &&
            sourceURL.host?.lowercased() == "commons.wikimedia.org" &&
            sourceURL.path.hasPrefix("/wiki/File:") &&
            license.url.scheme?.lowercased() == "https" &&
            sourceRevisionSHA1.count == 40 &&
            sourceRevisionSHA1.allSatisfy(\.isHexDigit) &&
            verifiedAt <= Date() &&
            !trimmedModifications.isEmpty &&
            creationMethod == .photograph
    }
}

enum VehiclePhotoCatalog {
    private static let verifiedAt = Date(timeIntervalSince1970: 1_788_408_000)
    private static let modifications = "Resized to maximum 1200 px; no generative modification."

    private static let entries: [VehiclePhotoEntry] = [
        photo(.voiture, ["toyota"], ["prado", "landcruiserprado"], "VehiclePhotoToyotaPrado", "Toyota Land Cruiser Prado", "Self-Proclaimed-Car-Enthusiast", "https://commons.wikimedia.org/wiki/File:2013-2017_Toyota_Land_Cruiser_Prado_(front).jpg", .ccBySA40, "bc05eb5dabfa5e2510b0b072311d4591f7b52bda"),
        photo(.voiture, ["toyota"], ["landcruiser70"], "VehiclePhotoToyotaLandCruiser", "Toyota Land Cruiser 70", "TTTNIS", "https://commons.wikimedia.org/wiki/File:2023_Toyota_Land_Cruiser_70_front_left.jpg", .cc0, "ae0bfb7fd6b3b033bae0fc238f097687c355d5cb"),
        photo(.voiture, ["toyota"], ["corolla", "corollaaltis", "altis"], "VehiclePhotoToyotaCorolla", "Toyota Corolla Altis", "Poramin", "https://commons.wikimedia.org/wiki/File:Toyota_Corolla_Altis_Front_27082022.jpg", .ccBySA40, "179b674915813b1628d4851a15b31ce214077e8d"),
        photo(.voiture, ["toyota"], ["hilux", "hiluxe"], "VehiclePhotoToyotaHilux", "Toyota Hilux E", "Ethan Llamas", "https://commons.wikimedia.org/wiki/File:2020_Toyota_Hilux_E_(front_left_side_view).jpg", .ccBySA40, "f56e0cdf570e768817183670166710d6ef94b29a"),
        photo(.voiture, ["toyota"], ["rav4"], "VehiclePhotoToyotaRAV4", "Toyota RAV4 (5e generation)", "Wh.0414.justin", "https://commons.wikimedia.org/wiki/File:Toyota_RAV4_(5th_Gen.)_front_look.jpg", .ccBySA40, "1368557d6ae29286610ef0de997253ae4216af08"),
        photo(.voiture, ["toyota"], ["yaris"], "VehiclePhotoToyotaYaris", "Toyota Yaris 2020-2024", "TTTNIS", "https://commons.wikimedia.org/wiki/File:2020-2024_Toyota_Yaris.jpg", .cc0, "22568d1b34d87bb6f4917653faeae26ce457b7bf"),
        photo(.voiture, ["renault"], ["duster"], "VehiclePhotoRenaultDuster", "Renault Duster", "Retired electrician", "https://commons.wikimedia.org/wiki/File:Moscow,_Renault_Duster_Aug_2025_01.jpg", .cc0, "3c5ebaa64d8b2fa31b340c0e5cd59c26122cde06"),
        photo(.voiture, ["kia"], ["picanto"], "VehiclePhotoKiaPicanto", "Kia Picanto III", "M 93", "https://commons.wikimedia.org/wiki/File:Kia_Picanto_GT_Line_(III)_%E2%80%93_f_01062025.jpg", .ccBySA30DE, "3bd5924e1b16187cfdce45536c79f46995f8215a"),
        photo(.voiture, ["nissan"], ["navara"], "VehiclePhotoNissanNavara", "Nissan Navara 2025", "Captainmorlypogi1959", "https://commons.wikimedia.org/wiki/File:Nissan_Navara_4x2_VE_2025_(3).jpg", .ccBySA40, "069c0d7fc63c1a5aebd6056b1024d071554cbf9f"),
        photo(.moto, ["yamaha"], ["crypton", "t110c"], "VehiclePhotoYamahaCrypton", "Yamaha Crypton", "Thigre", "https://commons.wikimedia.org/wiki/File:Crypton.jpg", .ccBySA40, "342d89697a5c646da958bbc1f9c530cdfb14bb45"),
        photo(.moto, ["yamaha"], ["ybr125"], "VehiclePhotoYamahaYBR", "Yamaha YBR 125", "Kyrylo Danylchenko", "https://commons.wikimedia.org/wiki/File:Yamaha_YBR-125_Kiev1.JPG", .publicDomain, "f4d12aa7747d740a730f02e88f599fc502ddb657"),
        photo(.moto, ["yamaha"], ["fzs", "fzs150"], "VehiclePhotoYamahaFZS", "Yamaha FZ-S", "Rosinisubramani", "https://commons.wikimedia.org/wiki/File:Fz_bike.jpg", .ccBySA40, "80cd6d19c258d5fbfb0406c8b26bfa2de0541fb7"),
        photo(.moto, ["bajaj"], ["boxerbm150", "bm150"], "VehiclePhotoBajajBoxer", "Bajaj Boxer BM 150", "Axxter99", "https://commons.wikimedia.org/wiki/File:Bajaj_Boxer_BM_150.jpg", .ccBySA40, "dc63ad7ca23684c4972fcc547403500b4ac30778"),
        photo(.moto, ["tvs"], ["apachertr200", "rtr200"], "VehiclePhotoTVSApache", "TVS Apache RTR 200 4V", "OffPoynt", "https://commons.wikimedia.org/wiki/File:TVS_Apache_RTR_200_4V_Front-Right_Profile.jpg", .ccBySA40, "62dbf9941650902629208910a5fca5335a5732ab"),
        photo(.moto, ["honda"], ["cg125"], "VehiclePhotoHondaCG125", "Honda CG125", "SEDJRO SETONDJI", "https://commons.wikimedia.org/wiki/File:Honda_CG125.jpg", .ccBySA40, "f9e9d9cf1787a69025bfbab5812c001369d76472"),
        photo(.moto, ["honda"], ["cb125", "cb125f"], "VehiclePhotoHondaCB125F", "Honda CB125F", "Hasan HH", "https://commons.wikimedia.org/wiki/File:CB_125_F_in_Pakistan.jpg", .ccBySA40, "13bb77d16dcc72454862c9bb77b9f77fd235723d"),
        photo(.moto, ["honda"], ["wave110"], "VehiclePhotoHondaWave110", "Honda Wave 110 Special Edition 2026", "Chanokchon", "https://commons.wikimedia.org/wiki/File:2026_Honda_Wave_110_Special_Edition_(Alloy_Type).jpg", .ccBySA40, "dad5561136623982ec722eaf1457626c639be6a3", yearRange: 2026...2026),
        photo(.moto, ["suzuki"], ["gn125"], "VehiclePhotoSuzukiGN125", "Suzuki GN 125", "Addvisor", "https://commons.wikimedia.org/wiki/File:Suzuki_GN_125_DSCF0735.JPG", .ccBySA40, "fc8d5a3745392ad267da7972ce031c6d38743efb")
    ]

    private static func photo(
        _ vehicleType: VehicleType,
        _ brandKeys: [String],
        _ modelKeys: [String],
        _ assetName: String,
        _ canonicalName: String,
        _ author: String,
        _ source: String,
        _ license: VehiclePhotoLicense,
        _ sourceRevisionSHA1: String,
        yearRange: ClosedRange<Int>? = nil
    ) -> VehiclePhotoEntry {
        VehiclePhotoEntry(
            vehicleType: vehicleType,
            brandKeys: brandKeys,
            modelKeys: modelKeys,
            assetName: assetName,
            canonicalName: canonicalName,
            yearRange: yearRange,
            attribution: VehiclePhotoAttribution(
                assetName: assetName,
                author: author,
                sourceURL: URL(string: source)!,
                license: license,
                sourceRevisionSHA1: sourceRevisionSHA1,
                verifiedAt: verifiedAt,
                modifications: modifications,
                creationMethod: .photograph
            )
        )
    }

    static func resolve(for profile: UserProfile?) -> VehiclePhotoResolution? {
        guard let profile else {
            return nil
        }

        return resolve(
            vehicleType: profile.vehicleType,
            brand: profile.vehicleBrand,
            model: profile.vehicleModel,
            year: profile.vehicleYear
        )
    }

    static func resolve(
        vehicleType: VehicleType,
        brand: String,
        model: String,
        year: String? = nil
    ) -> VehiclePhotoResolution? {
        let normalizedBrand = normalize(brand)
        let normalizedModel = normalize(model)
        let combined = normalizedBrand + normalizedModel
        let resolvedYear = year.flatMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        guard !combined.isEmpty else {
            return nil
        }

        return entries.first { entry in
            entry.vehicleType == vehicleType &&
                entry.attribution.isEligibleForDisplay &&
                entry.matches(year: resolvedYear) &&
                entry.matches(brand: normalizedBrand, model: normalizedModel, combined: combined)
        }
        .map {
            VehiclePhotoResolution(
                assetName: $0.assetName,
                canonicalName: $0.canonicalName,
                attribution: $0.attribution
            )
        }
    }

    static func catalogedAssetNames() -> Set<String> {
        Set(entries.filter(\.attribution.isEligibleForDisplay).map(\.assetName))
    }

    static func catalogedAttributions() -> [VehiclePhotoAttribution] {
        entries.map(\.attribution).filter(\.isEligibleForDisplay)
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_BF"))
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }
}

private struct VehiclePhotoEntry: Equatable {
    let vehicleType: VehicleType
    let brandKeys: [String]
    let modelKeys: [String]
    let assetName: String
    let canonicalName: String
    let yearRange: ClosedRange<Int>?
    let attribution: VehiclePhotoAttribution

    func matches(year: Int?) -> Bool {
        guard let yearRange else {
            return true
        }
        guard let year else {
            return false
        }
        return yearRange.contains(year)
    }

    func matches(brand: String, model: String, combined: String) -> Bool {
        let brandMatches = brand.isEmpty || brandKeys.contains(brand)
        let modelMatches = modelKeys.contains(model) || brandKeys.contains { brandKey in
            modelKeys.contains { modelKey in
                combined == brandKey + modelKey || model == brandKey + modelKey
            }
        }
        return brandMatches && modelMatches
    }
}
