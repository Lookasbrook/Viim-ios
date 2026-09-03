import Foundation
import Security

enum SupportedCountry: String, CaseIterable, Codable, Hashable, Identifiable {
    case burkinaFaso = "BF"
    case canada = "CA"
    case other = "OTHER"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .burkinaFaso:
            return String(localized: "country.burkinaFaso")
        case .canada:
            return String(localized: "country.canada")
        case .other:
            return String(localized: "country.other")
        }
    }

    var phonePrefix: String {
        switch self {
        case .burkinaFaso: "+226 "
        case .canada: "+1 "
        case .other: "+"
        }
    }

    static func preferred(for locale: Locale = .current) -> SupportedCountry {
        switch locale.region?.identifier {
        case "BF": .burkinaFaso
        case "CA": .canada
        default: .other
        }
    }

    func matches(phoneNumber: String) -> Bool {
        switch self {
        case .burkinaFaso:
            return phoneNumber.hasPrefix("+226")
        case .canada:
            return phoneNumber.hasPrefix("+1")
        case .other:
            return !phoneNumber.hasPrefix("+226") && !phoneNumber.hasPrefix("+1")
        }
    }
}

struct EmergencyNumbers: Equatable {
    let firefighters: String?
    let police: String?
    let sourceIdentifier: String
}

enum EmergencyNumberCatalog {
    static func numbers(for country: SupportedCountry) -> EmergencyNumbers {
        switch country {
        case .burkinaFaso:
            return EmergencyNumbers(
                firefighters: "18",
                police: "17",
                sourceIdentifier: "police.gov.bf"
            )
        case .canada:
            return EmergencyNumbers(
                firefighters: "911",
                police: "911",
                sourceIdentifier: "canada.ca"
            )
        case .other:
            return EmergencyNumbers(
                firefighters: nil,
                police: nil,
                sourceIdentifier: "unavailable"
            )
        }
    }
}

enum SupportedCurrency: String, CaseIterable, Codable, Hashable, Identifiable {
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

enum FuelPriceSource: String, Codable, Hashable {
    case userProvided
    case officialPublicData
    case unverifiedDefault
}

enum VehicleFuelType: String, CaseIterable, Codable, Hashable, Identifiable {
    case gasoline
    case diesel
    case gasolineHybrid
    case dieselHybrid
    case electric

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gasoline: String(localized: "vehicle.fuelType.gasoline")
        case .diesel: String(localized: "vehicle.fuelType.diesel")
        case .gasolineHybrid: String(localized: "vehicle.fuelType.gasolineHybrid")
        case .dieselHybrid: String(localized: "vehicle.fuelType.dieselHybrid")
        case .electric: String(localized: "vehicle.fuelType.electric")
        }
    }

    var supportsLiquidFuelEstimate: Bool {
        self != .electric
    }
}

struct FuelSettings: Codable, Equatable, Hashable {
    /// Un prix plus ancien n'est plus utilise pour figer un cout de trajet.
    /// L'utilisateur peut toujours le voir et le confirmer a nouveau.
    static let maximumSnapshotAge: TimeInterval = 30 * 24 * 60 * 60
    /// Les sources publiques hebdomadaires doivent être rafraîchies plus souvent
    /// qu'un prix directement confirmé par l'utilisateur.
    static let maximumOfficialSnapshotAge: TimeInterval = 14 * 24 * 60 * 60
    static let maximumFutureClockSkew: TimeInterval = 5 * 60

    let currency: SupportedCurrency
    let pricePerLiter: Double
    let source: FuelPriceSource?
    let capturedAt: Date?
    let fuelType: VehicleFuelType?
    let sourceIdentifier: String?
    let sourceURL: URL?
    let locality: String?

    init(
        currency: SupportedCurrency,
        pricePerLiter: Double,
        source: FuelPriceSource = .userProvided,
        capturedAt: Date? = nil,
        fuelType: VehicleFuelType? = nil,
        sourceIdentifier: String? = nil,
        sourceURL: URL? = nil,
        locality: String? = nil
    ) {
        self.currency = currency
        self.pricePerLiter = pricePerLiter
        self.source = source
        self.capturedAt = capturedAt
        self.fuelType = fuelType
        self.sourceIdentifier = sourceIdentifier
        self.sourceURL = sourceURL
        self.locality = locality
    }

    static func defaults(for locale: Locale = .current) -> FuelSettings {
        let currency = SupportedCurrency.preferred(for: locale)
        return FuelSettings(
            currency: currency,
            pricePerLiter: currency.defaultFuelPricePerLiter,
            source: .unverifiedDefault
        )
    }

    var canSnapshotCost: Bool {
        source == .userProvided || source == .officialPublicData
    }

    func canSnapshotCost(at date: Date) -> Bool {
        guard canSnapshotCost, let capturedAt else {
            return false
        }

        let age = date.timeIntervalSince(capturedAt)
        let maximumAge = source == .officialPublicData
            ? Self.maximumOfficialSnapshotAge
            : Self.maximumSnapshotAge
        return age >= -Self.maximumFutureClockSkew && age <= maximumAge
    }

    func costMinorUnits(for liters: Double?) -> Int? {
        guard canSnapshotCost,
              let liters,
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
    var countryCode: String? = nil
    /// Choix explicite de l'utilisateur. `nil` conserve la compatibilite des
    /// profils crees avant l'ajout de cette information.
    var fuelType: VehicleFuelType? = nil

    var vehicleDisplayName: String {
        let parts = [vehicleBrand, vehicleModel, vehicleYear]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? vehicleType.fallbackDisplayName : parts.joined(separator: " ")
    }

    var country: SupportedCountry {
        if let countryCode,
           let country = SupportedCountry(rawValue: countryCode) {
            return country
        }
        if phoneNumber.hasPrefix("+226") {
            return .burkinaFaso
        }
        if phoneNumber.hasPrefix("+1") {
            return .canada
        }
        return .other
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

    func updateVehicleFuelType(_ fuelType: VehicleFuelType) throws {
        guard var updatedProfile = profile, updatedProfile.vehicleType != .velo else {
            return
        }

        updatedProfile.fuelType = fuelType
        userDefaults.set(try JSONEncoder().encode(updatedProfile), forKey: Keys.profile)
        profile = updatedProfile

        guard fuelSettings.fuelType != fuelType else {
            return
        }

        // Un prix saisi pour l'essence ne doit jamais etre reutilise pour le
        // diesel apres un changement de motorisation.
        let resetSettings = FuelSettings(
            currency: fuelSettings.currency,
            pricePerLiter: fuelSettings.currency.defaultFuelPricePerLiter,
            source: .unverifiedDefault,
            fuelType: fuelType
        )
        userDefaults.set(try JSONEncoder().encode(resetSettings), forKey: Keys.fuelSettings)
        fuelSettings = resetSettings
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
