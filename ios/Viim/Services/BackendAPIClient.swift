import CoreLocation
import Foundation

enum BackendAPIError: Error, Equatable {
    case invalidURL
    case invalidResponse
    case apiStatus(statusCode: Int, code: String?)
    case network(URLError.Code)
    case transport
}

final class BackendAPIClient {
    static let shared = BackendAPIClient()

    private static let trustedAPIHost = "api.burktech-ia.com"
    private static let maximumFuelPriceResponseBytes = 128_000
    private static let fuelPriceRequestTimeout: TimeInterval = 10
    private let baseURL = URL(string: "https://api.burktech-ia.com/v1")
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func sendAlertTest(contact: EmergencyContact, driverName: String?) async throws {
        let payload = AlertTestPayload(
            driverName: driverName,
            contact: AlertContactPayload(contact)
        )
        try await post(payload, path: "alerts/test")
    }

    func shareLocation(
        contact: EmergencyContact,
        driverName: String?,
        location: CLLocation
    ) async throws {
        let payload = LocationSharePayload(
            driverName: driverName,
            contact: AlertContactPayload(contact),
            location: AlertLocationPayload(location)
        )
        try await post(payload, path: "alerts/location-share")
    }

    func fetchOfficialFuelPrice(
        countryCode: String,
        regionCode: String,
        locality: String,
        fuelType: VehicleFuelType,
        now: Date = Date()
    ) async throws -> PublicFuelPriceQuote {
        guard Self.isValidLocationComponent(countryCode, maximumLength: 2),
              Self.isValidLocationComponent(regionCode, maximumLength: 80),
              Self.isValidLocationComponent(locality, maximumLength: 80) else {
            throw BackendAPIError.invalidURL
        }
        guard let baseURL,
              var components = URLComponents(
                url: baseURL.appending(path: "fuel-prices/current"),
                resolvingAgainstBaseURL: false
              ) else {
            throw BackendAPIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "country", value: countryCode),
            URLQueryItem(name: "region", value: regionCode),
            URLQueryItem(name: "locality", value: locality),
            URLQueryItem(name: "fuelType", value: fuelType.rawValue)
        ]
        guard let url = components.url else {
            throw BackendAPIError.invalidURL
        }

        var request = URLRequest(url: url, timeoutInterval: Self.fuelPriceRequestTimeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await perform(request, operation: "api.fuelPrice")
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAPIError.invalidResponse
        }
        guard data.count <= Self.maximumFuelPriceResponseBytes,
              let responseURL = httpResponse.url,
              Self.isTrustedFuelPriceResponseURL(responseURL),
              httpResponse.mimeType?.lowercased() == "application/json" else {
            throw BackendAPIError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let apiError = try? JSONDecoder().decode(APIErrorPayload.self, from: data)
            throw BackendAPIError.apiStatus(statusCode: httpResponse.statusCode, code: apiError?.error)
        }

        do {
            let quote = try PublicFuelPriceQuote.decode(from: data)
            guard quote.isValid(
                countryCode: countryCode,
                regionCode: regionCode,
                fuelType: fuelType,
                now: now
            ) else {
                throw BackendAPIError.invalidResponse
            }
            return quote
        } catch {
            throw BackendAPIError.invalidResponse
        }
    }

    private func post<Payload: Encodable>(_ payload: Payload, path: String) async throws {
        guard let url = baseURL?.appending(path: path) else {
            throw BackendAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await perform(request, operation: "api.post path=/v1/\(path)")

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAPIError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let apiError = try? JSONDecoder().decode(APIErrorPayload.self, from: data)
            ViimDiagnostics.log("api.post.failure path=/v1/\(path) status=\(httpResponse.statusCode) code=\(apiError?.error ?? "none")")
            throw BackendAPIError.apiStatus(statusCode: httpResponse.statusCode, code: apiError?.error)
        }
    }

    private func perform(_ request: URLRequest, operation: String) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let urlError as URLError {
            ViimDiagnostics.log("\(operation).transport urlError=\(urlError.code.rawValue)")
            throw BackendAPIError.network(urlError.code)
        } catch {
            ViimDiagnostics.log("\(operation).transport error=unknown")
            throw BackendAPIError.transport
        }
    }

    private static func isValidLocationComponent(_ value: String, maximumLength: Int) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty &&
            trimmed.count <= maximumLength &&
            trimmed.rangeOfCharacter(from: .controlCharacters) == nil
    }

    private static func isTrustedFuelPriceResponseURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" &&
            url.host?.lowercased() == trustedAPIHost &&
            url.port == nil &&
            url.user == nil &&
            url.password == nil &&
            url.path == "/v1/fuel-prices/current"
    }
}

struct PublicFuelPriceQuote: Equatable {
    private static let maximumRetrievalAge: TimeInterval = 24 * 60 * 60
    private static let maximumFutureClockSkew: TimeInterval = 5 * 60
    private static let plausibleCanadianPriceRange = 0.20...5.00

    let countryCode: String
    let regionCode: String
    let locality: String
    let fuelType: VehicleFuelType
    let pricePerLiter: Double
    let currency: SupportedCurrency
    let observedAt: Date
    let retrievedAt: Date
    let source: String
    let sourceURL: URL

    fileprivate func isValid(
        countryCode requestedCountry: String,
        regionCode requestedRegion: String,
        fuelType requestedFuelType: VehicleFuelType,
        now: Date
    ) -> Bool {
        let normalizedCountry = requestedCountry.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedRegion = requestedRegion
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let acceptedRegions = normalizedRegion == "ONTARIO"
            ? Set(["ON", "ONTARIO"])
            : Set([normalizedRegion])
        let sourceAge = now.timeIntervalSince(observedAt)
        let retrievalAge = now.timeIntervalSince(retrievedAt)
        let chronologyIsValid = observedAt <= retrievedAt.addingTimeInterval(Self.maximumFutureClockSkew)
        let normalizedQuoteCountry = countryCode.uppercased()
        let normalizedQuoteRegion = regionCode.uppercased()
        guard let maximumSourceAge = OfficialFuelPriceEvidenceContract.maximumAge(
            for: source
        ) else {
            return false
        }

        return normalizedQuoteCountry == "CA" &&
            normalizedQuoteCountry == normalizedCountry &&
            acceptedRegions.contains(normalizedQuoteRegion) &&
            requestedFuelType == fuelType &&
            currency == .cad &&
            Self.plausibleCanadianPriceRange.contains(pricePerLiter) &&
            !locality.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            locality.count <= 80 &&
            locality.rangeOfCharacter(from: .controlCharacters) == nil &&
            sourceAge >= -Self.maximumFutureClockSkew &&
            sourceAge <= maximumSourceAge &&
            retrievalAge >= -Self.maximumFutureClockSkew &&
            retrievalAge <= Self.maximumRetrievalAge &&
            chronologyIsValid &&
            hasTrustedOfficialSource
    }

    fileprivate var hasTrustedOfficialSource: Bool {
        OfficialFuelPriceEvidenceContract.hasTrustedSource(
            identifier: source,
            url: sourceURL
        ) && OfficialFuelPriceEvidenceContract.supportsEvidence(
            identifier: source,
            fuelType: fuelType,
            locality: locality
        )
    }

    fileprivate static func decode(from data: Data) throws -> PublicFuelPriceQuote {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let fuelType = VehicleFuelType(rawValue: payload.fuelType),
              let currency = SupportedCurrency(rawValue: payload.currency),
              let observedAt = parseDate(payload.observedAt),
              let retrievedAt = parseDate(payload.retrievedAt),
              let sourceURL = URL(string: payload.sourceUrl),
              sourceURL.scheme == "https",
              payload.pricePerLiter.isFinite,
              payload.pricePerLiter > 0 else {
            throw BackendAPIError.invalidResponse
        }
        return PublicFuelPriceQuote(
            countryCode: payload.countryCode,
            regionCode: payload.regionCode,
            locality: payload.locality,
            fuelType: fuelType,
            pricePerLiter: payload.pricePerLiter,
            currency: currency,
            observedAt: observedAt,
            retrievedAt: retrievedAt,
            source: payload.source,
            sourceURL: sourceURL
        )
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private struct Payload: Decodable {
        let countryCode: String
        let regionCode: String
        let locality: String
        let fuelType: String
        let pricePerLiter: Double
        let currency: String
        let observedAt: String
        let retrievedAt: String
        let source: String
        let sourceUrl: String
    }
}

/// Lit le relevé public de l'Ontario directement sur l'appareil. La sélection
/// de marché reste locale : aucune coordonnée et aucune ville ne quittent
/// l'iPhone pour cette source.
final class OntarioPublicFuelPriceClient {
    static let shared = OntarioPublicFuelPriceClient()

    private static let sourceURL = OfficialFuelPriceEvidenceContract.ontarioURL
    private static let redirectedSourceHost = "prod-energy-fuel-prices.s3.amazonaws.com"
    private static let maximumResponseBytes = 2_000_000
    private static let requestTimeout: TimeInterval = 10
    private static let sourceIdentifier = OfficialFuelPriceEvidenceContract.ontarioIdentifier
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchCurrentPrice(
        countryCode: String,
        regionCode: String,
        locality: String,
        fuelType: VehicleFuelType,
        now: Date = Date()
    ) async throws -> PublicFuelPriceQuote {
        let country = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let region = regionCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard country == "CA",
              ["ON", "ONTARIO"].contains(region),
              !locality.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              locality.count <= 80,
              locality.rangeOfCharacter(from: .controlCharacters) == nil,
              let providerFuelType = Self.providerFuelType(for: fuelType) else {
            throw BackendAPIError.apiStatus(statusCode: 404, code: "fuel_price_unavailable")
        }

        var request = URLRequest(url: Self.sourceURL, timeoutInterval: Self.requestTimeout)
        request.httpMethod = "GET"
        request.setValue("text/csv", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            ViimDiagnostics.log("api.fuelPrice.ontario.transport urlError=\(urlError.code.rawValue)")
            throw BackendAPIError.network(urlError.code)
        } catch {
            ViimDiagnostics.log("api.fuelPrice.ontario.transport error=unknown")
            throw BackendAPIError.transport
        }

        guard data.count <= Self.maximumResponseBytes,
              let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode,
              httpResponse.mimeType?.lowercased() == "text/csv",
              let responseURL = httpResponse.url,
              Self.isTrustedResponseURL(responseURL),
              let text = String(data: data, encoding: .utf8) else {
            throw BackendAPIError.invalidResponse
        }

        let rows = try Self.parseCSV(text)
        guard let latest = Self.latestRow(in: rows, providerFuelType: providerFuelType),
              let selection = Self.priceSelection(from: latest.values, locality: locality) else {
            throw BackendAPIError.invalidResponse
        }

        let quote = PublicFuelPriceQuote(
            countryCode: "CA",
            regionCode: "ON",
            locality: selection.locality,
            fuelType: fuelType,
            pricePerLiter: (selection.centsPerLiter * 10).rounded() / 1_000,
            currency: .cad,
            observedAt: latest.date,
            retrievedAt: now,
            source: Self.sourceIdentifier,
            sourceURL: Self.sourceURL
        )
        guard quote.isValid(
            countryCode: countryCode,
            regionCode: regionCode,
            fuelType: fuelType,
            now: now
        ) else {
            throw BackendAPIError.invalidResponse
        }
        ViimDiagnostics.log(
            "api.fuelPrice.ontario.success observedAt=\(latest.date.timeIntervalSince1970)"
        )
        return quote
    }

    private static func isTrustedResponseURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.port == nil,
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil else {
            return false
        }
        if ["ontario.ca", "www.ontario.ca"].contains(url.host?.lowercased() ?? "") {
            return url.path == sourceURL.path
        }
        return url.host?.lowercased() == redirectedSourceHost &&
            url.path == "/fueltypesall.csv"
    }

    private static func providerFuelType(for fuelType: VehicleFuelType) -> String? {
        switch fuelType {
        case .gasoline, .gasolineHybrid:
            "Regular Unleaded Gasoline"
        case .diesel, .dieselHybrid:
            "Diesel"
        case .electric:
            nil
        }
    }

    private static func latestRow(in rows: [[String: String]], providerFuelType: String) -> DatedRow? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"

        return rows.compactMap { values -> DatedRow? in
            guard values["Fuel Type"] == providerFuelType,
                  let rawDate = values["Date"],
                  let date = formatter.date(from: rawDate) else {
                return nil
            }
            return DatedRow(date: date, values: values)
        }
        .max { $0.date < $1.date }
    }

    private static func priceSelection(
        from row: [String: String],
        locality: String
    ) -> (locality: String, centsPerLiter: Double)? {
        let match = marketSelection(for: locality)
        let columns = match?.columns ?? ["Ontario Average/Moyenne provinciale"]
        let values = columns.compactMap { column -> Double? in
            guard let raw = row[column], let value = Double(raw), value.isFinite, value > 0 else {
                return nil
            }
            return value
        }
        guard !values.isEmpty else {
            return nil
        }
        return (
            match?.displayName ?? "Ontario",
            values.reduce(0, +) / Double(values.count)
        )
    }

    /// La preuve et le cache utilisent le meme nom canonique que la colonne du
    /// releve. Les variantes retournees par le geocodeur (par ex. Sudbury /
    /// Greater Sudbury) ne provoquent donc pas un faux changement de marche.
    static func evidenceLocality(locality: String) -> String {
        marketSelection(for: locality)?.displayName ?? "Ontario"
    }

    private static func marketSelection(for locality: String) -> OntarioMarket? {
        let normalized = normalize(locality)
        let markets = [
            OntarioMarket("Ottawa", ["ottawa"], ["Ottawa"]),
            OntarioMarket("Toronto", ["toronto"], ["Toronto West/Ouest", "Toronto East/Est"]),
            OntarioMarket("Windsor", ["windsor"], ["Windsor"]),
            OntarioMarket("London", ["london"], ["London"]),
            OntarioMarket("Peterborough", ["peterborough"], ["Peterborough"]),
            OntarioMarket("St. Catharines", ["stcatharines", "saintcatharines"], ["St. Catharine's"]),
            OntarioMarket("Sudbury", ["sudbury", "greatersudbury"], ["Sudbury"]),
            OntarioMarket("Sault Ste. Marie", ["saultstemarie", "saultsaintemarie"], ["Sault Saint Marie"]),
            OntarioMarket("Thunder Bay", ["thunderbay"], ["Thunder Bay"]),
            OntarioMarket("North Bay", ["northbay"], ["North Bay"]),
            OntarioMarket("Timmins", ["timmins"], ["Timmins"]),
            OntarioMarket("Kenora", ["kenora"], ["Kenora"]),
            OntarioMarket("Parry Sound", ["parrysound"], ["Parry Sound"])
        ]
        return markets.first { market in
            market.aliases.contains { normalized.contains($0) }
        }
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_CA"))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    private struct OntarioMarket {
        let displayName: String
        let aliases: [String]
        let columns: [String]

        init(_ displayName: String, _ aliases: [String], _ columns: [String]) {
            self.displayName = displayName
            self.aliases = aliases
            self.columns = columns
        }
    }

    private static func parseCSV(_ text: String) throws -> [[String: String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var quoted = false
        var iterator = text.makeIterator()
        var pendingCharacter: Character?

        while let character = pendingCharacter ?? iterator.next() {
            pendingCharacter = nil
            if character == "\"" {
                if quoted, let next = iterator.next() {
                    if next == "\"" {
                        field.append("\"")
                    } else {
                        quoted = false
                        pendingCharacter = next
                    }
                } else {
                    quoted.toggle()
                }
            } else if character == ",", !quoted {
                record.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
                field = ""
            } else if character.isNewline, !quoted {
                if character == "\r", let next = iterator.next(), next != "\n" {
                    pendingCharacter = next
                }
                record.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
                if record.contains(where: { !$0.isEmpty }) {
                    records.append(record)
                }
                record = []
                field = ""
            } else {
                field.append(character)
            }
        }
        if !field.isEmpty || !record.isEmpty {
            record.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
            records.append(record)
        }

        guard !quoted,
              let headers = records.first,
              headers.contains("Date"),
              headers.contains("Fuel Type") else {
            throw BackendAPIError.invalidResponse
        }
        return records.dropFirst().map { fields in
            var values: [String: String] = [:]
            for (index, header) in headers.enumerated() where !header.isEmpty {
                values[header] = fields.indices.contains(index) ? fields[index] : ""
            }
            return values
        }
    }

    private struct DatedRow {
        let date: Date
        let values: [String: String]
    }
}

/// Lit directement l'API publique de Statistique Canada. La ville est convertie
/// localement en identifiant de serie : ni coordonnee GPS ni texte libre ne sont
/// transmis. Si la table ne publie pas cette ville, le resultat est explicitement
/// la moyenne Canada et n'est jamais presente comme un prix provincial.
final class StatisticsCanadaPublicFuelPriceClient {
    static let shared = StatisticsCanadaPublicFuelPriceClient()

    private static let productID = 18_100_001
    private static let endpoint = URL(
        string: "https://www150.statcan.gc.ca/t1/wds/rest/getDataFromCubePidCoordAndLatestNPeriods"
    )!
    private static let sourceURL = OfficialFuelPriceEvidenceContract.statisticsCanadaURL
    private static let sourceIdentifier = OfficialFuelPriceEvidenceContract.statisticsCanadaIdentifier
    private static let maximumResponseBytes = 128_000
    private static let maximumReferencePeriodAge: TimeInterval = 95 * 24 * 60 * 60
    private static let maximumReleaseAge: TimeInterval = 45 * 24 * 60 * 60
    private static let maximumFutureClockSkew: TimeInterval = 5 * 60
    private static let requestTimeout: TimeInterval = 10
    private static let expectedFrequencyCode = 6
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchCurrentPrice(
        countryCode: String,
        regionCode: String,
        locality: String,
        fuelType: VehicleFuelType,
        now: Date = Date()
    ) async throws -> PublicFuelPriceQuote {
        let country = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let region = regionCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let locality = locality.trimmingCharacters(in: .whitespacesAndNewlines)
        guard country == "CA",
              !region.isEmpty,
              region.count <= 80,
              region.rangeOfCharacter(from: .controlCharacters) == nil,
              !locality.isEmpty,
              locality.count <= 80,
              locality.rangeOfCharacter(from: .controlCharacters) == nil,
              let fuelMemberID = Self.fuelMemberID(for: fuelType) else {
            throw BackendAPIError.apiStatus(statusCode: 404, code: "fuel_price_unavailable")
        }

        let market = Self.market(region: region, locality: locality)
        // La table ne publie aucune moyenne nationale diesel. Refuser avant le
        // reseau est plus fiable qu'interroger une coordonnee inexistante ou
        // presenter une autre serie comme un repli Canada.
        guard market.geographyMemberID != 20 || fuelMemberID != 6 else {
            throw BackendAPIError.apiStatus(statusCode: 404, code: "fuel_price_unavailable")
        }
        let coordinate = Self.coordinate(
            geographyMemberID: market.geographyMemberID,
            fuelMemberID: fuelMemberID
        )
        let payload = [
            RequestPayload(
                productId: Self.productID,
                coordinate: coordinate,
                latestN: 3
            )
        ]
        var request = URLRequest(url: Self.endpoint, timeoutInterval: Self.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            ViimDiagnostics.log(
                "api.fuelPrice.statcan.transport urlError=\(urlError.code.rawValue)"
            )
            throw BackendAPIError.network(urlError.code)
        } catch {
            ViimDiagnostics.log("api.fuelPrice.statcan.transport error=unknown")
            throw BackendAPIError.transport
        }

        guard data.count <= Self.maximumResponseBytes,
              let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode,
              httpResponse.mimeType?.lowercased() == "application/json",
              let responseURL = httpResponse.url,
              Self.isTrustedResponseURL(responseURL) else {
            throw BackendAPIError.invalidResponse
        }

        let responses: [ResponsePayload]
        do {
            responses = try JSONDecoder().decode([ResponsePayload].self, from: data)
        } catch {
            throw BackendAPIError.invalidResponse
        }
        guard responses.count == 1,
              responses[0].status == "SUCCESS",
              let object = responses[0].object,
              object.responseStatusCode == 0,
              object.productId == Self.productID,
              object.coordinate == coordinate,
              object.vectorId > 0,
              (1...3).contains(object.vectorDataPoint.count),
              let latest = Self.latestValidPoint(in: object.vectorDataPoint, now: now) else {
            throw BackendAPIError.invalidResponse
        }

        let quote = PublicFuelPriceQuote(
            countryCode: "CA",
            regionCode: region.uppercased(),
            locality: market.displayName,
            fuelType: fuelType,
            pricePerLiter: (latest.value * 10).rounded() / 1_000,
            currency: .cad,
            observedAt: latest.referencePeriodEndedAt,
            retrievedAt: now,
            source: Self.sourceIdentifier,
            sourceURL: Self.sourceURL
        )
        guard quote.isValid(
            countryCode: countryCode,
            regionCode: regionCode,
            fuelType: fuelType,
            now: now
        ) else {
            throw BackendAPIError.invalidResponse
        }
        ViimDiagnostics.log(
            "api.fuelPrice.statcan.success releasedAt=\(latest.releasedAt.timeIntervalSince1970)"
        )
        return quote
    }

    static func evidenceLocality(region: String, locality: String) -> String {
        market(region: region, locality: locality).displayName
    }

    private static func isTrustedResponseURL(_ url: URL) -> Bool {
        url == endpoint
    }

    private static func fuelMemberID(for fuelType: VehicleFuelType) -> Int? {
        switch fuelType {
        case .gasoline, .gasolineHybrid:
            2 // essence ordinaire, libre-service
        case .diesel, .dieselHybrid:
            6 // diesel, libre-service
        case .electric:
            nil
        }
    }

    private static func coordinate(
        geographyMemberID: Int,
        fuelMemberID: Int
    ) -> String {
        "\(geographyMemberID).\(fuelMemberID).0.0.0.0.0.0.0.0"
    }

    private static func market(region: String, locality: String) -> MarketSelection {
        let normalizedRegion = normalize(region)
        let normalizedLocality = normalize(locality)
        let markets = [
            Market(2, "St. John's", ["nl", "newfoundlandandlabrador", "terreneuveetlabrador"], ["stjohns", "saintjohns"]),
            Market(3, "Charlottetown et Summerside", ["pe", "pei", "princeedwardisland", "ileduprinceedouard"], ["charlottetown", "summerside"]),
            Market(4, "Halifax", ["ns", "novascotia", "nouvelleecosse"], ["halifax"]),
            Market(5, "Saint John", ["nb", "newbrunswick", "nouveaubrunswick"], ["saintjohn", "stjohn"]),
            Market(6, "Québec", ["qc", "quebec"], ["quebec", "quebeccity"]),
            Market(7, "Montréal", ["qc", "quebec"], ["montreal"]),
            Market(11, "Winnipeg", ["mb", "manitoba"], ["winnipeg"]),
            Market(12, "Regina", ["sk", "saskatchewan"], ["regina"]),
            Market(13, "Saskatoon", ["sk", "saskatchewan"], ["saskatoon"]),
            Market(14, "Edmonton", ["ab", "alberta"], ["edmonton"]),
            Market(15, "Calgary", ["ab", "alberta"], ["calgary"]),
            Market(16, "Vancouver", ["bc", "britishcolumbia", "colombiebritannique"], ["vancouver"]),
            Market(17, "Victoria", ["bc", "britishcolumbia", "colombiebritannique"], ["victoria"]),
            Market(18, "Whitehorse", ["yt", "yukon"], ["whitehorse"]),
            Market(19, "Yellowknife", ["nt", "nwt", "northwestterritories", "territoiresdunordouest"], ["yellowknife"])
        ]
        guard let match = markets.first(where: {
            $0.regionAliases.contains(normalizedRegion) &&
                $0.localityAliases.contains(where: normalizedLocality.contains)
        }) else {
            return MarketSelection(geographyMemberID: 20, displayName: "Canada")
        }
        return MarketSelection(
            geographyMemberID: match.geographyMemberID,
            displayName: match.displayName
        )
    }

    private static func latestValidPoint(
        in points: [DataPoint],
        now: Date
    ) -> ValidPoint? {
        points.compactMap { point -> ValidPoint? in
            guard point.value.isFinite,
                  (20...500).contains(point.value),
                  point.decimals == 1,
                  point.scalarFactorCode == 0,
                  point.symbolCode == 0,
                  point.statusCode == 0,
                  point.securityLevelCode == 0,
                  point.frequencyCode == expectedFrequencyCode,
                  let referenceDate = parseReferenceDate(point.refPer),
                  let releasedAt = parseReleaseDate(point.releaseTime) else {
                return nil
            }
            let referenceAge = now.timeIntervalSince(referenceDate)
            let releaseAge = now.timeIntervalSince(releasedAt)
            guard referenceAge >= -maximumFutureClockSkew,
                  referenceAge <= maximumReferencePeriodAge,
                  releaseAge >= -maximumFutureClockSkew,
                  releaseAge <= maximumReleaseAge,
                  releasedAt >= referenceDate else {
                return nil
            }
            guard let referencePeriodEndedAt = endOfReferenceMonth(referenceDate) else {
                return nil
            }
            return ValidPoint(
                referenceDate: referenceDate,
                referencePeriodEndedAt: referencePeriodEndedAt,
                releasedAt: releasedAt,
                value: point.value
            )
        }
        .max { $0.referenceDate < $1.referenceDate }
    }

    private static func parseReferenceDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value)
    }

    private static func parseReleaseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Toronto")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.isLenient = false
        return formatter.date(from: value)
    }

    private static func endOfReferenceMonth(_ date: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: date) else {
            return nil
        }
        return nextMonth.addingTimeInterval(-1)
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "fr_CA")
            )
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    private struct Market {
        let geographyMemberID: Int
        let displayName: String
        let regionAliases: Set<String>
        let localityAliases: [String]

        init(
            _ geographyMemberID: Int,
            _ displayName: String,
            _ regionAliases: Set<String>,
            _ localityAliases: [String]
        ) {
            self.geographyMemberID = geographyMemberID
            self.displayName = displayName
            self.regionAliases = regionAliases
            self.localityAliases = localityAliases
        }
    }

    private struct MarketSelection {
        let geographyMemberID: Int
        let displayName: String
    }

    private struct RequestPayload: Encodable {
        let productId: Int
        let coordinate: String
        let latestN: Int
    }

    private struct ResponsePayload: Decodable {
        let status: String
        let object: ResponseObject?
    }

    private struct ResponseObject: Decodable {
        let responseStatusCode: Int
        let productId: Int
        let coordinate: String
        let vectorId: Int
        let vectorDataPoint: [DataPoint]
    }

    private struct DataPoint: Decodable {
        let refPer: String
        let value: Double
        let decimals: Int
        let scalarFactorCode: Int
        let symbolCode: Int
        let statusCode: Int
        let securityLevelCode: Int
        let releaseTime: String
        let frequencyCode: Int
    }

    private struct ValidPoint {
        let referenceDate: Date
        let referencePeriodEndedAt: Date
        let releasedAt: Date
        let value: Double
    }
}

private struct APIErrorPayload: Decodable {
    let error: String?
}

private struct AlertContactPayload: Encodable {
    let name: String
    let phoneNumber: String

    init(_ contact: EmergencyContact) {
        name = contact.name
        phoneNumber = contact.phoneNumber
    }
}

private struct AlertLocationPayload: Encodable {
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        accuracyMeters = location.horizontalAccuracy
    }
}

private struct AlertTestPayload: Encodable {
    let driverName: String?
    let contact: AlertContactPayload
}

private struct LocationSharePayload: Encodable {
    let driverName: String?
    let contact: AlertContactPayload
    let location: AlertLocationPayload
}
