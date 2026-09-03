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
        fuelType: VehicleFuelType
    ) async throws -> PublicFuelPriceQuote {
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

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await perform(request, operation: "api.fuelPrice")
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAPIError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let apiError = try? JSONDecoder().decode(APIErrorPayload.self, from: data)
            throw BackendAPIError.apiStatus(statusCode: httpResponse.statusCode, code: apiError?.error)
        }

        do {
            let quote = try PublicFuelPriceQuote.decode(from: data)
            guard quote.matchesRequest(countryCode: countryCode, regionCode: regionCode),
                  quote.hasTrustedOfficialSource else {
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
}

struct PublicFuelPriceQuote: Equatable {
    private static let ontarioSourceIdentifier = "government_of_ontario_fuel_price_survey"
    private static let ontarioSourceHosts = Set(["ontario.ca", "www.ontario.ca"])

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

    fileprivate func matchesRequest(countryCode requestedCountry: String, regionCode requestedRegion: String) -> Bool {
        let normalizedCountry = requestedCountry.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedRegion = requestedRegion
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let acceptedRegions = normalizedRegion == "ONTARIO" ? Set(["ON", "ONTARIO"]) : Set([normalizedRegion])
        return countryCode.uppercased() == normalizedCountry && acceptedRegions.contains(regionCode.uppercased())
    }

    fileprivate var hasTrustedOfficialSource: Bool {
        source == Self.ontarioSourceIdentifier &&
            sourceURL.scheme?.lowercased() == "https" &&
            sourceURL.host.map(Self.ontarioSourceHosts.contains) == true
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
