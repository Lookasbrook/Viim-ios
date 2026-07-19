import Foundation
import Security

enum SupportedCurrency: String, CaseIterable, Codable, Identifiable {
    case xof = "XOF"
    case cad = "CAD"
    case usd = "USD"
    case eur = "EUR"

    var id: String { rawValue }

    var fractionDigits: Int {
        self == .xof ? 0 : 2
    }

    var minorUnitScale: Double {
        fractionDigits == 0 ? 1 : 100
    }

    var defaultFuelPricePerLiter: Double {
        switch self {
        case .xof: 850
        case .cad: 1.70
        case .usd: 1.00
        case .eur: 1.80
        }
    }

    var displayName: String {
        let localizedName = Locale.current.localizedString(forCurrencyCode: rawValue) ?? rawValue
        return "\(localizedName) (\(rawValue))"
    }

    static func preferred(for locale: Locale) -> SupportedCurrency {
        let code = (locale as NSLocale).object(forKey: .currencyCode) as? String
        return code.flatMap(SupportedCurrency.init(rawValue:)) ?? .xof
    }
}

struct FuelSettings: Codable, Equatable {
    let currency: SupportedCurrency
    let pricePerLiter: Double

    init(currency: SupportedCurrency, pricePerLiter: Double) {
        self.currency = currency
        self.pricePerLiter = pricePerLiter
    }

    static func defaults(for locale: Locale = .current) -> FuelSettings {
        let currency = SupportedCurrency.preferred(for: locale)
        return FuelSettings(
            currency: currency,
            pricePerLiter: currency.defaultFuelPricePerLiter
        )
    }

    func costMinorUnits(for liters: Double?) -> Int? {
        guard let liters,
              liters.isFinite,
              liters >= 0,
              pricePerLiter.isFinite,
              pricePerLiter >= 0 else {
            return nil
        }

        return Int((liters * pricePerLiter * currency.minorUnitScale).rounded())
    }
}

struct UserProfile: Codable, Equatable {
    let firstName: String
    let phoneNumber: String
    let vehicleType: VehicleType
    let vehicleBrand: String
    let vehicleModel: String
    let vehicleYear: String
    let synced: Bool
    // Odometre declare par l'utilisateur (km) et date de la declaration.
    // Le kilometrage courant = base + km des trajets valides depuis cette
    // date ; il progresse donc automatiquement avec la conduite.
    var odometerBaselineKm: Double? = nil
    var odometerBaselineDate: Date? = nil

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
        static let fuelSettings = "viim.fuelSettings.v1"
    }

    @Published private(set) var profile: UserProfile?
    @Published private(set) var fuelSettings: FuelSettings

    private let userDefaults: UserDefaults
    private let secureStore: SecureEmergencyContactStore

    init(
        userDefaults: UserDefaults = .standard,
        secureStore: SecureEmergencyContactStore = .shared,
        locale: Locale = .current
    ) {
        self.userDefaults = userDefaults
        self.secureStore = secureStore
        self.profile = Self.loadProfile(from: userDefaults)
        self.fuelSettings = Self.loadFuelSettings(from: userDefaults) ?? .defaults(for: locale)
    }

    var isCompleted: Bool {
        profile != nil
    }

    func complete(profile: UserProfile, emergencyContact: EmergencyContact?) throws {
        let encodedProfile = try JSONEncoder().encode(profile)
        userDefaults.set(encodedProfile, forKey: Keys.profile)

        if let emergencyContact {
            try secureStore.saveAll([emergencyContact])
        } else {
            try secureStore.delete()
        }

        self.profile = profile
    }

    /// Redeclare l'odometre : la nouvelle valeur devient la base et les
    /// trajets valides posterieurs a cette date s'y additionnent.
    func updateOdometer(baselineKm: Double, date: Date = Date()) throws {
        guard var updatedProfile = profile else {
            return
        }
        guard baselineKm.isFinite, baselineKm >= 0, baselineKm < 3_000_000 else {
            throw OdometerError.invalidValue
        }

        updatedProfile.odometerBaselineKm = baselineKm
        updatedProfile.odometerBaselineDate = date
        let encodedProfile = try JSONEncoder().encode(updatedProfile)
        userDefaults.set(encodedProfile, forKey: Keys.profile)
        profile = updatedProfile
    }

    func updateFuelSettings(_ settings: FuelSettings) throws {
        guard settings.pricePerLiter.isFinite, settings.pricePerLiter >= 0 else {
            throw FuelSettingsError.invalidPrice
        }

        let encodedSettings = try JSONEncoder().encode(settings)
        userDefaults.set(encodedSettings, forKey: Keys.fuelSettings)
        fuelSettings = settings
    }

    private static func loadProfile(from userDefaults: UserDefaults) -> UserProfile? {
        guard let data = userDefaults.data(forKey: Keys.profile) else {
            return nil
        }
        return try? JSONDecoder().decode(UserProfile.self, from: data)
    }

    private static func loadFuelSettings(from userDefaults: UserDefaults) -> FuelSettings? {
        guard let data = userDefaults.data(forKey: Keys.fuelSettings) else {
            return nil
        }
        return try? JSONDecoder().decode(FuelSettings.self, from: data)
    }
}

enum FuelSettingsError: Error {
    case invalidPrice
}

enum OdometerError: Error {
    case invalidValue
}

final class SecureEmergencyContactStore {
    static let shared = SecureEmergencyContactStore()

    /// Nombre maximal de proches a prevenir en cas de besoin.
    static let maximumContacts = 4

    private let service = "com.yamstack.viim.secure"
    private let legacyAccount = "emergency-contact-v1"
    private let account = "emergency-contacts-v2"

    private init() {}

    func saveAll(_ contacts: [EmergencyContact]) throws {
        guard contacts.count <= Self.maximumContacts else {
            throw EmergencyContactStoreError.tooManyContacts
        }
        guard !contacts.isEmpty else {
            try delete()
            return
        }

        let data = try JSONEncoder().encode(contacts)
        try write(data, account: account)
        // L'ancien emplacement mono-contact ne doit plus faire autorite.
        _ = deleteIgnoringMissing(account: legacyAccount)
    }

    func save(_ contact: EmergencyContact) throws {
        var contacts = (try? loadAll()) ?? []
        if let existingIndex = contacts.firstIndex(where: { $0.phoneNumber == contact.phoneNumber }) {
            contacts[existingIndex] = contact
        } else {
            contacts.insert(contact, at: 0)
        }
        try saveAll(Array(contacts.prefix(Self.maximumContacts)))
    }

    func delete() throws {
        for accountKey in [account, legacyAccount] {
            let status = deleteIgnoringMissing(account: accountKey)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.unhandledStatus(status)
            }
        }
    }

    func loadAll() throws -> [EmergencyContact] {
        if let data = try read(account: account) {
            return try JSONDecoder().decode([EmergencyContact].self, from: data)
        }

        // Migration : un contact enregistre avant la v2 reste disponible.
        if let legacyData = try read(account: legacyAccount) {
            let contact = try JSONDecoder().decode(EmergencyContact.self, from: legacyData)
            return [contact]
        }

        return []
    }

    func load() throws -> EmergencyContact? {
        try loadAll().first
    }

    private func write(_ data: Data, account: String) throws {
        let deleteStatus = deleteIgnoringMissing(account: account)
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

    private func read(account: String) throws -> Data? {
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

        return data
    }

    private func deleteIgnoringMissing(account: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        return SecItemDelete(query as CFDictionary)
    }
}

enum EmergencyContactStoreError: Error {
    case tooManyContacts
}

enum KeychainError: Error {
    case unhandledStatus(OSStatus)
}
