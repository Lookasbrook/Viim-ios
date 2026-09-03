import CryptoKit
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
    let sourceIdentifier: String
    let recordID: String
    let description: String

    init(
        recordID: String,
        description: String,
        sourceIdentifier: String = FuelEconomyVehicleClient.sourceIdentifier
    ) {
        self.sourceIdentifier = sourceIdentifier
        self.recordID = recordID
        self.description = description
    }

    var id: String { "\(sourceIdentifier)#\(recordID)" }

    var isValid: Bool {
        guard !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        switch sourceIdentifier {
        case FuelEconomyVehicleClient.sourceIdentifier:
            return !recordID.isEmpty && recordID.count <= 12 && recordID.allSatisfy(\.isNumber)
        case NRCanVehicleClient.sourceIdentifier:
            return NRCanVehicleClient.isValidRecordID(recordID)
        default:
            return false
        }
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

        let trustedSource: Bool
        switch sourceIdentifier {
        case FuelEconomyVehicleClient.sourceIdentifier:
            trustedSource = sourceRecordID.count <= 12 &&
                !sourceRecordID.isEmpty &&
                sourceRecordID.allSatisfy(\.isNumber) &&
                sourceURL.scheme?.lowercased() == "https" &&
                sourceURL.host?.lowercased() == FuelEconomyVehicleClient.trustedHost &&
                sourceURL.port == nil &&
                sourceURL.user == nil &&
                sourceURL.password == nil &&
                sourceURL.query == nil &&
                sourceURL.path == "/ws/rest/vehicle/\(sourceRecordID)"
        case NRCanVehicleClient.sourceIdentifier:
            trustedSource = NRCanVehicleClient.hasTrustedEvidence(
                sourceRecordID: sourceRecordID,
                sourceURL: sourceURL,
                year: year,
                make: make,
                model: model,
                variant: variant,
                engineDescription: engineDescription,
                transmission: transmission,
                fuelType: fuelType,
                cityLitersPer100Km: cityLitersPer100Km,
                highwayLitersPer100Km: highwayLitersPer100Km,
                combinedLitersPer100Km: combinedLitersPer100Km
            )
        default:
            trustedSource = false
        }
        guard trustedSource else {
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

    var officialSourceDisplayName: String {
        switch sourceIdentifier {
        case NRCanVehicleClient.sourceIdentifier:
            return "Ressources naturelles Canada"
        case FuelEconomyVehicleClient.sourceIdentifier:
            return "FuelEconomy.gov"
        default:
            return sourceIdentifier
        }
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
              variant.sourceIdentifier == Self.sourceIdentifier,
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

/// Routage local : un profil canadien utilise le jeu de donnees public de
/// Ressources naturelles Canada. Les autres profils gardent FuelEconomy.gov
/// tant qu'une source nationale equivalente n'a pas ete qualifiee.
enum LocalizedVehicleCatalogClient {
    static func preferredSourceIdentifier(for country: SupportedCountry) -> String {
        country == .canada
            ? NRCanVehicleClient.sourceIdentifier
            : FuelEconomyVehicleClient.sourceIdentifier
    }

    static func fetchVariants(
        country: SupportedCountry,
        year: Int,
        make: String,
        model: String,
        expectedFuelType: VehicleFuelType?
    ) async throws -> [FuelEconomyVehicleVariant] {
        if country == .canada {
            return try await NRCanVehicleClient.shared.fetchVariants(
                year: year,
                make: make,
                model: model,
                expectedFuelType: expectedFuelType
            )
        }
        return try await FuelEconomyVehicleClient.shared.fetchVariants(year: year, make: make, model: model)
    }

    static func fetchSpecification(
        variant: FuelEconomyVehicleVariant,
        expectedYear: Int,
        expectedMake: String,
        expectedModel: String,
        expectedFuelType: VehicleFuelType?
    ) async throws -> VerifiedVehicleSpecification {
        switch variant.sourceIdentifier {
        case NRCanVehicleClient.sourceIdentifier:
            return try await NRCanVehicleClient.shared.fetchSpecification(
                variant: variant,
                expectedYear: expectedYear,
                expectedMake: expectedMake,
                expectedModel: expectedModel,
                expectedFuelType: expectedFuelType
            )
        case FuelEconomyVehicleClient.sourceIdentifier:
            return try await FuelEconomyVehicleClient.shared.fetchSpecification(
                variant: variant,
                expectedYear: expectedYear,
                expectedMake: expectedMake,
                expectedModel: expectedModel
            )
        default:
            throw PublicVehicleCatalogError.invalidRequest
        }
    }
}

/// Client du catalogue officiel de consommation de carburant de Ressources
/// naturelles Canada. Le fichier public est charge par annee, jamais avec la
/// position de l'utilisateur. Une ligne n'est proposee que si l'identite du
/// modele et le type de carburant concordent sans ambiguite.
final class NRCanVehicleClient {
    static let shared = NRCanVehicleClient()
    static let sourceIdentifier = "nrcan.fuel-consumption-ratings"
    static let maximumResponseBytes = 1_500_000
    static let requestTimeout: TimeInterval = 15

    private struct Source: Equatable {
        let years: ClosedRange<Int>
        let datasetID: String
        let resourceID: String
        let filename: String

        var canonicalURL: URL {
            URL(string: "https://open.canada.ca/data/dataset/\(datasetID)/resource/\(resourceID)/download/\(filename)")!
        }

        var blobPath: String {
            "/opengovprod/resources/\(resourceID)/\(filename)"
        }
    }

    private static let sources = [
        Source(
            years: 1995...2014,
            datasetID: "98f1a129-f628-4ce4-b24d-6f16bf24dd64",
            resourceID: "42495676-28b7-40f3-b0e0-3d7fe005ca56",
            filename: "my1995-2014-fuel-consumption-ratings-5-cycle.csv"
        ),
        Source(
            years: 2015...2024,
            datasetID: "98f1a129-f628-4ce4-b24d-6f16bf24dd64",
            resourceID: "c98b9dc8-b23f-4cd8-8b19-e892da1e4688",
            filename: "my2015-2024-fuel-consumption-ratings.csv"
        ),
        Source(
            years: 2025...2025,
            datasetID: "98f1a129-f628-4ce4-b24d-6f16bf24dd64",
            resourceID: "d589f2bc-9a85-4f65-be2f-20f17debfcb1",
            filename: "my2025-fuel-consumption-ratings.csv"
        ),
        Source(
            years: 2026...2026,
            datasetID: "98f1a129-f628-4ce4-b24d-6f16bf24dd64",
            resourceID: "9df1b18d-d036-4783-a61c-99f1f75b3ac5",
            filename: "my2026-fuel-consumption-ratings.csv"
        )
    ]

    private struct Row {
        let year: Int
        let make: String
        let fullModel: String
        let engineSize: Double
        let cylinders: Int
        let transmission: String
        let fuelType: VehicleFuelType
        let city: Double
        let highway: Double
        let combined: Double

        var engineDescription: String {
            "\(engineSize.formatted(.number.precision(.fractionLength(0...1)))) L · \(cylinders) cyl"
        }
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchVariants(
        year: Int,
        make: String,
        model: String,
        expectedFuelType: VehicleFuelType? = nil
    ) async throws -> [FuelEconomyVehicleVariant] {
        let (source, rows) = try await matchingRows(
            year: year,
            make: make,
            model: model,
            expectedFuelType: expectedFuelType
        )
        let variants = rows.map { row in
            FuelEconomyVehicleVariant(
                recordID: Self.recordID(
                    sourceURL: source.canonicalURL,
                    year: row.year,
                    make: make,
                    model: model,
                    variant: row.fullModel,
                    engineDescription: row.engineDescription,
                    transmission: row.transmission,
                    fuelType: row.fuelType,
                    cityLitersPer100Km: row.city,
                    highwayLitersPer100Km: row.highway,
                    combinedLitersPer100Km: row.combined
                ),
                description: Self.variantDescription(row),
                sourceIdentifier: Self.sourceIdentifier
            )
        }
        var seen = Set<String>()
        let unique = variants.filter { seen.insert($0.recordID).inserted }
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
        expectedFuelType: VehicleFuelType? = nil,
        retrievedAt: Date = Date()
    ) async throws -> VerifiedVehicleSpecification {
        guard variant.isValid, variant.sourceIdentifier == Self.sourceIdentifier else {
            throw PublicVehicleCatalogError.invalidRequest
        }
        let (source, rows) = try await matchingRows(
            year: expectedYear,
            make: expectedMake,
            model: expectedModel,
            expectedFuelType: expectedFuelType
        )
        guard let row = rows.first(where: {
            Self.recordID(
                sourceURL: source.canonicalURL,
                year: $0.year,
                make: expectedMake,
                model: expectedModel,
                variant: $0.fullModel,
                engineDescription: $0.engineDescription,
                transmission: $0.transmission,
                fuelType: $0.fuelType,
                cityLitersPer100Km: $0.city,
                highwayLitersPer100Km: $0.highway,
                combinedLitersPer100Km: $0.combined
            ) == variant.recordID
        }) else {
            throw PublicVehicleCatalogError.identityMismatch
        }
        guard let specification = VerifiedVehicleSpecification(
            sourceIdentifier: Self.sourceIdentifier,
            sourceRecordID: variant.recordID,
            sourceURL: source.canonicalURL,
            retrievedAt: retrievedAt,
            year: row.year,
            make: expectedMake.trimmingCharacters(in: .whitespacesAndNewlines),
            model: expectedModel.trimmingCharacters(in: .whitespacesAndNewlines),
            variant: row.fullModel,
            engineDescription: row.engineDescription,
            transmission: row.transmission,
            fuelType: row.fuelType,
            cityLitersPer100Km: row.city,
            highwayLitersPer100Km: row.highway,
            combinedLitersPer100Km: row.combined
        ) else {
            throw PublicVehicleCatalogError.invalidResponse
        }
        return specification
    }

    private func matchingRows(
        year: Int,
        make: String,
        model: String,
        expectedFuelType: VehicleFuelType?
    ) async throws -> (Source, [Row]) {
        guard let source = Self.source(for: year),
              Self.isValidQueryValue(make),
              Self.isValidQueryValue(model),
              expectedFuelType != .electric else {
            throw PublicVehicleCatalogError.invalidRequest
        }
        let data = try await perform(source: source)
        let parsedRows = try await Task.detached(priority: .userInitiated) {
            try Self.parseRows(data)
        }.value
        let rows = parsedRows.filter {
            $0.year == year &&
                Self.normalized($0.make) == Self.normalized(make) &&
                Self.matchesModel(candidate: $0.fullModel, expected: model) &&
                (expectedFuelType == nil || $0.fuelType == expectedFuelType)
        }
        guard !rows.isEmpty else {
            throw PublicVehicleCatalogError.invalidResponse
        }
        return (source, rows)
    }

    private func perform(source: Source) async throws -> Data {
        var request = URLRequest(url: source.canonicalURL, timeoutInterval: Self.requestTimeout)
        request.httpMethod = "GET"
        request.setValue("text/csv", forHTTPHeaderField: "Accept")

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
              Self.isTrusted(responseURL, for: source) else {
            throw PublicVehicleCatalogError.untrustedResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw PublicVehicleCatalogError.apiStatus(httpResponse.statusCode)
        }
        guard httpResponse.mimeType?.lowercased() == "text/csv" else {
            throw PublicVehicleCatalogError.invalidResponse
        }
        return data
    }

    static func hasTrustedEvidence(
        sourceRecordID: String,
        sourceURL: URL,
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
    ) -> Bool {
        guard let source = source(for: year), sourceURL == source.canonicalURL else {
            return false
        }
        return sourceRecordID == recordID(
            sourceURL: sourceURL,
            year: year,
            make: make,
            model: model,
            variant: variant,
            engineDescription: engineDescription,
            transmission: transmission,
            fuelType: fuelType,
            cityLitersPer100Km: cityLitersPer100Km,
            highwayLitersPer100Km: highwayLitersPer100Km,
            combinedLitersPer100Km: combinedLitersPer100Km
        )
    }

    static func isValidRecordID(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    private static func recordID(
        sourceURL: URL,
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
    ) -> String {
        let fields = [
            sourceURL.absoluteString,
            String(year),
            make.trimmingCharacters(in: .whitespacesAndNewlines),
            model.trimmingCharacters(in: .whitespacesAndNewlines),
            variant,
            engineDescription,
            transmission,
            fuelType.rawValue,
            String(cityLitersPer100Km.bitPattern, radix: 16),
            String(highwayLitersPer100Km.bitPattern, radix: 16),
            String(combinedLitersPer100Km.bitPattern, radix: 16)
        ]
        let digest = SHA256.hash(data: Data(fields.joined(separator: "\u{1f}").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func source(for year: Int) -> Source? {
        sources.first { $0.years.contains(year) }
    }

    private static func isTrusted(_ url: URL, for source: Source) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.port == nil,
              url.user == nil,
              url.password == nil else {
            return false
        }
        if url.host?.lowercased() == "open.canada.ca" {
            return url == source.canonicalURL
        }
        return url.host?.lowercased() == "opencanada.blob.core.windows.net" &&
            url.path == source.blobPath
    }

    private static func parseRows(_ data: Data) throws -> [Row] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw PublicVehicleCatalogError.invalidResponse
        }
        let table = try parseCSV(text)
        let expectedHeaders = [
            "Model year", "Make", "Model", "Vehicle class", "Engine size (L)",
            "Cylinders", "Transmission", "Fuel type", "City (L/100 km)",
            "Highway (L/100 km)", "Combined (L/100 km)"
        ]
        guard let header = table.first, header.count >= expectedHeaders.count else {
            throw PublicVehicleCatalogError.invalidResponse
        }
        let normalizedHeader = header.enumerated().map { index, value in
            index == 0 ? value.replacingOccurrences(of: "\u{feff}", with: "") : value
        }
        guard Array(normalizedHeader.prefix(expectedHeaders.count)) == expectedHeaders else {
            throw PublicVehicleCatalogError.invalidResponse
        }
        return table.dropFirst().compactMap { columns in
            guard columns.count >= expectedHeaders.count,
                  let year = Int(columns[0]),
                  let engineSize = Double(columns[4]),
                  let cylinders = Int(columns[5]),
                  (0.1...20).contains(engineSize),
                  (1...24).contains(cylinders),
                  isMeaningful(columns[1], maximumLength: 80),
                  isMeaningful(columns[2], maximumLength: 160),
                  isMeaningful(columns[6], maximumLength: 80),
                  let fuelType = fuelType(code: columns[7], model: columns[2]),
                  let city = Double(columns[8]),
                  let highway = Double(columns[9]),
                  let combined = Double(columns[10]),
                  isPlausibleConsumption(city),
                  isPlausibleConsumption(highway),
                  isPlausibleConsumption(combined),
                  combined >= min(city, highway),
                  combined <= max(city, highway) else {
                return nil
            }
            return Row(
                year: year,
                make: columns[1],
                fullModel: columns[2],
                engineSize: engineSize,
                cylinders: cylinders,
                transmission: columns[6],
                fuelType: fuelType,
                city: city,
                highway: highway,
                combined: combined
            )
        }
    }

    private static func parseCSV(_ text: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var insideQuotes = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "\"" {
                let next = text.index(after: index)
                if insideQuotes, next < text.endIndex, text[next] == "\"" {
                    field.append("\"")
                    index = next
                } else {
                    insideQuotes.toggle()
                }
            } else if character == "," && !insideQuotes {
                row.append(field)
                field = ""
            } else if (character == "\n" || character == "\r") && !insideQuotes {
                if character == "\r" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\n" {
                        index = next
                    }
                }
                row.append(field)
                if !row.allSatisfy({ $0.isEmpty }) {
                    rows.append(row)
                }
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index = text.index(after: index)
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        guard !insideQuotes else {
            throw PublicVehicleCatalogError.invalidResponse
        }
        return rows
    }

    private static func matchesModel(candidate: String, expected: String) -> Bool {
        let candidate = folded(candidate)
        let expected = folded(expected)
        guard candidate == expected || candidate.hasPrefix(expected + " ") else {
            return false
        }
        guard candidate != expected else {
            return true
        }
        let suffix = String(candidate.dropFirst(expected.count + 1))
        let allowedPrefixes = [
            "awd", "4wd", "4x4", "2wd", "hybrid", "hatchback", "sedan",
            "coupe", "convertible", "wagon"
        ]
        return suffix.hasPrefix("(") ||
            allowedPrefixes.contains { suffix == $0 || suffix.hasPrefix($0 + " ") || suffix.hasPrefix($0 + "(") }
    }

    private static func fuelType(code: String, model: String) -> VehicleFuelType? {
        let hybrid = folded(model).contains(" hybrid")
        switch code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "X", "Z": return hybrid ? .gasolineHybrid : .gasoline
        case "D": return hybrid ? .dieselHybrid : .diesel
        default: return nil
        }
    }

    private static func variantDescription(_ row: Row) -> String {
        "\(row.fullModel) · \(row.engineDescription) · \(row.transmission)"
    }

    private static func isPlausibleConsumption(_ value: Double) -> Bool {
        value.isFinite && (0.5...100).contains(value)
    }

    private static func isValidQueryValue(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 120 &&
            trimmed.rangeOfCharacter(from: .controlCharacters) == nil
    }

    private static func isMeaningful(_ value: String, maximumLength: Int) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maximumLength &&
            trimmed.rangeOfCharacter(from: .controlCharacters) == nil
    }

    private static func normalized(_ value: String) -> String {
        folded(value).replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    private static func folded(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_CA_POSIX"))
            .lowercased()
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
