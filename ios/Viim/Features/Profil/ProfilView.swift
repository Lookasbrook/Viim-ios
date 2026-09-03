import CoreLocation
import SwiftUI
import UIKit

struct ProfilView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var tripManager: TripManager
    @EnvironmentObject private var locationService: LocationService
    @State private var selectedCurrency: SupportedCurrency = .xof
    @State private var fuelPriceText = ""
    @State private var selectedFuelType: VehicleFuelType?
    @State private var feedbackKey: LocalizedStringKey?
    @State private var feedbackIsError = false
    @State private var isLoadingOfficialPrice = false
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
                Picker("profile.fuelType", selection: $selectedFuelType) {
                    Text("profile.fuelType.placeholder")
                        .tag(nil as VehicleFuelType?)
                    ForEach(VehicleFuelType.allCases) { fuelType in
                        Text(fuelType.displayName).tag(Optional(fuelType))
                    }
                }
                .disabled(isLoadingOfficialPrice)

                Picker("profile.currency", selection: $selectedCurrency) {
                    ForEach(SupportedCurrency.allCases) { currency in
                        Text(currency.displayName).tag(currency)
                    }
                }
                .disabled(isLoadingOfficialPrice)

                if selectedFuelType?.supportsLiquidFuelEstimate != false {
                    HStack {
                        TextField("profile.fuelPrice.placeholder", text: $fuelPriceText)
                            .keyboardType(.decimalPad)
                        Text(selectedCurrency.rawValue)
                            .foregroundStyle(ViimColors.muted)
                    }

                    Button {
                        Task { await loadOfficialLocalPrice() }
                    } label: {
                        if isLoadingOfficialPrice {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("profile.fuel.official.lookup", systemImage: "location.magnifyingglass")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isLoadingOfficialPrice || selectedFuelType?.supportsLiquidFuelEstimate != true)
                }

                Button("profile.fuel.save", action: saveFuelSettings)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(isLoadingOfficialPrice)
            } header: {
                Text("profile.section.fuel")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("profile.fuel.help")
                    if onboardingStore.fuelSettings.source == .officialPublicData,
                       onboardingStore.fuelSettings.canSnapshotCost(at: Date()) {
                        Text(officialPriceDetail)
                            .foregroundStyle(ViimColors.success)
                    } else if onboardingStore.fuelSettings.source == .officialPublicData {
                        Text("profile.fuel.official.stale")
                            .foregroundStyle(ViimColors.warning)
                    } else if onboardingStore.fuelSettings.source != .userProvided {
                        Text("profile.fuel.unverified")
                            .foregroundStyle(ViimColors.warning)
                    } else if !onboardingStore.fuelSettings.canSnapshotCost(at: Date()) {
                        Text("profile.fuel.stale")
                            .foregroundStyle(ViimColors.warning)
                    }
                    if let feedbackKey {
                        Text(feedbackKey)
                            .foregroundStyle(feedbackIsError ? Color.red : ViimColors.success)
                    }
                }
            }
        }
        .viimKeyboardDismissal()
        .navigationTitle("profile.title")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadFuelSettings)
        .onChange(of: selectedCurrency) { newCurrency in
            guard newCurrency != onboardingStore.fuelSettings.currency else {
                return
            }
            fuelPriceText = ""
            feedbackKey = nil
        }
        .onChange(of: selectedFuelType) { newFuelType in
            guard newFuelType != onboardingStore.fuelSettings.fuelType else {
                return
            }
            fuelPriceText = ""
            feedbackKey = nil
        }
    }

    private func loadFuelSettings() {
        let settings = onboardingStore.fuelSettings
        selectedFuelType = onboardingStore.profile?.fuelType ?? settings.fuelType
        selectedCurrency = settings.currency
        fuelPriceText = settings.canSnapshotCost && settings.fuelType == selectedFuelType
            ? Self.priceText(settings.pricePerLiter)
            : ""
    }

    private func saveFuelSettings() {
        dismissKeyboard()
        guard let selectedFuelType else {
            feedbackIsError = true
            feedbackKey = "profile.fuelType.required"
            return
        }

        if selectedFuelType == .electric {
            do {
                try onboardingStore.updateVehicleFuelType(selectedFuelType)
                feedbackIsError = false
                feedbackKey = "profile.fuel.saved"
            } catch {
                feedbackIsError = true
                feedbackKey = "profile.fuel.invalid"
            }
            return
        }

        let normalizedPrice = fuelPriceText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        guard let price = Double(normalizedPrice), price.isFinite, price > 0 else {
            feedbackIsError = true
            feedbackKey = "profile.fuel.invalid"
            return
        }

        let currentSettings = onboardingStore.fuelSettings
        if currentSettings.source == .officialPublicData,
           currentSettings.fuelType == selectedFuelType,
           currentSettings.currency == selectedCurrency,
           abs(currentSettings.pricePerLiter - price) < 0.000_001 {
            feedbackIsError = false
            feedbackKey = "profile.fuel.saved"
            return
        }

        do {
            try onboardingStore.updateVehicleFuelType(selectedFuelType)
            try onboardingStore.updateFuelSettings(
                FuelSettings(
                    currency: selectedCurrency,
                    pricePerLiter: price,
                    source: .userProvided,
                    capturedAt: Date(),
                    fuelType: selectedFuelType
                )
            )
            feedbackIsError = false
            feedbackKey = "profile.fuel.saved"
        } catch {
            feedbackIsError = true
            feedbackKey = "profile.fuel.invalid"
        }
    }

    @MainActor
    private func loadOfficialLocalPrice() async {
        guard let selectedFuelType, selectedFuelType.supportsLiquidFuelEstimate else {
            feedbackIsError = true
            feedbackKey = "profile.fuelType.required"
            return
        }

        isLoadingOfficialPrice = true
        feedbackKey = nil
        defer { isLoadingOfficialPrice = false }

        let requestedAt = Date()
        locationService.requestCurrentLocation()
        var location: CLLocation?
        for _ in 0..<20 {
            if let candidate = locationService.latestLocation,
               candidate.horizontalAccuracy > 0,
               candidate.horizontalAccuracy <= 1_000,
               candidate.timestamp >= requestedAt.addingTimeInterval(-60) {
                location = candidate
                break
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        guard let location else {
            feedbackIsError = true
            feedbackKey = "profile.fuel.official.locationUnavailable"
            return
        }

        do {
            // Le backend ne recoit jamais les coordonnees : seulement cette
            // localite grossiere retournee par le service Apple.
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(
                location,
                preferredLocale: Locale(identifier: "fr_CA")
            )
            guard let placemark = placemarks.first,
                  let countryCode = placemark.isoCountryCode,
                  let regionCode = placemark.administrativeArea,
                  let locality = placemark.locality else {
                throw BackendAPIError.invalidResponse
            }

            let quote = try await BackendAPIClient.shared.fetchOfficialFuelPrice(
                countryCode: countryCode,
                regionCode: regionCode,
                locality: locality,
                fuelType: selectedFuelType
            )
            guard self.selectedFuelType == selectedFuelType,
                  quote.fuelType == selectedFuelType else {
                throw BackendAPIError.invalidResponse
            }

            try onboardingStore.updateVehicleFuelType(selectedFuelType)
            try onboardingStore.updateFuelSettings(
                FuelSettings(
                    currency: quote.currency,
                    pricePerLiter: quote.pricePerLiter,
                    source: .officialPublicData,
                    capturedAt: quote.observedAt,
                    fuelType: quote.fuelType,
                    sourceIdentifier: quote.source,
                    sourceURL: quote.sourceURL,
                    locality: quote.locality
                )
            )
            selectedCurrency = quote.currency
            fuelPriceText = Self.priceText(quote.pricePerLiter)
            feedbackIsError = false
            feedbackKey = "profile.fuel.official.loaded"
        } catch let error as BackendAPIError {
            feedbackIsError = true
            if case .apiStatus(_, let code) = error, code == "fuel_price_unavailable" {
                feedbackKey = "profile.fuel.official.unavailable"
            } else {
                feedbackKey = "profile.fuel.official.failed"
            }
        } catch {
            feedbackIsError = true
            feedbackKey = "profile.fuel.official.failed"
        }
    }

    private var officialPriceDetail: String {
        let settings = onboardingStore.fuelSettings
        let date = settings.capturedAt?.formatted(date: .abbreviated, time: .omitted) ?? "—"
        let locality = settings.locality ?? String(localized: "profile.fuel.official.localityUnknown")
        return String.localizedStringWithFormat(
            String(localized: "profile.fuel.official.detail"),
            locality,
            date
        )
    }

    private func saveOdometer() {
        dismissKeyboard()
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

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
