import Foundation

struct VehicleFuelProfile: Equatable {
    let vehicleType: VehicleType
    let canonicalName: String
    let litersPer100Km: Double
    let confidence: MetricConfidence
    let sourceIdentifier: String
}

struct FuelConsumptionEstimate: Equatable {
    let liters: Double
    let confidence: MetricConfidence
}

struct VehicleCatalogSuggestion: Equatable, Identifiable {
    let vehicleType: VehicleType
    let brand: String
    let model: String
    let canonicalName: String
    let litersPer100Km: Double

    var id: String {
        "\(vehicleType.rawValue)-\(brand)-\(model)"
    }
}

enum VehicleFuelCatalog {
    static let formulaVersion = "vehicle-fuel-catalog-v7-static-base"
    static let sourceIdentifier = "ViimCatalog.indicative.v7"

    private static let entries: [VehicleFuelEntry] = [
        car("Toyota", "Corolla", ["corolla", "corollaaltis", "altis"], 6.8, rank: 10),
        car("Toyota", "Yaris", ["yaris", "vitz", "yarissedan"], 5.8, rank: 11),
        car("Toyota", "Camry", ["camry"], 8.2, rank: 24),
        car("Toyota", "Avensis", ["avensis"], 7.4, rank: 38),
        car("Toyota", "RAV4", ["rav4", "rav"], 8.2, rank: 14),
        car("Toyota", "Highlander", ["highlander"], 9.5, rank: 52),
        car("Toyota", "Hilux", ["hilux", "hiluxgr", "hiluxe"], 9.0, rank: 12),
        car("Toyota", "Fortuner", ["fortuner"], 9.3, rank: 18),
        car("Toyota", "Land Cruiser Prado", ["prado", "landcruiserprado"], 11.5, rank: 13),
        car("Toyota", "Land Cruiser", ["landcruiser", "landcruiser70", "lc70", "lc200"], 13.0, rank: 16),
        car("Toyota", "Hiace", ["hiace"], 10.0, rank: 22),

        car("Nissan", "March", ["march", "micra"], 5.7, rank: 44),
        car("Nissan", "Sunny", ["sunny", "almera", "versa"], 6.4, rank: 23),
        car("Nissan", "Qashqai", ["qashqai", "dualis"], 6.9, rank: 51),
        car("Nissan", "X-Trail", ["xtrail", "xtrailt30", "xtrailt31", "xtrailt32"], 8.0, rank: 27),
        car("Nissan", "Navara", ["navara", "frontier"], 8.5, rank: 29),
        car("Nissan", "Patrol", ["patrol"], 13.5, rank: 53),

        car("Hyundai", "i10", ["i10", "grand i10", "grandi10"], 5.2, rank: 20),
        car("Hyundai", "Accent", ["accent", "verna"], 6.2, rank: 19),
        car("Hyundai", "Elantra", ["elantra"], 6.8, rank: 30),
        car("Hyundai", "Tucson", ["tucson", "ix35"], 8.0, rank: 21),
        car("Hyundai", "Santa Fe", ["santafe"], 8.7, rank: 45),

        car("Kia", "Picanto", ["picanto", "morning"], 5.3, rank: 26),
        car("Kia", "Rio", ["rio"], 6.0, rank: 25),
        car("Kia", "Cerato", ["cerato", "forte"], 6.8, rank: 40),
        car("Kia", "Sportage", ["sportage"], 8.0, rank: 28),
        car("Kia", "Sorento", ["sorento"], 8.8, rank: 54),

        car("Mitsubishi", "L200", ["l200", "triton"], 8.7, rank: 32),
        car("Mitsubishi", "Pajero", ["pajero", "montero"], 10.8, rank: 41),
        car("Mitsubishi", "Outlander", ["outlander"], 7.9, rank: 57),

        car("Suzuki", "Alto", ["alto"], 4.8, rank: 34),
        car("Suzuki", "Swift", ["swift"], 5.6, rank: 35),
        car("Suzuki", "Vitara", ["vitara", "grandvitara"], 6.8, rank: 46),
        car("Suzuki", "Jimny", ["jimny"], 7.2, rank: 58),

        car("Honda", "Civic", ["civic"], 6.7, rank: 42),
        car("Honda", "Accord", ["accord"], 8.0, rank: 50),
        car("Honda", "CR-V", ["crv", "cr-v"], 7.8, rank: 43),

        car("Peugeot", "206", ["206"], 6.3, rank: 31),
        car("Peugeot", "207", ["207"], 6.5, rank: 39),
        car("Peugeot", "307", ["307"], 7.2, rank: 33),
        car("Peugeot", "308", ["308"], 6.8, rank: 56),
        car("Peugeot", "405", ["405"], 8.0, rank: 48),
        car("Peugeot", "406", ["406"], 8.4, rank: 49),
        car("Peugeot", "Partner", ["partner"], 7.0, rank: 55),

        car("Renault", "Clio", ["clio"], 5.9, rank: 60),
        car("Renault", "Logan", ["logan"], 6.4, rank: 36, brandKeys: ["renault", "dacia"]),
        car("Renault", "Sandero", ["sandero"], 6.2, rank: 37, brandKeys: ["renault", "dacia"]),
        car("Renault", "Duster", ["duster"], 7.2, rank: 17, brandKeys: ["renault", "dacia"]),
        car("Renault", "Kangoo", ["kangoo"], 6.8, rank: 61),

        car("Volkswagen", "Polo", ["polo"], 5.8, rank: 47, brandKeys: ["volkswagen", "vw"]),
        car("Volkswagen", "Golf", ["golf"], 6.5, rank: 62, brandKeys: ["volkswagen", "vw"]),
        car("Volkswagen", "Passat", ["passat"], 7.2, rank: 63, brandKeys: ["volkswagen", "vw"]),
        car("Volkswagen", "Tiguan", ["tiguan"], 7.8, rank: 64, brandKeys: ["volkswagen", "vw"]),

        car("Mercedes-Benz", "Classe C", ["classec", "classc", "cclass", "c200", "c220"], 7.5, rank: 65, brandKeys: ["mercedes", "mercedesbenz", "benz"]),
        car("Mercedes-Benz", "Classe E", ["classee", "classee", "classe-e", "eclass", "e200", "e220"], 8.5, rank: 66, brandKeys: ["mercedes", "mercedesbenz", "benz"]),

        car("Ford", "Focus", ["focus"], 6.8, rank: 67),
        car("Ford", "Escape", ["escape"], 8.3, rank: 68),
        car("Ford", "Ranger", ["ranger"], 8.9, rank: 15),

        car("Mazda", "3", ["mazda3", "3"], 6.7, rank: 69),
        car("Mazda", "CX-5", ["cx5", "cx-5"], 7.5, rank: 70),
        car("Mazda", "BT-50", ["bt50", "bt-50"], 8.8, rank: 71),

        car("Chevrolet", "Spark", ["spark"], 5.5, rank: 72),
        car("Chevrolet", "Aveo", ["aveo"], 6.5, rank: 73),
        car("Opel", "Corsa", ["corsa"], 5.8, rank: 74),
        car("Opel", "Astra", ["astra"], 6.7, rank: 75),

        moto("Yamaha", "Crypton", ["crypton", "t110c"], 2.0, rank: 10),
        moto("Yamaha", "YBR 125", ["ybr", "ybr125"], 2.4, rank: 13),
        moto("Yamaha", "Libero 125", ["libero", "libero125"], 2.2, rank: 26),
        moto("Yamaha", "XTZ 125", ["xtz", "xtz125"], 2.8, rank: 27),
        moto("Yamaha", "FZ 150", ["fz", "fz150", "fzs", "fz-s"], 2.7, rank: 33),

        moto("Bajaj", "Boxer", ["boxer"], 2.2, rank: 11),
        moto("Bajaj", "Boxer BM 100", ["boxer100", "bm100"], 1.8, rank: 12),
        moto("Bajaj", "Boxer BM 125", ["boxer125", "bm125"], 2.0, rank: 14),
        moto("Bajaj", "Boxer BM 150", ["boxer150", "boxerbm150", "bm150"], 2.2, rank: 15),
        moto("Bajaj", "Pulsar 150", ["pulsar", "pulsar150"], 2.5, rank: 24),
        moto("Bajaj", "Pulsar NS 200", ["pulsarns200", "ns200"], 3.0, rank: 38),
        moto("Bajaj", "Discover 125", ["discover", "discover125"], 2.1, rank: 25),
        moto("Bajaj", "Platina 100", ["platina", "platina100"], 1.8, rank: 28),
        moto("Bajaj", "CT 100", ["ct100"], 1.7, rank: 29),
        moto("Bajaj", "CT 110", ["ct110"], 1.8, rank: 30),

        moto("TVS", "HLX 125", ["hlx", "hlx125", "starhlx"], 2.0, rank: 15),
        moto("TVS", "HLX 150", ["hlx150"], 2.2, rank: 16),
        moto("TVS", "Apache RTR 160", ["apache", "rtr", "rtr160", "apache160"], 2.7, rank: 21),
        moto("TVS", "Apache RTR 200", ["rtr200", "apache200"], 3.0, rank: 39),
        moto("TVS", "Star City Plus", ["starcity", "starcityplus"], 1.9, rank: 37),

        moto("Honda", "CG 125", ["cg125", "cg"], 2.3, rank: 17),
        moto("Honda", "CB 125F", ["cb125", "cb125f"], 2.1, rank: 31),
        moto("Honda", "Ace 110", ["ace", "ace110"], 1.9, rank: 32),
        moto("Honda", "Wave 110", ["wave", "wave110"], 1.8, rank: 34),
        moto("Honda", "Dream 110", ["dream", "dream110"], 1.8, rank: 35),
        moto("Honda", "XR 150L", ["xr150", "xr150l"], 2.7, rank: 45),

        moto("Suzuki", "AX 100", ["ax100"], 2.4, rank: 18),
        moto("Suzuki", "GD 110", ["gd110"], 1.9, rank: 36),
        moto("Suzuki", "GN 125", ["gn125"], 2.4, rank: 40),
        moto("Suzuki", "Gixxer 155", ["gixxer", "gixxer155"], 2.8, rank: 48),

        moto("Haojue", "HJ 110", ["hj110"], 1.9, rank: 19),
        moto("Haojue", "HJ 125", ["hj125"], 2.2, rank: 20),
        moto("Haojue", "DK 125", ["dk125"], 2.3, rank: 41),
        moto("Haojue", "KA 150", ["ka150"], 2.5, rank: 49),

        moto("Hero", "HF Deluxe", ["hfdeluxe", "hf"], 1.7, rank: 42),
        moto("Hero", "Splendor", ["splendor", "splendorplus"], 1.8, rank: 43),
        moto("Hero", "Hunk 150", ["hunk", "hunk150"], 2.5, rank: 50),

        moto("Dayun", "DY 100", ["dy100", "dayun100"], 1.9, rank: 22),
        moto("Dayun", "DY 125", ["dy125", "dayun125"], 2.2, rank: 23),
        moto("Dayun", "DY 150", ["dy150", "dayun150"], 2.5, rank: 46),

        moto("Sanili", "SL 125", ["sl125", "sanili125"], 2.2, rank: 44),
        moto("Sanili", "SL 150", ["sl150", "sanili150"], 2.5, rank: 51),
        moto("Apsonic", "AP 125", ["ap125", "apsonic125"], 2.2, rank: 47),
        moto("Apsonic", "AP 150", ["ap150", "apsonic150"], 2.5, rank: 52),
        moto("Lifan", "LF 125", ["lf125", "lifan125"], 2.2, rank: 53),
        moto("Lifan", "LF 150", ["lf150", "lifan150"], 2.5, rank: 54),
        moto("Jincheng", "JC 110", ["jc110", "jincheng110"], 1.9, rank: 55),
        moto("Jincheng", "JC 125", ["jc125", "jincheng125"], 2.2, rank: 56),
        moto("Sonlink", "SL 125", ["sonlink125"], 2.2, rank: 57),
        moto("Sonlink", "SL 150", ["sonlink150"], 2.5, rank: 58),
        moto("Kymco", "Agility 125", ["agility", "agility125"], 2.6, rank: 59)
    ]

    static func profile(for userProfile: UserProfile?) -> VehicleFuelProfile? {
        guard let userProfile else {
            return nil
        }

        return profile(
            vehicleType: userProfile.vehicleType,
            brand: userProfile.vehicleBrand,
            model: userProfile.vehicleModel
        )
    }

    static func profile(vehicleType: VehicleType, brand: String, model: String) -> VehicleFuelProfile? {
        guard vehicleType != .velo else {
            return VehicleFuelProfile(
                vehicleType: vehicleType,
                canonicalName: String(localized: "vehicle.type.velo"),
                litersPer100Km: 0,
                confidence: .reliable,
                sourceIdentifier: sourceIdentifier
            )
        }

        guard let entry = resolvedEntry(vehicleType: vehicleType, brand: brand, model: model) else {
            return nil
        }

        return VehicleFuelProfile(
            vehicleType: vehicleType,
            canonicalName: entry.canonicalName,
            litersPer100Km: entry.litersPer100Km,
            confidence: .partial,
            sourceIdentifier: sourceIdentifier
        )
    }

    static func canonicalSuggestion(
        vehicleType: VehicleType,
        brand: String,
        model: String
    ) -> VehicleCatalogSuggestion? {
        guard vehicleType != .velo,
              hasEnoughModelSignal(brand: brand, model: model),
              let entry = resolvedEntry(vehicleType: vehicleType, brand: brand, model: model) else {
            return nil
        }

        return suggestion(for: entry)
    }

    static func suggestions(
        vehicleType: VehicleType,
        query: String,
        limit: Int = 6
    ) -> [VehicleCatalogSuggestion] {
        guard vehicleType != .velo, limit > 0 else {
            return []
        }

        return rankedEntries(vehicleType: vehicleType, brand: query, model: "")
            .prefix(limit)
            .map { suggestion(for: $0.entry) }
    }

    static func estimateConsumption(
        distanceKm: Double,
        fuelProfile: VehicleFuelProfile?,
        dynamics: DrivingDynamics? = nil
    ) -> FuelConsumptionEstimate? {
        guard let fuelProfile,
              distanceKm.isFinite,
              distanceKm >= 0 else {
            return nil
        }

        // La valeur financiere reste strictement la distance GPS validee x
        // consommation indicative du catalogue. La dynamique GPS n'est pas
        // une mesure de carburant et ne doit pas modifier un montant tant
        // qu'elle n'a pas ete calibree contre des pleins ou un capteur moteur.
        let baseLiters = distanceKm * fuelProfile.litersPer100Km / 100

        return FuelConsumptionEstimate(
            liters: baseLiters,
            confidence: fuelProfile.confidence
        )
    }

    private static func resolvedEntry(vehicleType: VehicleType, brand: String, model: String) -> VehicleFuelEntry? {
        let normalizedBrand = normalize(brand)
        let normalizedModel = normalize(model)
        let combined = normalizedBrand + normalizedModel
        guard !combined.isEmpty else {
            return nil
        }

        return entries.first(where: { entry in
            entry.vehicleType == vehicleType &&
                entry.matches(brand: normalizedBrand, model: normalizedModel, combined: combined)
        })
    }

    private static func rankedEntries(vehicleType: VehicleType, brand: String, model: String) -> [(entry: VehicleFuelEntry, score: Int)] {
        let query = [brand, model]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let normalizedQuery = normalize(query)
        let queryTokens = tokens(from: query)

        return entries.compactMap { entry -> (entry: VehicleFuelEntry, score: Int)? in
            guard entry.vehicleType == vehicleType else {
                return nil
            }

            guard !normalizedQuery.isEmpty else {
                return (entry, 1_000 + entry.rank)
            }

            let canonical = normalize(entry.canonicalName)
            let canonicalBrand = normalize(entry.canonicalBrand)
            let canonicalModel = normalize(entry.canonicalModel)
            if canonical == normalizedQuery {
                return (entry, entry.rank)
            }
            if canonical.hasPrefix(normalizedQuery) || canonical.contains(normalizedQuery) {
                return (entry, 20 + entry.rank)
            }

            let candidateTokens = entry.searchTokens
            var tokenScore = 0
            for token in queryTokens {
                guard let bestTokenScore = candidateTokens.compactMap({ score(token: token, candidate: $0) }).min() else {
                    return nil
                }
                tokenScore += bestTokenScore
            }

            let brandBonus = queryTokens.contains { score(token: $0, candidate: canonicalBrand) != nil } ? -5 : 0
            let modelBonus = queryTokens.contains { score(token: $0, candidate: canonicalModel) != nil } ? -5 : 0
            return (entry, 50 + tokenScore + brandBonus + modelBonus + entry.rank)
        }
        .sorted { left, right in
            if left.score == right.score {
                return left.entry.canonicalName < right.entry.canonicalName
            }
            return left.score < right.score
        }
    }

    private static func suggestion(for entry: VehicleFuelEntry) -> VehicleCatalogSuggestion {
        VehicleCatalogSuggestion(
            vehicleType: entry.vehicleType,
            brand: entry.canonicalBrand,
            model: entry.canonicalModel,
            canonicalName: entry.canonicalName,
            litersPer100Km: entry.litersPer100Km
        )
    }

    private static func hasEnoughModelSignal(brand: String, model: String) -> Bool {
        if !normalize(model).isEmpty {
            return true
        }
        return tokens(from: brand).count >= 2
    }

    private static func score(token: String, candidate: String) -> Int? {
        guard !token.isEmpty, !candidate.isEmpty else {
            return nil
        }
        if candidate == token {
            return 0
        }
        if candidate.hasPrefix(token) || token.hasPrefix(candidate) {
            return 5
        }
        if candidate.contains(token) || token.contains(candidate) {
            return 10
        }

        let threshold: Int
        switch token.count {
        case 0...3:
            threshold = 0
        case 4:
            threshold = 2
        default:
            threshold = 3
        }

        let distance = levenshtein(token, candidate)
        guard distance <= threshold else {
            return nil
        }
        return 25 + distance
    }

    private static func tokens(from value: String) -> [String] {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_BF"))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map(normalize)
            .filter { !$0.isEmpty }
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_BF"))
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    private static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        guard !left.isEmpty else {
            return right.count
        }
        guard !right.isEmpty else {
            return left.count
        }

        var previous = Array(0...right.count)
        var current = Array(repeating: 0, count: right.count + 1)

        for leftIndex in 1...left.count {
            current[0] = leftIndex
            for rightIndex in 1...right.count {
                let substitutionCost = left[leftIndex - 1] == right[rightIndex - 1] ? 0 : 1
                current[rightIndex] = min(
                    previous[rightIndex] + 1,
                    current[rightIndex - 1] + 1,
                    previous[rightIndex - 1] + substitutionCost
                )
            }
            previous = current
        }

        return previous[right.count]
    }

    private static func car(
        _ brand: String,
        _ model: String,
        _ modelKeys: [String],
        _ litersPer100Km: Double,
        rank: Int,
        brandKeys: [String] = []
    ) -> VehicleFuelEntry {
        entry(
            vehicleType: .voiture,
            brand: brand,
            model: model,
            modelKeys: modelKeys,
            litersPer100Km: litersPer100Km,
            rank: rank,
            brandKeys: brandKeys
        )
    }

    private static func moto(
        _ brand: String,
        _ model: String,
        _ modelKeys: [String],
        _ litersPer100Km: Double,
        rank: Int,
        brandKeys: [String] = []
    ) -> VehicleFuelEntry {
        entry(
            vehicleType: .moto,
            brand: brand,
            model: model,
            modelKeys: modelKeys,
            litersPer100Km: litersPer100Km,
            rank: rank,
            brandKeys: brandKeys
        )
    }

    private static func entry(
        vehicleType: VehicleType,
        brand: String,
        model: String,
        modelKeys: [String],
        litersPer100Km: Double,
        rank: Int,
        brandKeys: [String]
    ) -> VehicleFuelEntry {
        let normalizedBrandKeys = ([brand] + brandKeys).map(normalize)
        let normalizedModelKeys = ([model] + modelKeys).map(normalize)
        let searchTokens = Set(tokens(from: "\(brand) \(model)") + normalizedBrandKeys + normalizedModelKeys)

        return VehicleFuelEntry(
            vehicleType: vehicleType,
            canonicalBrand: brand,
            canonicalModel: model,
            brandKeys: Array(Set(normalizedBrandKeys)),
            modelKeys: Array(Set(normalizedModelKeys)),
            litersPer100Km: litersPer100Km,
            rank: rank,
            searchTokens: Array(searchTokens)
        )
    }
}

private struct VehicleFuelEntry: Equatable {
    let vehicleType: VehicleType
    let canonicalBrand: String
    let canonicalModel: String
    let brandKeys: [String]
    let modelKeys: [String]
    let litersPer100Km: Double
    let rank: Int
    let searchTokens: [String]

    var canonicalName: String {
        "\(canonicalBrand) \(canonicalModel)"
    }

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
