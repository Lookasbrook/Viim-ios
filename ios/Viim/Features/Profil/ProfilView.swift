import SwiftUI

struct ProfilView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var tripManager: TripManager
    @State private var selectedCurrency: SupportedCurrency = .xof
    @State private var fuelPriceText = ""
    @State private var feedbackKey: LocalizedStringKey?
    @State private var feedbackIsError = false
    @State private var odometerText = ""
    @State private var odometerFeedbackKey: LocalizedStringKey?
    @State private var odometerFeedbackIsError = false

    var body: some View {
        Form {
            Section("profile.section.account") {
                if let profile = onboardingStore.profile {
                    LabeledContent("profile.name", value: profile.firstName)
                    LabeledContent("profile.vehicle", value: profile.vehicleDisplayName)
                } else {
                    Text("profile.placeholder")
                }
            }

            Section {
                if let currentOdometerKm = tripManager.currentOdometerKm(profile: onboardingStore.profile) {
                    LabeledContent("profile.odometer.current", value: Self.odometerValueText(currentOdometerKm))
                }

                HStack {
                    TextField("profile.odometer.placeholder", text: $odometerText)
                        .keyboardType(.numberPad)
                    Text(verbatim: "km")
                        .foregroundStyle(ViimColors.muted)
                }

                Button("profile.odometer.save", action: saveOdometer)
                    .frame(maxWidth: .infinity, alignment: .center)
            } header: {
                Text("profile.section.odometer")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("profile.odometer.help")
                    if let odometerFeedbackKey {
                        Text(odometerFeedbackKey)
                            .foregroundStyle(odometerFeedbackIsError ? Color.red : ViimColors.success)
                    }
                }
            }

            Section {
                Picker("profile.currency", selection: $selectedCurrency) {
                    ForEach(SupportedCurrency.allCases) { currency in
                        Text(currency.displayName).tag(currency)
                    }
                }

                HStack {
                    TextField("profile.fuelPrice.placeholder", text: $fuelPriceText)
                        .keyboardType(.decimalPad)
                    Text(selectedCurrency.rawValue)
                        .foregroundStyle(ViimColors.muted)
                }

                Button("profile.fuel.save", action: saveFuelSettings)
                    .frame(maxWidth: .infinity, alignment: .center)
            } header: {
                Text("profile.section.fuel")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("profile.fuel.help")
                    if let feedbackKey {
                        Text(feedbackKey)
                            .foregroundStyle(feedbackIsError ? Color.red : ViimColors.success)
                    }
                }
            }
        }
        .navigationTitle("profile.title")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadFuelSettings)
        .onChange(of: selectedCurrency) { newCurrency in
            guard newCurrency != onboardingStore.fuelSettings.currency else {
                return
            }
            fuelPriceText = Self.priceText(newCurrency.defaultFuelPricePerLiter)
            feedbackKey = nil
        }
    }

    private func loadFuelSettings() {
        let settings = onboardingStore.fuelSettings
        selectedCurrency = settings.currency
        fuelPriceText = Self.priceText(settings.pricePerLiter)
    }

    private func saveFuelSettings() {
        let normalizedPrice = fuelPriceText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        guard let price = Double(normalizedPrice), price.isFinite, price > 0 else {
            feedbackIsError = true
            feedbackKey = "profile.fuel.invalid"
            return
        }

        do {
            try onboardingStore.updateFuelSettings(
                FuelSettings(currency: selectedCurrency, pricePerLiter: price)
            )
            feedbackIsError = false
            feedbackKey = "profile.fuel.saved"
        } catch {
            feedbackIsError = true
            feedbackKey = "profile.fuel.invalid"
        }
    }

    private func saveOdometer() {
        let cleaned = odometerText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")

        guard let value = Double(cleaned), value.isFinite, value >= 0, value < 3_000_000 else {
            odometerFeedbackIsError = true
            odometerFeedbackKey = "profile.odometer.invalid"
            return
        }

        do {
            try onboardingStore.updateOdometer(baselineKm: value)
            odometerText = ""
            odometerFeedbackIsError = false
            odometerFeedbackKey = "profile.odometer.saved"
        } catch {
            odometerFeedbackIsError = true
            odometerFeedbackKey = "profile.odometer.invalid"
        }
    }

    private static func odometerValueText(_ value: Double) -> String {
        String.localizedStringWithFormat(
            String(localized: "prevention.maintenance.odometerFormat"),
            value
        )
    }

    private static func priceText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(.current))
    }
}
