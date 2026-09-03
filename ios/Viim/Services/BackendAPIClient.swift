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
    private static let ontarioSourceIdentifier = "government_of_ontario_fuel_price_survey"
    private static let ontarioSourceHosts = Set(["ontario.ca", "www.ontario.ca"])
    private static let ontarioSourcePath = "/v1/files/fuel-prices/fueltypesall.csv"
    private static let maximumSourceAge: TimeInterval = 14 * 24 * 60 * 60
    private static let maximumRetrievalAge: TimeInterval = 24 * 60 * 60
    private static let maximumFutureClockSkew: TimeInterval = 5 * 60
    private static let plausibleOntarioPriceRange = 0.20...5.00

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
        let acceptedRegions = normalizedRegion == "ONTARIO" ? Set(["ON", "ONTARIO"]) : Set([normalizedRegion])
        let sourceAge = now.timeIntervalSince(observedAt)
        let retrievalAge = now.timeIntervalSince(retrievedAt)
        let chronologyIsValid = observedAt <= retrievedAt.addingTimeInterval(Self.maximumFutureClockSkew)
        let normalizedQuoteCountry = countryCode.uppercased()
        let normalizedQuoteRegion = regionCode.uppercased()

        return normalizedQuoteCountry == "CA" &&
            ["ON", "ONTARIO"].contains(normalizedQuoteRegion) &&
            normalizedQuoteCountry == normalizedCountry &&
            acceptedRegions.contains(normalizedQuoteRegion) &&
            requestedFuelType == fuelType &&
            currency == .cad &&
            Self.plausibleOntarioPriceRange.contains(pricePerLiter) &&
            !locality.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            locality.count <= 80 &&
            locality.rangeOfCharacter(from: .controlCharacters) == nil &&
            sourceAge >= -Self.maximumFutureClockSkew &&
            sourceAge <= Self.maximumSourceAge &&
            retrievalAge >= -Self.maximumFutureClockSkew &&
            retrievalAge <= Self.maximumRetrievalAge &&
            chronologyIsValid &&
            hasTrustedOfficialSource
    }

    fileprivate var hasTrustedOfficialSource: Bool {
        source == Self.ontarioSourceIdentifier &&
            sourceURL.scheme?.lowercased() == "https" &&
            sourceURL.host.map { Self.ontarioSourceHosts.contains($0.lowercased()) } == true &&
            sourceURL.port == nil &&
            sourceURL.user == nil &&
            sourceURL.password == nil &&
            sourceURL.path == Self.ontarioSourcePath &&
            sourceURL.query == nil &&
            sourceURL.fragment == nil
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

    private static let sourceURL = URL(string: "https://www.ontario.ca/v1/files/fuel-prices/fueltypesall.csv")!
    private static let redirectedSourceHost = "prod-energy-fuel-prices.s3.amazonaws.com"
    private static let maximumResponseBytes = 2_000_000
    private static let requestTimeout: TimeInterval = 10
    private static let sourceIdentifier = "government_of_ontario_fuel_price_survey"
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
            "api.fuelPrice.ontario.success region=ON fuelType=\(fuelType.rawValue) observedAt=\(latest.date.timeIntervalSince1970)"
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
        let normalized = normalize(locality)
        let markets: [([String], [String])] = [
            (["ottawa"], ["Ottawa"]),
            (["toronto"], ["Toronto West/Ouest", "Toronto East/Est"]),
            (["windsor"], ["Windsor"]),
            (["london"], ["London"]),
            (["peterborough"], ["Peterborough"]),
            (["stcatharines", "saintcatharines"], ["St. Catharine's"]),
            (["sudbury", "greatersudbury"], ["Sudbury"]),
            (["saultstemarie", "saultsaintemarie"], ["Sault Saint Marie"]),
            (["thunderbay"], ["Thunder Bay"]),
            (["northbay"], ["North Bay"]),
            (["timmins"], ["Timmins"]),
            (["kenora"], ["Kenora"]),
            (["parrysound"], ["Parry Sound"])
        ]
        let match = markets.first { aliases, _ in
            aliases.contains { normalized.contains($0) }
        }
        let columns = match?.1 ?? ["Ontario Average/Moyenne provinciale"]
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
            match == nil ? "Ontario" : locality.trimmingCharacters(in: .whitespacesAndNewlines),
            values.reduce(0, +) / Double(values.count)
        )
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_CA"))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
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
