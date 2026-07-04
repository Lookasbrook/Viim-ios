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

    var normalizedForBurkina: EmergencyContact? {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty,
              let normalizedPhone = BurkinaPhoneNumber.normalized(phoneNumber) else {
            return nil
        }
        return EmergencyContact(name: cleanedName, phoneNumber: normalizedPhone)
    }
}

enum BurkinaPhoneNumber {
    static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let digits = trimmed.filter(\.isNumber)
        let localDigits: Substring

        if digits.hasPrefix("00226") {
            localDigits = digits.dropFirst(5)
        } else if digits.hasPrefix("226") {
            localDigits = digits.dropFirst(3)
        } else {
            localDigits = digits[...]
        }

        guard localDigits.count == 8,
              localDigits.allSatisfy(\.isNumber) else {
            return nil
        }

        return "+226\(localDigits)"
    }
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

    func load() throws -> EmergencyContact? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = item as? Data else {
            throw KeychainError.unhandledStatus(status)
        }

        return try JSONDecoder().decode(EmergencyContact.self, from: data)
    }

    func loadNormalizedForBurkina() throws -> EmergencyContact? {
        guard let contact = try load(),
              let normalizedContact = contact.normalizedForBurkina else {
            return nil
        }

        if normalizedContact != contact {
            try save(normalizedContact)
        }

        return normalizedContact
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
