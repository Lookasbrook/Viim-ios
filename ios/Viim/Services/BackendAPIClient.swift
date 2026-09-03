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

    func sendAlertTest(
        contact: EmergencyContact,
        driverName: String?,
        contactsConsent: Bool
    ) async throws {
        let payload = AlertTestPayload(
            driverName: driverName,
            contact: AlertContactPayload(contact),
            contactsConsent: contactsConsent
        )
        try await post(payload, path: "alerts/test")
    }

    func shareLocation(
        contact: EmergencyContact,
        driverName: String?,
        location: CLLocation,
        contactsConsent: Bool
    ) async throws {
        let payload = LocationSharePayload(
            driverName: driverName,
            contact: AlertContactPayload(contact),
            location: AlertLocationPayload(location),
            contactsConsent: contactsConsent
        )
        try await post(payload, path: "alerts/location-share")
    }

    /// Alerte accident : declenche l'envoi WhatsApp au premier proche joignable,
    /// puis la cascade serveur (proche suivant apres 5 min sans lecture).
    /// `contactsConsent` est vrai seulement si TOUS les contacts vises ont
    /// l'attestation d'opt-in (`consentAcknowledgedAt`).
    func sendCollisionAlert(
        contacts: [EmergencyContact],
        driverName: String?,
        location: CLLocation,
        medicalProfile: MedicalProfile?
    ) async throws {
        let payload = CollisionPayload(
            driverName: driverName,
            contacts: contacts.map(AlertContactPayload.init),
            location: AlertLocationPayload(location),
            occurredAt: ISO8601DateFormatter().string(from: Date()),
            contactsConsent: !contacts.isEmpty && contacts.allSatisfy(\.hasProchesConsent),
            medicalProfile: medicalProfile.flatMap(CollisionMedicalPayload.init)
        )
        try await post(payload, path: "alerts/collision")
    }

    private func post<Payload: Encodable>(_ payload: Payload, path: String) async throws {
        guard let url = baseURL?.appending(path: path) else {
            throw BackendAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            ViimDiagnostics.log("api.post.transport path=/v1/\(path) urlError=\(urlError.code.rawValue)")
            throw BackendAPIError.network(urlError.code)
        } catch {
            ViimDiagnostics.log("api.post.transport path=/v1/\(path) error=unknown")
            throw BackendAPIError.transport
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAPIError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let apiError = try? JSONDecoder().decode(APIErrorPayload.self, from: data)
            ViimDiagnostics.log("api.post.failure path=/v1/\(path) status=\(httpResponse.statusCode) code=\(apiError?.error ?? "none")")
            throw BackendAPIError.apiStatus(statusCode: httpResponse.statusCode, code: apiError?.error)
        }
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
    let contactsConsent: Bool
}

private struct LocationSharePayload: Encodable {
    let driverName: String?
    let contact: AlertContactPayload
    let location: AlertLocationPayload
    let contactsConsent: Bool
}

private struct CollisionPayload: Encodable {
    let driverName: String?
    let contacts: [AlertContactPayload]
    let location: AlertLocationPayload
    let occurredAt: String
    let contactsConsent: Bool
    let medicalProfile: CollisionMedicalPayload?
}

private struct CollisionMedicalPayload: Encodable {
    let bloodType: String?
    let allergies: String?
    let conditions: String?
    let medications: String?
    let cnib: String?

    init?(_ profile: MedicalProfile) {
        guard profile.hasContent else {
            return nil
        }
        func trimmed(_ value: String) -> String? {
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        }
        bloodType = trimmed(profile.bloodType)
        allergies = trimmed(profile.allergies)
        conditions = trimmed(profile.conditions)
        medications = trimmed(profile.medications)
        cnib = trimmed(profile.cnib)
    }
}
