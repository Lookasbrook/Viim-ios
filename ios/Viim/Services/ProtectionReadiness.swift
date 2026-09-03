import Combine
import Foundation

enum TripCollectionProtectionState: Equatable {
    case configurationRequired(LocationCollectionReadiness)
    case standby
    case collecting

    var diagnosticValue: String {
        switch self {
        case .configurationRequired(let readiness):
            return "configurationRequired:\(readiness.rawValue)"
        case .standby:
            return "standby"
        case .collecting:
            return "collecting"
        }
    }
}

/// SafetyKit et sa chaine de livraison ne sont pas encore livres. Garder cet
/// etat explicite evite qu'un moteur de calibration local soit presente comme
/// une fonction de secours.
enum AutomaticCollisionProtectionState: String, Equatable {
    case unavailable
}

enum ManualAlertProtectionState: Equatable {
    case unavailable
    case notConfigured
    case needsCorrection(validContactCount: Int, invalidContactCount: Int)
    case configuredUnverified(contactCount: Int)

    var diagnosticValue: String {
        switch self {
        case .unavailable:
            return "unavailable"
        case .notConfigured:
            return "notConfigured"
        case .needsCorrection(let validContactCount, let invalidContactCount):
            return "needsCorrection:valid=\(validContactCount):invalid=\(invalidContactCount)"
        case .configuredUnverified(let contactCount):
            return "configuredUnverified:count=\(contactCount)"
        }
    }
}

enum ProtectionNetworkState: String, Equatable {
    case online
    case offline
}

/// Source de verite commune aux ecrans qui parlent de protection.
///
/// Ce snapshot ne transforme jamais une configuration locale en preuve de
/// securite. En particulier, un contact valide reste `configuredUnverified`
/// tant que l'app ne dispose pas d'un accuse de reception fournisseur.
struct ProtectionReadinessSnapshot: Equatable {
    let tripCollection: TripCollectionProtectionState
    let automaticCollision: AutomaticCollisionProtectionState
    let manualAlerts: ManualAlertProtectionState
    let network: ProtectionNetworkState

    static func evaluate(
        locationReadiness: LocationCollectionReadiness,
        isLocationMonitoring: Bool,
        isPassiveWakeupMonitoring: Bool,
        emergencyContacts: [EmergencyContact]?,
        isOnline: Bool
    ) -> Self {
        let tripCollection: TripCollectionProtectionState
        if !locationReadiness.isReadyForBackground {
            tripCollection = .configurationRequired(locationReadiness)
        } else if isLocationMonitoring {
            tripCollection = .collecting
        } else if isPassiveWakeupMonitoring {
            tripCollection = .standby
        } else {
            // Etat defensif : `ready` implique aujourd'hui un reveil passif,
            // mais le snapshot reste honnete si ce contrat change.
            tripCollection = .configurationRequired(.passiveWakeupPending)
        }

        guard let emergencyContacts else {
            return Self(
                tripCollection: tripCollection,
                automaticCollision: .unavailable,
                manualAlerts: .unavailable,
                network: isOnline ? .online : .offline
            )
        }

        let validContactCount = emergencyContacts.reduce(into: 0) { count, contact in
            if BurkinaPhoneNumber.normalizedContact(contact) != nil {
                count += 1
            }
        }
        let invalidContactCount = emergencyContacts.count - validContactCount
        let manualAlerts: ManualAlertProtectionState
        if emergencyContacts.isEmpty {
            manualAlerts = .notConfigured
        } else if invalidContactCount > 0 {
            manualAlerts = .needsCorrection(
                validContactCount: validContactCount,
                invalidContactCount: invalidContactCount
            )
        } else {
            manualAlerts = .configuredUnverified(contactCount: validContactCount)
        }

        return Self(
            tripCollection: tripCollection,
            automaticCollision: .unavailable,
            manualAlerts: manualAlerts,
            network: isOnline ? .online : .offline
        )
    }

    var diagnosticSummary: String {
        "trip=\(tripCollection.diagnosticValue) "
            + "collision=\(automaticCollision.rawValue) "
            + "manualAlerts=\(manualAlerts.diagnosticValue) "
            + "network=\(network.rawValue)"
    }
}

@MainActor
final class ProtectionReadinessService: ObservableObject {
    @Published private(set) var snapshot: ProtectionReadinessSnapshot

    private let emergencyContactsProvider: () -> [EmergencyContact]?
    private var emergencyContacts: [EmergencyContact]?
    private var locationReadiness: LocationCollectionReadiness
    private var isLocationMonitoring: Bool
    private var isPassiveWakeupMonitoring: Bool
    private var isOnline: Bool
    private var cancellables = Set<AnyCancellable>()

    init(
        locationService: LocationService,
        networkStatusService: NetworkStatusService,
        emergencyContactsProvider: @escaping () -> [EmergencyContact]? = {
            try? SecureEmergencyContactStore.shared.loadAll()
        }
    ) {
        self.emergencyContactsProvider = emergencyContactsProvider
        let contacts = emergencyContactsProvider()
        emergencyContacts = contacts
        locationReadiness = locationService.collectionReadiness
        isLocationMonitoring = locationService.isMonitoring
        isPassiveWakeupMonitoring = locationService.isPassiveWakeupMonitoring
        isOnline = networkStatusService.isOnline
        snapshot = ProtectionReadinessSnapshot.evaluate(
            locationReadiness: locationReadiness,
            isLocationMonitoring: isLocationMonitoring,
            isPassiveWakeupMonitoring: isPassiveWakeupMonitoring,
            emergencyContacts: contacts,
            isOnline: isOnline
        )

        Publishers.CombineLatest4(
            locationService.$collectionReadiness,
            locationService.$isMonitoring,
            locationService.$isPassiveWakeupMonitoring,
            networkStatusService.$isOnline
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] values in
            guard let self else { return }
            let (readiness, isMonitoring, isPassiveWakeupMonitoring, isOnline) = values
            self.locationReadiness = readiness
            self.isLocationMonitoring = isMonitoring
            self.isPassiveWakeupMonitoring = isPassiveWakeupMonitoring
            self.isOnline = isOnline
            self.publishIfChanged(
                locationReadiness: readiness,
                isLocationMonitoring: isMonitoring,
                isPassiveWakeupMonitoring: isPassiveWakeupMonitoring,
                isOnline: isOnline
            )
        }
        .store(in: &cancellables)

        ViimDiagnostics.log("protection.readiness \(snapshot.diagnosticSummary)")
    }

    func refreshEmergencyContacts() {
        guard let contacts = emergencyContactsProvider() else {
            markEmergencyContactsUnavailable()
            return
        }
        updateEmergencyContacts(contacts)
    }

    func updateEmergencyContacts(_ contacts: [EmergencyContact]) {
        emergencyContacts = contacts
        republishCurrentInputs()
    }

    func markEmergencyContactsUnavailable() {
        emergencyContacts = nil
        republishCurrentInputs()
    }

    private func republishCurrentInputs() {
        publishIfChanged(
            locationReadiness: locationReadiness,
            isLocationMonitoring: isLocationMonitoring,
            isPassiveWakeupMonitoring: isPassiveWakeupMonitoring,
            isOnline: isOnline
        )
    }

    private func publishIfChanged(
        locationReadiness: LocationCollectionReadiness,
        isLocationMonitoring: Bool,
        isPassiveWakeupMonitoring: Bool,
        isOnline: Bool
    ) {
        let next = ProtectionReadinessSnapshot.evaluate(
            locationReadiness: locationReadiness,
            isLocationMonitoring: isLocationMonitoring,
            isPassiveWakeupMonitoring: isPassiveWakeupMonitoring,
            emergencyContacts: emergencyContacts,
            isOnline: isOnline
        )
        guard next != snapshot else { return }
        snapshot = next
        ViimDiagnostics.log("protection.readiness \(next.diagnosticSummary)")
    }

}
