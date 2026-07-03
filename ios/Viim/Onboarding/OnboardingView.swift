import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @State private var draft = OnboardingDraft()
    @State private var step: OnboardingStep = .identity
    @State private var errorKey: LocalizedStringKey?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OnboardingProgressView(currentStep: step)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        stepContent

                        if let errorKey {
                            Text(errorKey)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(ViimColors.danger)
                        }
                    }
                    .padding(20)
                }

                actionBar
                    .padding(20)
                    .background(.regularMaterial)
            }
            .background(ViimColors.background)
            .navigationTitle(step.titleKey)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .identity:
            identityStep
        case .vehicle:
            vehicleStep
        case .safety:
            safetyStep
        }
    }

    private var identityStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnboardingHeader(
                systemImage: "person.crop.circle.badge.checkmark",
                titleKey: "onboarding.identity.header",
                detailKey: "onboarding.identity.detail",
                tint: ViimColors.navy
            )

            VStack(spacing: 12) {
                TextField("onboarding.identity.firstName.placeholder", text: $draft.firstName)
                    .textContentType(.givenName)
                    .submitLabel(.next)
                    .textInputAutocapitalization(.words)
                    .formFieldStyle()

                TextField("onboarding.identity.phone.placeholder", text: $draft.phoneNumber)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .formFieldStyle()
            }

            Text("onboarding.identity.consent")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var vehicleStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnboardingHeader(
                systemImage: draft.vehicleType.symbolName,
                titleKey: "onboarding.vehicle.header",
                detailKey: "onboarding.vehicle.detail",
                tint: draft.vehicleType.tint
            )

            HStack(spacing: 10) {
                ForEach(VehicleType.allCases) { type in
                    VehicleTypeButton(
                        type: type,
                        isSelected: draft.vehicleType == type
                    ) {
                        draft.vehicleType = type
                    }
                }
            }

            VehiclePreviewCard(draft: draft)

            VStack(spacing: 12) {
                TextField("onboarding.vehicle.brand.placeholder", text: $draft.vehicleBrand)
                    .textContentType(.organizationName)
                    .textInputAutocapitalization(.words)
                    .formFieldStyle()

                TextField("onboarding.vehicle.model.placeholder", text: $draft.vehicleModel)
                    .textInputAutocapitalization(.words)
                    .formFieldStyle()

                TextField("onboarding.vehicle.year.placeholder", text: $draft.vehicleYear)
                    .keyboardType(.numberPad)
                    .formFieldStyle()
            }
        }
    }

    private var safetyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnboardingHeader(
                systemImage: "cross.case.fill",
                titleKey: "onboarding.safety.header",
                detailKey: "onboarding.safety.detail",
                tint: ViimColors.red
            )

            ViimCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label {
                        Text("onboarding.safety.contact.title")
                            .font(.headline)
                    } icon: {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(ViimColors.red)
                    }

                    TextField("onboarding.safety.contactName.placeholder", text: $draft.emergencyContactName)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .formFieldStyle()

                    TextField("onboarding.safety.contactPhone.placeholder", text: $draft.emergencyContactPhone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .formFieldStyle()

                    Text("onboarding.safety.keychain")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            ViimCard {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("onboarding.safety.medical.title")
                            .font(.headline)
                        Text("onboarding.safety.medical.detail")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(ViimColors.navy)
                }
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            if step != .identity {
                Button {
                    errorKey = nil
                    step = step.previous
                } label: {
                    Label("onboarding.action.back", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
            }

            Spacer(minLength: 0)

            Button {
                advance()
            } label: {
                if step == .safety {
                    Label("onboarding.action.finish", systemImage: "checkmark")
                } else {
                    Label("onboarding.action.next", systemImage: "chevron.right")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(step.tint)
        }
    }

    private func advance() {
        errorKey = nil

        guard step.isValid(draft: draft) else {
            errorKey = step.errorKey
            return
        }

        guard step == .safety else {
            step = step.next
            return
        }

        let profile = UserProfile(
            firstName: draft.firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            phoneNumber: draft.phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            vehicleType: draft.vehicleType,
            vehicleBrand: draft.vehicleBrand.trimmingCharacters(in: .whitespacesAndNewlines),
            vehicleModel: draft.vehicleModel.trimmingCharacters(in: .whitespacesAndNewlines),
            vehicleYear: draft.vehicleYear.trimmingCharacters(in: .whitespacesAndNewlines),
            calibrationTripCount: 0,
            synced: false
        )

        let emergencyContact = draft.emergencyContact

        do {
            try onboardingStore.complete(profile: profile, emergencyContact: emergencyContact)
        } catch {
            errorKey = "onboarding.error.save"
        }
    }
}

private struct OnboardingDraft {
    var firstName = ""
    var phoneNumber = "+226 "
    var vehicleType: VehicleType = .moto
    var vehicleBrand = ""
    var vehicleModel = ""
    var vehicleYear = ""
    var emergencyContactName = ""
    var emergencyContactPhone = ""

    var emergencyContact: EmergencyContact? {
        let name = emergencyContactName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = emergencyContactPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty && !phone.isEmpty else {
            return nil
        }
        return EmergencyContact(name: name, phoneNumber: phone)
    }
}

private enum OnboardingStep: Int, CaseIterable {
    case identity
    case vehicle
    case safety

    var titleKey: LocalizedStringKey {
        switch self {
        case .identity: "onboarding.identity.title"
        case .vehicle: "onboarding.vehicle.title"
        case .safety: "onboarding.safety.title"
        }
    }

    var errorKey: LocalizedStringKey {
        switch self {
        case .identity: "onboarding.identity.error"
        case .vehicle: "onboarding.vehicle.error"
        case .safety: "onboarding.safety.error"
        }
    }

    var tint: Color {
        switch self {
        case .identity: ViimColors.navy
        case .vehicle: ViimColors.blue
        case .safety: ViimColors.red
        }
    }

    var next: OnboardingStep {
        OnboardingStep(rawValue: rawValue + 1) ?? .safety
    }

    var previous: OnboardingStep {
        OnboardingStep(rawValue: rawValue - 1) ?? .identity
    }

    func isValid(draft: OnboardingDraft) -> Bool {
        switch self {
        case .identity:
            return !draft.firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                draft.phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("+226") &&
                draft.phoneNumber.filter(\.isNumber).count >= 11
        case .vehicle:
            return true
        case .safety:
            let hasName = !draft.emergencyContactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasPhone = !draft.emergencyContactPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return hasName == hasPhone
        }
    }
}

private struct OnboardingProgressView: View {
    let currentStep: OnboardingStep

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                Capsule()
                    .fill(step.rawValue <= currentStep.rawValue ? currentStep.tint : Color(.systemGray5))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}

private struct OnboardingHeader: View {
    let systemImage: String
    let titleKey: LocalizedStringKey
    let detailKey: LocalizedStringKey
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 52, height: 52)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(titleKey)
                .font(.title2.weight(.bold))
                .foregroundStyle(ViimColors.text)

            Text(detailKey)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct VehicleTypeButton: View {
    let type: VehicleType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: type.symbolName)
                    .font(.title3.weight(.semibold))
                Text(type.titleKey)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? Color.white : type.tint)
            .frame(maxWidth: .infinity)
            .frame(height: 82)
            .background(isSelected ? type.tint : type.tint.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct VehiclePreviewCard: View {
    let draft: OnboardingDraft

    var body: some View {
        ViimCard {
            HStack(spacing: 14) {
                Image(systemName: draft.vehicleType.symbolName)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(draft.vehicleType.tint)
                    .frame(width: 72, height: 72)
                    .background(draft.vehicleType.tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("onboarding.vehicle.preview.title")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(vehicleName)
                        .font(.headline)
                        .foregroundStyle(ViimColors.text)
                    Text(draft.vehicleType.statusKey)
                        .font(.footnote)
                        .foregroundStyle(ViimColors.success)
                }
            }
        }
    }

    private var vehicleName: String {
        let parts = [draft.vehicleBrand, draft.vehicleModel, draft.vehicleYear]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? draft.vehicleType.fallbackDisplayName : parts.joined(separator: " ")
    }
}

private extension View {
    func formFieldStyle() -> some View {
        self
            .textFieldStyle(.plain)
            .padding(14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
