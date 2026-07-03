import Foundation
import Security

struct UserProfile: Codable, Equatable {
    let firstName: String
    let phoneNumber: String
    let vehicleType: VehicleType
    let vehicleBrand: String
    let vehicleModel: String
    let vehicleYear: String
    let calibrationTripCount: Int
    let synced: Bool

    var vehicleDisplayName: String {
        let parts = [vehicleBrand, vehicleModel, vehicleYear]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? vehicleType.fallbackDisplayName : parts.joined(separator: " ")
    }
}

struct EmergencyContact: Codable, Equatable {
    let name: String
    let phoneNumber: String
}

final class OnboardingStore: ObservableObject {
    private enum Keys {
        static let profile = "viim.userProfile.v1"
    }

    @Published private(set) var profile: UserProfile?

    private let userDefaults: UserDefaults
    private let secureStore: SecureEmergencyContactStore

    init(
        userDefaults: UserDefaults = .standard,
        secureStore: SecureEmergencyContactStore = .shared
    ) {
        self.userDefaults = userDefaults
        self.secureStore = secureStore
        self.profile = Self.loadProfile(from: userDefaults)
    }

    var isCompleted: Bool {
        profile != nil
    }

    func complete(profile: UserProfile, emergencyContact: EmergencyContact?) throws {
        let encodedProfile = try JSONEncoder().encode(profile)
        userDefaults.set(encodedProfile, forKey: Keys.profile)

        if let emergencyContact {
            try secureStore.save(emergencyContact)
        } else {
            try secureStore.delete()
        }

        self.profile = profile
    }

    private static func loadProfile(from userDefaults: UserDefaults) -> UserProfile? {
        guard let data = userDefaults.data(forKey: Keys.profile) else {
            return nil
        }
        return try? JSONDecoder().decode(UserProfile.self, from: data)
    }
}

final class SecureEmergencyContactStore {
    static let shared = SecureEmergencyContactStore()

    private let service = "com.yamstack.viim.secure"
    private let account = "emergency-contact-v1"

    private init() {}

    func save(_ contact: EmergencyContact) throws {
        let data = try JSONEncoder().encode(contact)
        let deleteStatus = deleteIgnoringMissing()
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(deleteStatus)
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    func delete() throws {
        let status = deleteIgnoringMissing()
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    private func deleteIgnoringMissing() -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        return SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: Error {
    case unhandledStatus(OSStatus)
}
