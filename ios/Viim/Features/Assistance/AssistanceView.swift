import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct AssistanceView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var locationService: LocationService
    @State private var emergencyContact: EmergencyContact?
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
                                ViimChip(titleKey: emergencyContact == nil ? "status.disabled" : "status.enabled", style: emergencyContact == nil ? .neutral : .success)
                            }
                            Text("assistance.realtime.detail")
                                .font(.caption)
                                .foregroundStyle(ViimColors.muted)
                                .fixedSize(horizontal: false, vertical: true)

                            if emergencyContact == nil {
                                NavigationLink {
                                    EmergencyContactsView(onChange: reloadSecureData)
                                } label: {
                                    Label("assistance.test.configure", systemImage: "person.badge.plus.fill")
                                        .font(.caption.weight(.bold))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 40)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(ViimColors.red)
                            } else {
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
                                .disabled(isSendingTest)
                            }
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
                                AssistanceListRow(icon: "person.2.fill", titleKey: "assistance.contacts.title", detailKey: emergencyContact == nil ? "assistance.contacts.status" : "assistance.contacts.configured", tint: ViimColors.navy)
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                MedicalProfileView(onChange: reloadSecureData)
                            } label: {
                                AssistanceListRow(icon: "cross.case.fill", titleKey: "assistance.medical.title", detailKey: medicalProfile?.isComplete == true ? "assistance.medical.complete" : "assistance.medical.status", tint: ViimColors.green)
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
                        EmergencyButton(titleKey: "assistance.firefighters.title", detailKey: "assistance.firefighters.detail", phoneNumber: "18", tint: ViimColors.red)
                        EmergencyButton(titleKey: "assistance.police.title", detailKey: "assistance.police.detail", phoneNumber: "17", tint: ViimColors.navy)
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
            .onAppear {
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
        emergencyContact = try? SecureEmergencyContactStore.shared.loadNormalizedForBurkina()
        medicalProfile = try? SecureMedicalProfileStore.shared.load()
    }

    private func sendTestWhatsApp() {
        guard let emergencyContact else {
            alertMessage = AssistanceAlertMessage(titleKey: "assistance.error.title", detailKey: "assistance.test.missingContact")
            return
        }
        guard let normalizedContact = emergencyContact.normalizedForBurkina else {
            alertMessage = AssistanceAlertMessage(titleKey: "assistance.error.title", detailKey: "assistance.test.invalidContact")
            return
        }

        isSendingTest = true
        Task { @MainActor in
            defer { isSendingTest = false }
            do {
                try await BackendAPIClient.shared.sendAlertTest(
                    contact: normalizedContact,
                    driverName: onboardingStore.profile?.firstName
                )
                alertMessage = AssistanceAlertMessage(titleKey: "assistance.test.success.title", detailKey: "assistance.test.success.detail")
            } catch {
                alertMessage = AssistanceAlertMessage(titleKey: "assistance.error.title", detailKey: "assistance.test.error")
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
    let detailKey: LocalizedStringKey
    let phoneNumber: String
    let tint: Color

    var body: some View {
        Button {
            if let url = URL(string: "tel://\(phoneNumber)") {
                openURL(url)
            }
        } label: {
            VStack(spacing: 4) {
                Text(titleKey)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(detailKey)
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
    }
}

private struct AssistanceLocationView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var locationService: LocationService
    @State private var emergencyContact: EmergencyContact?
    @State private var isSharing = false
    @State private var alertMessage: AssistanceAlertMessage?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let location = locationService.latestLocation {
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
                    .disabled(isSharing)
                } else {
                    ViimCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(locationWaitingTitleKey, systemImage: locationService.isRequestingCurrentLocation ? "location.fill.viewfinder" : "location.slash.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(ViimColors.text)
                            Text(locationWaitingDetailKey)
                                .font(.caption)
                                .foregroundStyle(ViimColors.muted)
                                .fixedSize(horizontal: false, vertical: true)

                            Button {
                                locationService.requestCurrentLocation()
                            } label: {
                                Label(locationService.isRequestingCurrentLocation ? "assistance.location.refreshing" : "assistance.location.refresh", systemImage: "location.fill")
                                    .font(.caption.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 40)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ViimColors.blue)
                            .disabled(locationService.isRequestingCurrentLocation || !locationService.authorizationState.canTrackLocation)
                        }
                    }
                }
            }
            .padding(14)
        }
        .background(ViimColors.background.ignoresSafeArea())
        .navigationTitle("assistance.location.title")
        .task {
            emergencyContact = try? SecureEmergencyContactStore.shared.loadNormalizedForBurkina()
            locationService.prepareForForegroundUse()
            locationService.requestCurrentLocation()
        }
        .onAppear {
            emergencyContact = try? SecureEmergencyContactStore.shared.loadNormalizedForBurkina()
        }
        .alert(item: $alertMessage) { message in
            Alert(
                title: Text(message.titleKey),
                message: Text(message.detailKey),
                dismissButton: .default(Text("common.ok"))
            )
        }
    }

    private var locationWaitingTitleKey: LocalizedStringKey {
        switch locationService.authorizationState {
        case .denied, .restricted:
            return "assistance.location.denied.title"
        case .notDetermined:
            return "assistance.location.permission.title"
        case .authorizedWhenInUse, .authorizedAlways:
            return locationService.isRequestingCurrentLocation ? "assistance.location.loading.title" : "assistance.location.waiting.title"
        }
    }

    private var locationWaitingDetailKey: LocalizedStringKey {
        switch locationService.authorizationState {
        case .denied, .restricted:
            return "assistance.location.denied.detail"
        case .notDetermined:
            return "assistance.location.permission.detail"
        case .authorizedWhenInUse, .authorizedAlways:
            return locationService.isRequestingCurrentLocation ? "assistance.location.loading.detail" : "assistance.location.waiting.detail"
        }
    }

    private func shareLocation(_ location: CLLocation) {
        guard let emergencyContact else {
            alertMessage = AssistanceAlertMessage(titleKey: "assistance.error.title", detailKey: "assistance.test.missingContact")
            return
        }
        guard let normalizedContact = emergencyContact.normalizedForBurkina else {
            alertMessage = AssistanceAlertMessage(titleKey: "assistance.error.title", detailKey: "assistance.test.invalidContact")
            return
        }

        isSharing = true
        Task { @MainActor in
            defer { isSharing = false }
            do {
                try await BackendAPIClient.shared.shareLocation(
                    contact: normalizedContact,
                    driverName: onboardingStore.profile?.firstName,
                    location: location
                )
                alertMessage = AssistanceAlertMessage(titleKey: "assistance.location.shared.title", detailKey: "assistance.location.shared.detail")
            } catch {
                alertMessage = AssistanceAlertMessage(titleKey: "assistance.error.title", detailKey: "assistance.location.shared.error")
            }
        }
    }

    private func coordinatesText(_ location: CLLocation) -> String {
        String(format: "%.6f, %.6f", location.coordinate.latitude, location.coordinate.longitude)
    }
}

private struct EmergencyContactsView: View {
    let onChange: () -> Void
    @State private var name = ""
    @State private var phoneNumber = ""
    @State private var alertMessage: AssistanceAlertMessage?

    var body: some View {
        Form {
            Section {
                TextField("assistance.contacts.name.placeholder", text: $name)
                    .textContentType(.name)
                TextField("assistance.contacts.phone.placeholder", text: $phoneNumber)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            } header: {
                Text("assistance.contacts.title")
            } footer: {
                Text("assistance.contacts.footer")
            }

            Section {
                Button("assistance.contacts.save") {
                    saveContact()
                }
                .disabled(!isValidContact)

                Button("assistance.contacts.delete", role: .destructive) {
                    deleteContact()
                }
            }
        }
        .navigationTitle("assistance.contacts.title")
        .task {
            loadContact()
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
        EmergencyContact(name: name, phoneNumber: phoneNumber).normalizedForBurkina != nil
    }

    private func loadContact() {
        guard let contact = try? SecureEmergencyContactStore.shared.load() else {
            return
        }
        let displayContact = contact.normalizedForBurkina ?? contact
        name = displayContact.name
        phoneNumber = displayContact.phoneNumber
    }

    private func saveContact() {
        guard let normalizedContact = EmergencyContact(name: name, phoneNumber: phoneNumber).normalizedForBurkina else {
            alertMessage = AssistanceAlertMessage(titleKey: "assistance.error.title", detailKey: "assistance.test.invalidContact")
            return
        }

        do {
            try SecureEmergencyContactStore.shared.save(normalizedContact)
            name = normalizedContact.name
            phoneNumber = normalizedContact.phoneNumber
            onChange()
            alertMessage = AssistanceAlertMessage(titleKey: "assistance.contacts.saved.title", detailKey: "assistance.contacts.saved.detail")
        } catch {
            alertMessage = AssistanceAlertMessage(titleKey: "assistance.error.title", detailKey: "assistance.contacts.error")
        }
    }

    private func deleteContact() {
        do {
            try SecureEmergencyContactStore.shared.delete()
            name = ""
            phoneNumber = ""
            onChange()
            alertMessage = AssistanceAlertMessage(titleKey: "assistance.contacts.deleted.title", detailKey: "assistance.contacts.deleted.detail")
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
