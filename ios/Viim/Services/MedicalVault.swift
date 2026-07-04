import Foundation
import Security

struct MedicalProfile: Codable, Equatable {
    var bloodType: String
    var allergies: String
    var conditions: String
    var medications: String
    var cnib: String

    static let empty = MedicalProfile(
        bloodType: "",
        allergies: "",
        conditions: "",
        medications: "",
        cnib: ""
    )

    var isComplete: Bool {
        !bloodType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

final class SecureMedicalProfileStore {
    static let shared = SecureMedicalProfileStore()

    private let service = "com.yamstack.viim.secure"
    private let account = "medical-profile-v1"

    private init() {}

    func save(_ profile: MedicalProfile) throws {
        let data = try JSONEncoder().encode(profile)
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

    func load() throws -> MedicalProfile? {
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

        return try JSONDecoder().decode(MedicalProfile.self, from: data)
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
