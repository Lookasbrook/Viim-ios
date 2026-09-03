import Foundation

enum PublicVehicleCatalogError: Error, Equatable {
    case invalidRequest
    case invalidResponse
    case apiStatus(Int)
    case network(URLError.Code)
    case transport
    case responseTooLarge
    case untrustedResponse
    case identityMismatch
}

struct FuelEconomyVehicleVariant: Codable, Equatable, Identifiable {
    let recordID: String
    let description: String

    var id: String { recordID }

    var isValid: Bool {
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !recordID.isEmpty &&
            recordID.count <= 12 &&
            recordID.allSatisfy(\.isNumber)
    }
}

/// Une fiche technique ne devient « verifiee » que si son identite, ses
/// valeurs et sa provenance officielle passent tous les controles. Le meme
/// controle est refait apres decodage afin qu'un ancien JSON altere ne puisse
/// jamais alimenter silencieusement le calcul carburant.
struct VerifiedVehicleSpecification: Codable, Equatable {
    static let schemaVersion = 1

    let version: Int
    let sourceIdentifier: String
    let sourceRecordID: String
    let sourceURL: URL
    let retrievedAt: Date
    let year: Int
    let make: String
    let model: String
    let variant: String
    let engineDescription: String
    let transmission: String
    let fuelType: VehicleFuelType
    let cityLitersPer100Km: Double
    let highwayLitersPer100Km: Double
    let combinedLitersPer100Km: Double

    init?(
        sourceIdentifier: String,
        sourceRecordID: String,
        sourceURL: URL,
        retrievedAt: Date,
        year: Int,
        make: String,
        model: String,
        variant: String,
        engineDescription: String,
        transmission: String,
        fuelType: VehicleFuelType,
        cityLitersPer100Km: Double,
        highwayLitersPer100Km: Double,
        combinedLitersPer100Km: Double
    ) {
        version = Self.schemaVersion
        self.sourceIdentifier = sourceIdentifier
        self.sourceRecordID = sourceRecordID
        self.sourceURL = sourceURL
        self.retrievedAt = retrievedAt
        self.year = year
        self.make = make
        self.model = model
        self.variant = variant
        self.engineDescription = engineDescription
        self.transmission = transmission
        self.fuelType = fuelType
        self.cityLitersPer100Km = cityLitersPer100Km
        self.highwayLitersPer100Km = highwayLitersPer100Km
        self.combinedLitersPer100Km = combinedLitersPer100Km

        guard hasTrustedEvidence else {
            return nil
        }
    }

    var hasTrustedEvidence: Bool {
        guard version == Self.schemaVersion,
              sourceIdentifier == FuelEconomyVehicleClient.sourceIdentifier,
              sourceRecordID.count <= 12,
              !sourceRecordID.isEmpty,
              sourceRecordID.allSatisfy(\.isNumber),
              sourceURL.scheme?.lowercased() == "https",
              sourceURL.host?.lowercased() == FuelEconomyVehicleClient.trustedHost,
              sourceURL.path == "/ws/rest/vehicle/\(sourceRecordID)",
              (1984...(Calendar.current.component(.year, from: Date()) + 1)).contains(year),
              Self.isMeaningful(make, maximumLength: 80),
              Self.isMeaningful(model, maximumLength: 120),
              Self.isMeaningful(variant, maximumLength: 240),
              Self.isMeaningful(engineDescription, maximumLength: 160),
              Self.isMeaningful(transmission, maximumLength: 120),
              fuelType.supportsLiquidFuelEstimate,
              Self.isPlausibleConsumption(cityLitersPer100Km),
              Self.isPlausibleConsumption(highwayLitersPer100Km),
              Self.isPlausibleConsumption(combinedLitersPer100Km) else {
            return false
        }

        let lower = min(cityLitersPer100Km, highwayLitersPer100Km)
        let upper = max(cityLitersPer100Km, highwayLitersPer100Km)
        return combinedLitersPer100Km >= lower && combinedLitersPer100Km <= upper
    }

    func matched(to profile: UserProfile) -> VerifiedVehicleSpecification? {
        guard hasTrustedEvidence,
              profile.vehicleType == .voiture,
              Int(profile.vehicleYear.trimmingCharacters(in: .whitespacesAndNewlines)) == year,
              Self.normalized(profile.vehicleBrand) == Self.normalized(make),
              Self.normalized(profile.vehicleModel) == Self.normalized(model),
              profile.fuelType == fuelType else {
            return nil
        }
        return self
    }

    var qualifiedSourceIdentifier: String {
        "\(sourceIdentifier)#\(sourceRecordID)"
    }

    private static func isMeaningful(_ value: String, maximumLength: Int) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maximumLength &&
            trimmed.rangeOfCharacter(from: .controlCharacters) == nil
    }

    private static func isPlausibleConsumption(_ value: Double) -> Bool {
        value.isFinite && (0.5...100).contains(value)
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }
}

/// Client direct de l'API publique officielle FuelEconomy.gov. Il ne recoit
/// aucune position et n'envoie que l'annee, la marque et le modele saisis par
/// l'utilisateur. Les redirections vers un autre domaine sont refusees.
final class FuelEconomyVehicleClient {
    static let shared = FuelEconomyVehicleClient()
    static let sourceIdentifier = "fueleconomy.gov.vehicle"
    static let trustedHost = "www.fueleconomy.gov"
    static let maximumResponseBytes = 1_000_000
    static let requestTimeout: TimeInterval = 10

    private static let baseURL = URL(string: "https://www.fueleconomy.gov/ws/rest")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchVariants(year: Int, make: String, model: String) async throws -> [FuelEconomyVehicleVariant] {
        guard Self.isValidYear(year),
              Self.isValidQueryValue(make),
              Self.isValidQueryValue(model),
              var components = URLComponents(
                url: Self.baseURL.appending(path: "vehicle/menu/options"),
                resolvingAgainstBaseURL: false
              ) else {
            throw PublicVehicleCatalogError.invalidRequest
        }

        components.queryItems = [
            URLQueryItem(name: "year", value: String(year)),
            URLQueryItem(name: "make", value: make.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "model", value: model.trimmingCharacters(in: .whitespacesAndNewlines))
        ]
        guard let url = components.url else {
            throw PublicVehicleCatalogError.invalidRequest
        }

        let data = try await perform(url: url)
        let payload: MenuPayload
        do {
            payload = try JSONDecoder().decode(MenuPayload.self, from: data)
        } catch {
            throw PublicVehicleCatalogError.invalidResponse
        }

        let variants = payload.items.compactMap { item -> FuelEconomyVehicleVariant? in
            let variant = FuelEconomyVehicleVariant(recordID: item.value, description: item.text)
            return variant.isValid ? variant : nil
        }
        var seenRecordIDs = Set<String>()
        let unique = variants.filter { seenRecordIDs.insert($0.recordID).inserted }
        guard !unique.isEmpty else {
            throw PublicVehicleCatalogError.invalidResponse
        }
        return unique
    }

    func fetchSpecification(
        variant: FuelEconomyVehicleVariant,
        expectedYear: Int,
        expectedMake: String,
        expectedModel: String,
        retrievedAt: Date = Date()
    ) async throws -> VerifiedVehicleSpecification {
        guard variant.isValid,
              Self.isValidYear(expectedYear),
              Self.isValidQueryValue(expectedMake),
              Self.isValidQueryValue(expectedModel) else {
            throw PublicVehicleCatalogError.invalidRequest
        }

        let url = Self.baseURL.appending(path: "vehicle/\(variant.recordID)")
        let data = try await perform(url: url)
        let payload: VehiclePayload
        do {
            payload = try JSONDecoder().decode(VehiclePayload.self, from: data)
        } catch {
            throw PublicVehicleCatalogError.invalidResponse
        }

        guard payload.id == variant.recordID,
              payload.year == String(expectedYear),
              Self.normalized(payload.make) == Self.normalized(expectedMake),
              Self.normalized(payload.model) == Self.normalized(expectedModel) else {
            throw PublicVehicleCatalogError.identityMismatch
        }
        guard let fuelType = Self.fuelType(primary: payload.fuelType1, technology: payload.atvType),
              let cityMPG = Double(payload.city08),
              let highwayMPG = Double(payload.highway08),
              let combinedMPG = Double(payload.comb08),
              cityMPG > 0,
              highwayMPG > 0,
              combinedMPG > 0 else {
            throw PublicVehicleCatalogError.invalidResponse
        }

        let engine = Self.engineDescription(from: payload)
        guard let specification = VerifiedVehicleSpecification(
            sourceIdentifier: Self.sourceIdentifier,
            sourceRecordID: payload.id,
            sourceURL: url,
            retrievedAt: retrievedAt,
            year: expectedYear,
            make: payload.make,
            model: payload.model,
            variant: variant.description,
            engineDescription: engine,
            transmission: payload.trany,
            fuelType: fuelType,
            cityLitersPer100Km: Self.litersPer100Km(fromMPG: cityMPG),
            highwayLitersPer100Km: Self.litersPer100Km(fromMPG: highwayMPG),
            combinedLitersPer100Km: Self.litersPer100Km(fromMPG: combinedMPG)
        ) else {
            throw PublicVehicleCatalogError.invalidResponse
        }
        return specification
    }

    private func perform(url: URL) async throws -> Data {
        guard Self.isTrusted(url) else {
            throw PublicVehicleCatalogError.invalidRequest
        }
        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw PublicVehicleCatalogError.network(error.code)
        } catch {
            throw PublicVehicleCatalogError.transport
        }

        guard data.count <= Self.maximumResponseBytes else {
            throw PublicVehicleCatalogError.responseTooLarge
        }
        guard let httpResponse = response as? HTTPURLResponse,
              let responseURL = httpResponse.url,
              Self.isTrusted(responseURL) else {
            throw PublicVehicleCatalogError.untrustedResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw PublicVehicleCatalogError.apiStatus(httpResponse.statusCode)
        }
        guard httpResponse.mimeType?.lowercased() == "application/json" else {
            throw PublicVehicleCatalogError.invalidResponse
        }
        return data
    }

    private static func isTrusted(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" &&
            url.host?.lowercased() == trustedHost &&
            url.port == nil &&
            url.user == nil &&
            url.password == nil &&
            url.path.hasPrefix("/ws/rest/vehicle/")
    }

    private static func isValidYear(_ year: Int) -> Bool {
        (1984...(Calendar.current.component(.year, from: Date()) + 1)).contains(year)
    }

    private static func isValidQueryValue(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 120 &&
            trimmed.rangeOfCharacter(from: .controlCharacters) == nil
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    private static func litersPer100Km(fromMPG mpg: Double) -> Double {
        235.214583 / mpg
    }

    private static func fuelType(primary: String, technology: String) -> VehicleFuelType? {
        let fuel = primary.lowercased()
        let tech = technology.lowercased()
        if fuel.contains("diesel") {
            return tech.contains("hybrid") ? .dieselHybrid : .diesel
        }
        if fuel.contains("gasoline") || fuel.contains("regular") || fuel.contains("premium") || fuel.contains("midgrade") {
            return tech.contains("hybrid") || fuel.contains("electricity") ? .gasolineHybrid : .gasoline
        }
        return nil
    }

    private static func engineDescription(from payload: VehiclePayload) -> String {
        [
            payload.displ.isEmpty ? nil : "\(payload.displ) L",
            payload.cylinders.isEmpty ? nil : "\(payload.cylinders) cyl",
            payload.engDscr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : payload.engDscr
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

private struct MenuPayload: Decodable {
    let items: [MenuItemPayload]

    private enum CodingKeys: String, CodingKey {
        case menuItem
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let many = try? container.decode([MenuItemPayload].self, forKey: .menuItem) {
            items = many
        } else {
            items = [try container.decode(MenuItemPayload.self, forKey: .menuItem)]
        }
    }
}

private struct MenuItemPayload: Decodable {
    let text: String
    let value: String
}

private struct VehiclePayload: Decodable {
    let id: String
    let year: String
    let make: String
    let model: String
    let fuelType1: String
    let atvType: String
    let city08: String
    let highway08: String
    let comb08: String
    let cylinders: String
    let displ: String
    let engDscr: String
    let trany: String

    private enum CodingKeys: String, CodingKey {
        case id, year, make, model, fuelType1, atvType, city08, highway08, comb08
        case cylinders, displ, trany
        case engDscr = "eng_dscr"
    }
}
