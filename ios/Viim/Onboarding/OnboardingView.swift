import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @State private var draft = OnboardingDraft()
    @State private var step: OnboardingStep = .identity
    @State private var errorKey: LocalizedStringKey?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ViimBrandMark()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                OnboardingProgressView(currentStep: step)
                    .frame(maxWidth: .infinity)

                Text(step.titleKey)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(ViimColors.text)
                    .padding(.horizontal, 2)

                Text(step.detailKey)
                    .font(.subheadline)
                    .foregroundStyle(ViimColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)

                stepContent

                if let errorKey {
                    Text(errorKey)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ViimColors.danger)
                }

                actionBar
                    .padding(.top, 2)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 18)
        }
        .background(ViimColors.background.ignoresSafeArea())
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
        VStack(alignment: .leading, spacing: 10) {
            LabeledTextField(
                labelKey: "onboarding.identity.firstName.label",
                placeholderKey: "onboarding.identity.firstName.placeholder",
                text: $draft.firstName
            )
            .textContentType(.givenName)
            .submitLabel(.next)
            .textInputAutocapitalization(.words)

            LabeledTextField(
                labelKey: "onboarding.identity.phone.label",
                placeholderKey: "onboarding.identity.phone.placeholder",
                text: $draft.phoneNumber
            )
            .textContentType(.telephoneNumber)
            .keyboardType(.phonePad)

            Text("onboarding.identity.consent")
                .font(.footnote)
                .foregroundStyle(ViimColors.muted)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }

    private var vehicleStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("onboarding.vehicle.type.label")
                    .fieldLabelStyle()

                HStack(spacing: 8) {
                    ForEach(VehicleType.allCases) { type in
                        VehicleTypeButton(
                            type: type,
                            isSelected: draft.vehicleType == type
                        ) {
                            draft.vehicleType = type
                        }
                    }
                }
            }

            LabeledTextField(
                labelKey: "onboarding.vehicle.brand.label",
                placeholderKey: "onboarding.vehicle.brand.placeholder",
                text: $draft.vehicleBrand
            )
            .textContentType(.organizationName)
            .textInputAutocapitalization(.words)

            LabeledTextField(
                labelKey: "onboarding.vehicle.model.label",
                placeholderKey: "onboarding.vehicle.model.placeholder",
                text: $draft.vehicleModel
            )
            .textInputAutocapitalization(.words)

            LabeledTextField(
                labelKey: "onboarding.vehicle.year.label",
                placeholderKey: "onboarding.vehicle.year.placeholder",
                text: $draft.vehicleYear
            )
            .keyboardType(.numberPad)

            VehiclePreviewCard(draft: draft)
        }
    }

    private var safetyStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViimCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label {
                        Text("onboarding.safety.contact.title")
                            .font(.headline)
                    } icon: {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(ViimColors.red)
                    }

                    LabeledTextField(
                        labelKey: "onboarding.safety.contactName.label",
                        placeholderKey: "onboarding.safety.contactName.placeholder",
                        text: $draft.emergencyContactName
                    )
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)

                    LabeledTextField(
                        labelKey: "onboarding.safety.contactPhone.label",
                        placeholderKey: "onboarding.safety.contactPhone.placeholder",
                        text: $draft.emergencyContactPhone
                    )
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)

                    Text("onboarding.safety.keychain")
                        .font(.footnote)
                        .foregroundStyle(ViimColors.muted)
                }
            }

            ViimCard {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("onboarding.safety.medical.title")
                            .font(.headline)
                        Text("onboarding.safety.medical.detail")
                            .font(.footnote)
                            .foregroundStyle(ViimColors.muted)
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
                .tint(ViimColors.blue)
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
            .controlSize(.large)
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
            phoneNumber: BurkinaPhoneNumber.normalized(draft.phoneNumber) ?? draft.phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines),
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
        return EmergencyContact(name: name, phoneNumber: phone).normalizedForBurkina
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

    var detailKey: LocalizedStringKey {
        switch self {
        case .identity: "onboarding.identity.detail"
        case .vehicle: "onboarding.vehicle.detail"
        case .safety: "onboarding.safety.detail"
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
                BurkinaPhoneNumber.normalized(draft.phoneNumber) != nil
        case .vehicle:
            return true
        case .safety:
            let hasName = !draft.emergencyContactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasPhone = !draft.emergencyContactPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard hasName == hasPhone else {
                return false
            }
            guard hasName, hasPhone else {
                return true
            }
            return draft.emergencyContact != nil
        }
    }
}

private struct OnboardingProgressView: View {
    let currentStep: OnboardingStep

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                Capsule()
                    .fill(step.rawValue <= currentStep.rawValue ? ViimColors.blue : Color(hex: 0xD7E2EC))
                    .frame(width: 26, height: 4)
            }
        }
        .padding(.vertical, 4)
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
            .foregroundStyle(type.tint)
            .frame(maxWidth: .infinity)
            .frame(height: 74)
            .background(isSelected ? Color(hex: 0xEDF5FC) : Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(isSelected ? ViimColors.blue : Color(hex: 0xD7E2EC), lineWidth: isSelected ? 2.5 : 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct VehiclePreviewCard: View {
    let draft: OnboardingDraft

    var body: some View {
        ViimCard {
            VStack(spacing: 7) {
                VehicleIllustration(type: draft.vehicleType)
                    .frame(maxWidth: .infinity)

                Text(vehicleName.uppercased())
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(ViimColors.text)
                    .multilineTextAlignment(.center)

                Text("onboarding.vehicle.preview.detail")
                    .font(.caption)
                    .foregroundStyle(ViimColors.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var vehicleName: String {
        let parts = [draft.vehicleBrand, draft.vehicleModel, draft.vehicleYear]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? draft.vehicleType.fallbackDisplayName : parts.joined(separator: " ")
    }
}

private struct LabeledTextField: View {
    let labelKey: LocalizedStringKey
    let placeholderKey: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(labelKey)
                .fieldLabelStyle()
            TextField(placeholderKey, text: $text)
                .formFieldStyle()
        }
    }
}

private extension View {
    func formFieldStyle() -> some View {
        self
            .textFieldStyle(.plain)
            .font(.body)
            .foregroundStyle(ViimColors.text)
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(hex: 0xD7E2EC), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    func fieldLabelStyle() -> some View {
        self
            .font(.caption2.weight(.bold))
            .foregroundStyle(ViimColors.muted)
            .textCase(.uppercase)
    }
}
