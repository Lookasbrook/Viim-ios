import Foundation

struct VehiclePhotoResolution: Equatable {
    let assetName: String
    let canonicalName: String
}

enum VehiclePhotoCatalog {
    private static let entries: [VehiclePhotoEntry] = [
        .init(vehicleType: .voiture, brandKeys: ["toyota"], modelKeys: ["prado", "landcruiserprado"], assetName: "VehiclePhotoToyotaPrado", canonicalName: "Toyota Land Cruiser Prado"),
        .init(vehicleType: .voiture, brandKeys: ["toyota"], modelKeys: ["landcruiser", "landcruiser70"], assetName: "VehiclePhotoToyotaLandCruiser", canonicalName: "Toyota Land Cruiser"),
        .init(vehicleType: .voiture, brandKeys: ["toyota"], modelKeys: ["corolla", "corollaaltis", "altis"], assetName: "VehiclePhotoToyotaCorolla", canonicalName: "Toyota Corolla"),
        .init(vehicleType: .voiture, brandKeys: ["toyota"], modelKeys: ["hilux", "hiluxgr", "hiluxe"], assetName: "VehiclePhotoToyotaHilux", canonicalName: "Toyota Hilux"),
        .init(vehicleType: .voiture, brandKeys: ["toyota"], modelKeys: ["rav4", "rav"], assetName: "VehiclePhotoToyotaRAV4", canonicalName: "Toyota RAV4"),
        .init(vehicleType: .moto, brandKeys: ["yamaha"], modelKeys: ["crypton", "t110c"], assetName: "VehiclePhotoYamahaCrypton", canonicalName: "Yamaha Crypton"),
        .init(vehicleType: .moto, brandKeys: ["yamaha"], modelKeys: ["ybr", "ybr125"], assetName: "VehiclePhotoYamahaYBR", canonicalName: "Yamaha YBR 125"),
        .init(vehicleType: .moto, brandKeys: ["bajaj"], modelKeys: ["boxer", "boxerbm150", "bm150"], assetName: "VehiclePhotoBajajBoxer", canonicalName: "Bajaj Boxer"),
        .init(vehicleType: .moto, brandKeys: ["tvs"], modelKeys: ["apache", "rtr", "rtr180", "rtr200"], assetName: "VehiclePhotoTVSApache", canonicalName: "TVS Apache"),
        .init(vehicleType: .moto, brandKeys: ["honda"], modelKeys: ["cg125", "cg"], assetName: "VehiclePhotoHondaCG125", canonicalName: "Honda CG125")
    ]

    static func resolve(for profile: UserProfile?) -> VehiclePhotoResolution? {
        guard let profile else {
            return nil
        }

        return resolve(
            vehicleType: profile.vehicleType,
            brand: profile.vehicleBrand,
            model: profile.vehicleModel
        )
    }

    static func resolve(vehicleType: VehicleType, brand: String, model: String) -> VehiclePhotoResolution? {
        let normalizedBrand = normalize(brand)
        let normalizedModel = normalize(model)
        let combined = normalizedBrand + normalizedModel

        guard !combined.isEmpty else {
            return nil
        }

        return entries.first { entry in
            entry.vehicleType == vehicleType &&
                entry.matches(brand: normalizedBrand, model: normalizedModel, combined: combined)
        }
        .map { VehiclePhotoResolution(assetName: $0.assetName, canonicalName: $0.canonicalName) }
    }

    static func catalogedAssetNames() -> Set<String> {
        Set(entries.map(\.assetName))
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

    func matches(brand: String, model: String, combined: String) -> Bool {
        let brandMatches = brand.isEmpty || brandKeys.contains { key in
            brand.contains(key) || model.contains(key)
        }
        let modelMatches = modelKeys.contains { key in
            model.contains(key) || combined.contains(key)
        }
        return brandMatches && modelMatches
    }
}
