import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct AssistanceView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var locationService: LocationService
    @State private var emergencyContacts: [EmergencyContact] = []
    @State private var hasInvalidEmergencyContact = false
    @State private var medicalProfile: MedicalProfile?
    @State private var isSendingTest = false
    @State private var alertMessage: AssistanceAlertMessage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    AssistanceHero()

                    ViimCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("assistance.realtime.title", systemImage: "dot.radiowaves.left.and.right")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(ViimColors.text)
                                Spacer()
                                ViimChip(titleKey: emergencyContactStatusKey, style: emergencyContactStatusStyle)
                            }
                            Text("assistance.realtime.detail")
                                .font(.caption)
                                .foregroundStyle(ViimColors.muted)
                                .fixedSize(horizontal: false, vertical: true)

                            Button {
                                sendTestWhatsApp()
                            } label: {
                                Label(isSendingTest ? "assistance.test.sending" : "assistance.test.action", systemImage: "paperplane.fill")
                                    .font(.caption.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 40)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ViimColors.red)
                            .disabled(emergencyContacts.isEmpty || isSendingTest)
                        }
                    }

                    ViimCard {
                        VStack(spacing: 0) {
                            NavigationLink {
                                AssistanceLocationView()
                            } label: {
                                AssistanceListRow(icon: "location.fill", titleKey: "assistance.location.title", detailKey: "assistance.row.open", tint: ViimColors.blue)
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                EmergencyContactsView(onChange: reloadSecureData)
                            } label: {
                                AssistanceListRow(icon: "person.2.fill", titleKey: "assistance.contacts.title", detailKey: emergencyContactDetailKey, tint: ViimColors.navy)
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                MedicalProfileView(onChange: reloadSecureData)
                            } label: {
                                AssistanceListRow(icon: "cross.case.fill", titleKey: "assistance.medical.title", detailKey: medicalProfile?.hasContent == true ? "assistance.medical.savedStatus" : "assistance.medical.status", tint: ViimColors.green)
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                AssistanceDetailView(icon: "doc.text.fill", titleKey: "assistance.report.title", detailKey: "assistance.report.detail", tint: ViimColors.gold)
                            } label: {
                                AssistanceListRow(icon: "doc.text.fill", titleKey: "assistance.report.title", detailKey: "assistance.row.open", tint: ViimColors.gold)
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                AssistanceDetailView(icon: "wrench.and.screwdriver.fill", titleKey: "assistance.towing.title", detailKey: "assistance.towing.detail", tint: ViimColors.warning)
                            } label: {
                                AssistanceListRow(icon: "wrench.and.screwdriver.fill", titleKey: "assistance.towing.title", detailKey: "assistance.row.open", tint: ViimColors.warning, showsDivider: false)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    SectionHeader(titleKey: "assistance.emergency.section")

                    HStack(spacing: 10) {
                        EmergencyButton(
                            titleKey: "assistance.firefighters.title",
                            phoneNumber: emergencyNumbers.firefighters,
                            tint: ViimColors.red
                        )
                        EmergencyButton(
                            titleKey: "assistance.police.title",
                            phoneNumber: emergencyNumbers.police,
                            tint: ViimColors.navy
                        )
                    }

                    ViimCard {
                        NavigationLink {
                            AssistanceDetailView(icon: "cross.vial.fill", titleKey: "assistance.hospitals.title", detailKey: "assistance.hospitals.screen.detail", tint: ViimColors.red)
                        } label: {
                            AssistanceListRow(icon: "cross.vial.fill", titleKey: "assistance.hospitals.title", detailKey: "assistance.hospitals.detail", tint: ViimColors.red, showsDivider: false)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("assistance.medical.privacy")
                        .font(.caption)
                        .foregroundStyle(ViimColors.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)

                    Text("assistance.footer.publisher")
                        .font(.caption2)
                        .foregroundStyle(Color(hex: 0xA9B8C6))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(ViimColors.background.ignoresSafeArea())
            .navigationTitle("assistance.title")
            .task {
                reloadSecureData()
            }
            .alert(item: $alertMessage) { message in
                Alert(
                    title: Text(message.titleKey),
                    message: Text(message.detailKey),
                    dismissButton: .default(Text("common.ok"))
                )
            }
        }
    }

    private func reloadSecureData() {
        let storedContacts = (try? SecureEmergencyContactStore.shared.loadAll()) ?? []
        emergencyContacts = storedContacts.compactMap(BurkinaPhoneNumber.normalizedContact)
        hasInvalidEmergencyContact = !storedContacts.isEmpty && emergencyContacts.isEmpty
        medicalProfile = try? SecureMedicalProfileStore.shared.load()
    }

    private var emergencyNumbers: EmergencyNumbers {
        EmergencyNumberCatalog.numbers(
            for: onboardingStore.profile?.country ?? .other
        )
    }

    private var emergencyContactStatusKey: LocalizedStringKey {
        if hasInvalidEmergencyContact {
            return "assistance.contacts.needsCorrection"
        }
        return emergencyContacts.isEmpty ? "status.disabled" : "status.enabled"
    }

    private var emergencyContactDetailKey: LocalizedStringKey {
        if hasInvalidEmergencyContact {
            return "assistance.contacts.needsCorrection"
        }
        if emergencyContacts.isEmpty {
            return "assistance.contacts.status"
        }
        return "assistance.contacts.configuredCount \(emergencyContacts.count)"
    }

    private var emergencyContactStatusStyle: ViimChip.Style {
        if hasInvalidEmergencyContact {
            return .danger
        }
        return emergencyContacts.isEmpty ? .neutral : .success
    }

    private func sendTestWhatsApp() {
        guard !emergencyContacts.isEmpty else {
            alertMessage = AssistanceAlertMessage(titleKey: "assistance.error.title", detailKey: hasInvalidEmergencyContact ? "assistance.contacts.correctRequired" : "assistance.test.missingContact")
            return
        }

        isSendingTest = true
        let contacts = emergencyContacts
        let driverName = onboardingStore.profile?.firstName
        Task { @MainActor in
            defer { isSendingTest = false }
            var firstError: Error?
            var sentCount = 0
            for contact in contacts {
                do {
                    try await BackendAPIClient.shared.sendAlertTest(
                        contact: contact,
                        driverName: driverName
                    )
                    sentCount += 1
                } catch {
                    if firstError == nil {
                        firstError = error
                    }
                }
            }

            if sentCount == contacts.count {
                alertMessage = AssistanceAlertMessage(titleKey: "assistance.test.success.title", detailKey: "assistance.test.success.detail")
            } else if sentCount > 0 {
                alertMessage = AssistanceAlertMessage(
                    titleKey: "assistance.send.partial.title",
                    detailKey: "assistance.send.partial.detail"
                )
            } else if let firstError {
                alertMessage = AssistanceAlertMessage(titleKey: "assistance.error.title", detailKey: AssistanceAPIErrorPresenter.detailKey(for: firstError, fallbackKey: "assistance.test.error"))
            }
        }
    }
}

private struct AssistanceHero: View {
    var body: some View {
        ZStack(alignment: .leading) {
            LinearGradient(
                colors: [Color(hex: 0x7A1010), ViimColors.red],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 78, weight: .bold))
                .foregroundStyle(.white.opacity(0.13))
                .offset(x: 210, y: 10)
            VStack(alignment: .leading, spacing: 6) {
                Text("assistance.title")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("assistance.hero.detail")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .padding(18)
        }
        .frame(height: 132)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct AssistanceListRow: View {
    let icon: String
    let titleKey: LocalizedStringKey
    let detailKey: LocalizedStringKey
    let tint: Color
    var showsDivider = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.12))
                    .clipShape(Circle())
                Text(titleKey)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ViimColors.text)
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    Text(detailKey)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ViimColors.muted)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(ViimColors.muted.opacity(0.7))
                }
            }
            .frame(minHeight: 48)

            if showsDivider {
                Divider()
                    .padding(.leading, 45)
            }
        }
    }
}

private struct SectionHeader: View {
    let titleKey: LocalizedStringKey

    var body: some View {
        Text(titleKey)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(ViimColors.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
    }
}

private struct EmergencyButton: View {
    @Environment(\.openURL) private var openURL
    let titleKey: LocalizedStringKey
    let phoneNumber: String?
    let tint: Color

    var body: some View {
        Button {
            if let phoneNumber,
               let url = URL(string: "tel://\(phoneNumber)") {
                openURL(url)
            }
        } label: {
            VStack(spacing: 4) {
                Text(titleKey)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(phoneNumber.map {
                    String.localizedStringWithFormat(
                        String(localized: "assistance.emergency.call"),
                        $0
                    )
                } ?? String(localized: "assistance.emergency.unavailable"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(tint)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(phoneNumber == nil)
        .opacity(phoneNumber == nil ? 0.65 : 1)
    }
}

private struct AssistanceLocationView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var locationService: LocationService
    @State private var emergencyContacts: [EmergencyContact] = []
    @State private var hasInvalidEmergencyContact = false
    @State private var isSharing = false
    @State private var locationRequestState: AssistanceLocationRequestState = .searching
    @State private var alertMessage: AssistanceAlertMessage?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let location = currentLocation {
                    Map(
                        coordinateRegion: .constant(
                            MKCoordinateRegion(
                                center: location.coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                            )
                        )
                    )
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    ViimCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("assistance.location.coordinates")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(ViimColors.text)
                            Text(coordinatesText(location))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(ViimColors.muted)
                            Button {
                                UIPasteboard.general.string = coordinatesText(location)
                                alertMessage = AssistanceAlertMessage(titleKey: "assistance.location.copied.title", detailKey: "assistance.location.copied.detail")
                            } label: {
                                Label("assistance.location.copy", systemImage: "doc.on.doc.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Button {
                        shareLocation(location)
                    } label: {
                        Label(isSharing ? "assistance.location.sharing" : "assistance.location.share", systemImage: "paperplane.fill")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ViimColors.blue)
                    .disabled(emergencyContacts.isEmpty || isSharing)
                } else {
                    AssistanceDetailView(
                        icon: locationRequestState.icon,
                        titleKey: locationRequestState.titleKey(for: locationService.authorizationState),
                        detailKey: locationRequestState.detailKey(for: locationService.authorizationState),
                        tint: locationRequestState.tint
                    )
                }
            }
            .padding(14)
        }
        .background(ViimColors.background.ignoresSafeArea())
        .navigationTitle("assistance.location.title")
        .task {
            reloadContact()
            locationService.prepareForForegroundUse()
            requestFreshLocation()
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if currentLocation == nil {
                locationRequestState = .timedOut
            }
        }
        .onChange(of: locationService.latestLocation) { _ in
            if currentLocation != nil {
                locationRequestState = .available
            }
        }
        .alert(item: $alertMessage) { message in
            Alert(
                title: Text(message.titleKey),
                message: Text(message.detailKey),
                dismissButton: .default(Text("common.ok"))
            )
        }
    }

    private var currentLocation: CLLocation? {
        guard let location = locationService.latestLocation,
              abs(Date().timeIntervalSince(location.timestamp)) <= 120 else {
            return nil
        }
        return location
    }

    private func reloadContact() {
        let storedContacts = (try? SecureEmergencyContactStore.shared.loadAll()) ?? []
        emergencyContacts = storedContacts.compactMap(BurkinaPhoneNumber.normalizedContact)
        hasInvalidEmergencyContact = !storedContacts.isEmpty && emergencyContacts.isEmpty
    }

    private func requestFreshLocation() {
        locationRequestState = .searching
        locationService.requestCurrentLocation()
    }

    private func shareLocation(_ location: CLLocation) {
        guard !emergencyContacts.isEmpty else {
            alertMessage = AssistanceAlertMessage(titleKey: "assistance.error.title", detailKey: hasInvalidEmergencyContact ? "assistance.contacts.correctRequired" : "assistance.test.missingContact")
            return
        }

        isSharing = true
        let contacts = emergencyContacts
        let driverName = onboardingStore.profile?.firstName
        Task { @MainActor in
            defer { isSharing = false }
            var firstError: Error?
            var sentCount = 0
            for contact in contacts {
                do {
                    try await BackendAPIClient.shared.shareLocation(
                        contact: contact,
                        driverName: driverName,
                        location: location
                    )
                    sentCount += 1
                } catch {
                    if firstError == nil {
                        firstError = error
                    }
                }
            }

            if sentCount == contacts.count {
                alertMessage = AssistanceAlertMessage(titleKey: "assistance.location.shared.title", detailKey: "assistance.location.shared.detail")
            } else if sentCount > 0 {
                alertMessage = AssistanceAlertMessage(
                    titleKey: "assistance.send.partial.title",
                    detailKey: "assistance.send.partial.detail"
                )
            } else if let firstError {
                alertMessage = AssistanceAlertMessage(titleKey: "assistance.error.title", detailKey: AssistanceAPIErrorPresenter.detailKey(for: firstError, fallbackKey: "assistance.location.shared.error"))
            }
        }
    }

    private func coordinatesText(_ location: CLLocation) -> String {
        String(format: "%.6f, %.6f", location.coordinate.latitude, location.coordinate.longitude)
    }
}

private struct EmergencyContactsView: View {
    let onChange: () -> Void
    @State private var contacts: [EmergencyContact] = []
    @State private var name = ""
    @State private var phoneNumber = ""
    @State private var alertMessage: AssistanceAlertMessage?

    var body: some View {
        Form {
            if !contacts.isEmpty {
                Section {
                    ForEach(Array(contacts.enumerated()), id: \.element.phoneNumber) { _, contact in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.name)
                                .font(.body.weight(.semibold))
                            Text(contact.phoneNumber)
                                .font(.caption)
                                .foregroundStyle(ViimColors.muted)
                        }
                    }
                    .onDelete(perform: deleteContacts)
                } header: {
                    Text("assistance.contacts.listHeader \(contacts.count) \(SecureEmergencyContactStore.maximumContacts)")
                } footer: {
                    Text("assistance.contacts.deleteHint")
                }
            }

            if contacts.count < SecureEmergencyContactStore.maximumContacts {
                Section {
                    TextField("assistance.contacts.name.placeholder", text: $name)
                        .textContentType(.name)
                    TextField("assistance.contacts.phone.placeholder", text: $phoneNumber)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)

                    Button("assistance.contacts.add") {
                        addContact()
                    }
                    .disabled(!isValidContact)
                } header: {
                    Text("assistance.contacts.addHeader")
                } footer: {
                    Text("assistance.contacts.footer")
                }
            } else {
                Section {
                    Text("assistance.contacts.maxReached")
                        .font(.footnote)
                        .foregroundStyle(ViimColors.muted)
                }
            }
        }
        .viimKeyboardDismissal()
        .navigationTitle("assistance.contacts.title")
        .task {
            loadContacts()
        }
        .alert(item: $alertMessage) { message in
            Alert(
                title: Text(message.titleKey),
                message: Text(message.detailKey),
                dismissButton: .default(Text("common.ok"))
            )
        }
    }

    private var isValidContact: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            BurkinaPhoneNumber.normalize(phoneNumber) != nil
    }

    private func loadContacts() {
        contacts = (try? SecureEmergencyContactStore.shared.loadAll()) ?? []
    }

    private func addContact() {
        guard let normalizedPhoneNumber = BurkinaPhoneNumber.normalize(phoneNumber) else {
            alertMessage = AssistanceAlertMessage(titleKey: "assistance.error.title", detailKey: "assistance.contacts.invalidPhone")
            return
        }

        var updatedContacts = contacts.filter { $0.phoneNumber != normalizedPhoneNumber }
        updatedContacts.append(
            EmergencyContact(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                phoneNumber: normalizedPhoneNumber
            )
        )

        do {
            try SecureEmergencyContactStore.shared.saveAll(updatedContacts)
            contacts = updatedContacts
            name = ""
            phoneNumber = ""
            onChange()
            alertMessage = AssistanceAlertMessage(titleKey: "assistance.contacts.saved.title", detailKey: "assistance.contacts.saved.detail")
        } catch {
            alertMessage = AssistanceAlertMessage(titleKey: "assistance.error.title", detailKey: "assistance.contacts.error")
        }
    }

    private func deleteContacts(at offsets: IndexSet) {
        var updatedContacts = contacts
        updatedContacts.remove(atOffsets: offsets)

        do {
            try SecureEmergencyContactStore.shared.saveAll(updatedContacts)
            contacts = updatedContacts
            onChange()
        } catch {
            alertMessage = AssistanceAlertMessage(titleKey: "assistance.error.title", detailKey: "assistance.contacts.error")
        }
    }
}

private struct MedicalProfileView: View {
    let onChange: () -> Void
    @State private var profile: MedicalProfile = .empty
    @State private var alertMessage: AssistanceAlertMessage?

    var body: some View {
        Form {
            Section {
                TextField("assistance.medical.bloodType", text: $profile.bloodType)
                TextField("assistance.medical.allergies", text: $profile.allergies)
                TextField("assistance.medical.conditions", text: $profile.conditions)
                TextField("assistance.medical.medications", text: $profile.medications)
                TextField("assistance.medical.cnib", text: $profile.cnib)
            } header: {
                Text("assistance.medical.title")
            } footer: {
                Text("assistance.medical.privacy")
            }

            Section {
                Button("assistance.medical.save") {
                    saveProfile()
                }

                Button("assistance.medical.delete", role: .destructive) {
                    deleteProfile()
                }
            }
        }
        .viimKeyboardDismissal()
        .navigationTitle("assistance.medical.title")
        .task {
            profile = (try? SecureMedicalProfileStore.shared.load()) ?? .empty
        }
        .alert(item: $alertMessage) { message in
            Alert(
                title: Text(message.titleKey),
                message: Text(message.detailKey),
                dismissButton: .default(Text("common.ok"))
            )
        }
    }

    private func saveProfile() {
        do {
            try SecureMedicalProfileStore.shared.save(profile)
            onChange()
            alertMessage = AssistanceAlertMessage(titleKey: "assistance.medical.saved.title", detailKey: "assistance.medical.saved.detail")
        } catch {
            alertMessage = AssistanceAlertMessage(titleKey: "assistance.error.title", detailKey: "assistance.medical.error")
        }
    }

    private func deleteProfile() {
        do {
            try SecureMedicalProfileStore.shared.delete()
            profile = .empty
            onChange()
            alertMessage = AssistanceAlertMessage(titleKey: "assistance.medical.deleted.title", detailKey: "assistance.medical.deleted.detail")
        } catch {
            alertMessage = AssistanceAlertMessage(titleKey: "assistance.error.title", detailKey: "assistance.medical.error")
        }
    }
}

private struct AssistanceDetailView: View {
    let icon: String
    let titleKey: LocalizedStringKey
    let detailKey: LocalizedStringKey
    let tint: Color

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 72, height: 72)
                .background(tint.opacity(0.12))
                .clipShape(Circle())
            Text(titleKey)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(ViimColors.text)
                .multilineTextAlignment(.center)
            Text(detailKey)
                .font(.body)
                .foregroundStyle(ViimColors.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(22)
        .background(ViimColors.background.ignoresSafeArea())
        .navigationTitle(titleKey)
    }
}

private struct AssistanceAlertMessage: Identifiable {
    let id = UUID()
    let titleKey: LocalizedStringKey
    let detailKey: LocalizedStringKey
}

private enum AssistanceLocationRequestState {
    case searching
    case available
    case timedOut

    var icon: String {
        switch self {
        case .searching, .available:
            return "location.viewfinder"
        case .timedOut:
            return "location.slash.fill"
        }
    }

    var tint: Color {
        switch self {
        case .searching, .available:
            return ViimColors.blue
        case .timedOut:
            return ViimColors.warning
        }
    }

    func titleKey(for authorizationState: LocationAuthorizationState) -> LocalizedStringKey {
        if authorizationState == .denied || authorizationState == .restricted {
            return "assistance.location.permission.title"
        }

        switch self {
        case .searching, .available:
            return "assistance.location.searching.title"
        case .timedOut:
            return "assistance.location.unavailable.title"
        }
    }

    func detailKey(for authorizationState: LocationAuthorizationState) -> LocalizedStringKey {
        if authorizationState == .denied || authorizationState == .restricted {
            return "assistance.location.permission.detail"
        }

        switch self {
        case .searching, .available:
            return "assistance.location.searching.detail"
        case .timedOut:
            return "assistance.location.unavailable.detail"
        }
    }
}

private enum AssistanceAPIErrorPresenter {
    static func detailKey(for error: Error, fallbackKey: LocalizedStringKey) -> LocalizedStringKey {
        guard let apiError = error as? BackendAPIError else {
            return fallbackKey
        }

        switch apiError {
        case let .apiStatus(statusCode, code) where statusCode == 422 && code == "invalid_contact":
            return "assistance.error.invalidContact"
        case let .apiStatus(statusCode, code) where statusCode == 503 && code == "newagent_unavailable":
            return "assistance.error.whatsappUnavailable"
        case .network(.notConnectedToInternet), .network(.networkConnectionLost):
            return "assistance.error.offline"
        case .network(.timedOut):
            return "assistance.error.timeout"
        default:
            return fallbackKey
        }
    }
}
