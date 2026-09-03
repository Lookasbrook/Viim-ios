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
    @State private var activeFuelPriceLookupID: UUID?
    @State private var fuelPriceLookupTask: Task<Void, Never>?
    @State private var odometerText = ""
    @State private var odometerFeedbackKey: LocalizedStringKey?
    @State private var odometerFeedbackIsError = false
    @State private var vehicleVariants: [FuelEconomyVehicleVariant] = []
    @State private var selectedVehicleVariantID: String?
    @State private var isLoadingVehicleCatalog = false
    @State private var vehicleCatalogFeedbackKey: LocalizedStringKey?
    @State private var vehicleCatalogFeedbackIsError = false
    @State private var activeVehicleCatalogRequestID: UUID?
    @State private var vehicleCatalogTask: Task<Void, Never>?
    @State private var fillUpOdometerText = ""
    @State private var fillUpLitersText = ""
    @State private var isFullTankConfirmed = false
    @State private var fillUpFeedbackKey: LocalizedStringKey?
    @State private var fillUpFeedbackIsError = false
    @State private var fuelCalibration: FuelCalibrationEvidence?
    @State private var latestFuelFillUp: FuelFillUpRecord?
    @State private var isConfirmingLatestFillUpDeletion = false

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

            if let profile = onboardingStore.profile, profile.vehicleType == .voiture {
                vehicleSpecificationSection(profile: profile)
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
                        beginOfficialPriceLookup()
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
                    if let settings = editorFuelSettings,
                       settings.source == .officialPublicData,
                       settings.canSnapshotCost(at: Date()) {
                        Text(officialPriceDetail(settings: settings))
                            .foregroundStyle(ViimColors.success)
                    } else if let settings = editorFuelSettings,
                              settings.source == .officialPublicData {
                        Text("profile.fuel.official.stale")
                            .foregroundStyle(ViimColors.warning)
                    } else if let settings = editorFuelSettings,
                              settings.source != .userProvided {
                        Text("profile.fuel.unverified")
                            .foregroundStyle(ViimColors.warning)
                    } else if let settings = editorFuelSettings,
                              !settings.canSnapshotCost(at: Date()) {
                        Text("profile.fuel.stale")
                            .foregroundStyle(ViimColors.warning)
                    }
                    if let feedbackKey {
                        Text(feedbackKey)
                            .foregroundStyle(feedbackIsError ? Color.red : ViimColors.success)
                    }
                }
            }

            if onboardingStore.profile?.fuelType?.supportsLiquidFuelEstimate == true {
                fuelCalibrationSection
            }
        }
        .viimKeyboardDismissal()
        .navigationTitle("profile.title")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadFuelSettings()
            refreshFuelCalibration()
        }
        .onDisappear {
            cancelOfficialPriceLookup()
            cancelVehicleCatalogLookup()
        }
        .onChange(of: selectedCurrency) { _ in
            synchronizeFuelEditorToSelection()
        }
        .onChange(of: selectedFuelType) { _ in
            synchronizeFuelEditorToSelection()
        }
    }

    private var fuelCalibrationSection: some View {
        Section {
            if let fuelCalibration {
                LabeledContent(
                    "profile.fuelCalibration.consumption",
                    value: fuelCalibration.litersPer100Km.formatted(
                        .number.precision(.fractionLength(1))
                    ) + " L/100 km"
                )
                LabeledContent(
                    "profile.fuelCalibration.evidence",
                    value: String.localizedStringWithFormat(
                        String(localized: "profile.fuelCalibration.evidenceValue"),
                        fuelCalibration.intervalCount,
                        fuelCalibration.totalDistanceKm
                    )
                )
            } else {
                Text("profile.fuelCalibration.pending")
                    .foregroundStyle(ViimColors.warning)
            }

            HStack {
                TextField("profile.fuelCalibration.odometerPlaceholder", text: $fillUpOdometerText)
                    .keyboardType(.decimalPad)
                Text(verbatim: "km")
                    .foregroundStyle(ViimColors.muted)
            }

            HStack {
                TextField("profile.fuelCalibration.litersPlaceholder", text: $fillUpLitersText)
                    .keyboardType(.decimalPad)
                Text(verbatim: "L")
                    .foregroundStyle(ViimColors.muted)
            }

            Toggle("profile.fuelCalibration.fullTankConfirmation", isOn: $isFullTankConfirmed)

            Button("profile.fuelCalibration.save", action: saveFullTankFillUp)
                .frame(maxWidth: .infinity, alignment: .center)

            if let latestFuelFillUp {
                LabeledContent(
                    "profile.fuelCalibration.latest",
                    value: String.localizedStringWithFormat(
                        String(localized: "profile.fuelCalibration.latestValue"),
                        latestFuelFillUp.odometerKm,
                        latestFuelFillUp.liters
                    )
                )
                Button("profile.fuelCalibration.deleteLatest", role: .destructive) {
                    isConfirmingLatestFillUpDeletion = true
                }
            }
        } header: {
            Text("profile.section.fuelCalibration")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("profile.fuelCalibration.help")
                if let fillUpFeedbackKey {
                    Text(fillUpFeedbackKey)
                        .foregroundStyle(fillUpFeedbackIsError ? Color.red : ViimColors.success)
                }
            }
        }
        .alert(
            "profile.fuelCalibration.deleteTitle",
            isPresented: $isConfirmingLatestFillUpDeletion
        ) {
            Button("common.cancel", role: .cancel) {}
            Button("profile.fuelCalibration.deleteConfirm", role: .destructive) {
                deleteLatestFullTankFillUp()
            }
        } message: {
            Text("profile.fuelCalibration.deleteMessage")
        }
    }

    @ViewBuilder
    private func vehicleSpecificationSection(profile: UserProfile) -> some View {
        Section {
            if let specification = profile.vehicleSpecification?.matched(to: profile) {
                LabeledContent("profile.vehicleData.status") {
                    Label("profile.vehicleData.verified", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(ViimColors.success)
                }
                LabeledContent("profile.vehicleData.variant", value: specification.variant)
                LabeledContent("profile.vehicleData.source", value: specification.officialSourceDisplayName)
                LabeledContent("profile.vehicleData.engine", value: specification.engineDescription)
                LabeledContent("profile.vehicleData.transmission", value: specification.transmission)
                LabeledContent(
                    "profile.vehicleData.combinedConsumption",
                    value: specification.combinedLitersPer100Km.formatted(
                        .number.precision(.fractionLength(1))
                    ) + " L/100 km"
                )
                Link(destination: specification.sourceURL) {
                    Label("profile.vehicleData.openSource", systemImage: "safari")
                }

                Button(action: beginVehicleVariantLookup) {
                    if isLoadingVehicleCatalog && vehicleVariants.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("profile.vehicleData.changeVariant", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isLoadingVehicleCatalog)

                vehicleVariantPicker
            } else {
                LabeledContent("profile.vehicleData.status") {
                    Text("profile.vehicleData.indicative")
                        .foregroundStyle(ViimColors.warning)
                }

                Button(action: beginVehicleVariantLookup) {
                    if isLoadingVehicleCatalog && vehicleVariants.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("profile.vehicleData.lookup", systemImage: "checkmark.seal")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isLoadingVehicleCatalog)

                vehicleVariantPicker
            }
        } header: {
            Text("profile.section.vehicleData")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("profile.vehicleData.privacy")
                if let vehicleCatalogFeedbackKey {
                    Text(vehicleCatalogFeedbackKey)
                        .foregroundStyle(vehicleCatalogFeedbackIsError ? Color.red : ViimColors.success)
                }
            }
        }
    }

    @ViewBuilder
    private var vehicleVariantPicker: some View {
        if !vehicleVariants.isEmpty {
            Picker("profile.vehicleData.variant", selection: $selectedVehicleVariantID) {
                Text("profile.vehicleData.variantPlaceholder")
                    .tag(nil as String?)
                ForEach(vehicleVariants) { variant in
                    Text(variant.description).tag(Optional(variant.recordID))
                }
            }

            Button(action: confirmVehicleVariant) {
                if isLoadingVehicleCatalog {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("profile.vehicleData.confirm")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoadingVehicleCatalog || selectedVehicleVariantID == nil)
        }
    }

    private func beginVehicleVariantLookup() {
        guard let profile = onboardingStore.profile,
              profile.vehicleType == .voiture,
              let fuelType = profile.fuelType,
              fuelType.supportsLiquidFuelEstimate,
              let year = Int(profile.vehicleYear.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            vehicleCatalogFeedbackIsError = true
            vehicleCatalogFeedbackKey = "profile.vehicleData.invalidProfile"
            return
        }

        cancelVehicleCatalogLookup(clearVariants: true)
        let request = VehicleCatalogLookupRequest(id: UUID(), profile: profile)
        activeVehicleCatalogRequestID = request.id
        isLoadingVehicleCatalog = true
        vehicleCatalogFeedbackKey = nil
        vehicleCatalogTask = Task {
            defer { finishVehicleCatalogRequest(request.id) }
            do {
                let variants = try await LocalizedVehicleCatalogClient.fetchVariants(
                    country: profile.country,
                    year: year,
                    make: profile.vehicleBrand,
                    model: profile.vehicleModel,
                    expectedFuelType: fuelType
                )
                guard !Task.isCancelled,
                      request.canCommit(
                        activeRequestID: activeVehicleCatalogRequestID,
                        currentProfile: onboardingStore.profile
                      ) else {
                    return
                }
                vehicleVariants = variants
                selectedVehicleVariantID = variants.count == 1 ? variants.first?.recordID : nil
                vehicleCatalogFeedbackIsError = false
                vehicleCatalogFeedbackKey = "profile.vehicleData.variantsLoaded"
            } catch {
                guard !Task.isCancelled, activeVehicleCatalogRequestID == request.id else {
                    return
                }
                vehicleVariants = []
                selectedVehicleVariantID = nil
                vehicleCatalogFeedbackIsError = true
                vehicleCatalogFeedbackKey = "profile.vehicleData.unavailable"
            }
        }
    }

    private func confirmVehicleVariant() {
        guard let profile = onboardingStore.profile,
              let fuelType = profile.fuelType,
              fuelType.supportsLiquidFuelEstimate,
              let year = Int(profile.vehicleYear.trimmingCharacters(in: .whitespacesAndNewlines)),
              let selectedVehicleVariantID,
              let variant = vehicleVariants.first(where: { $0.recordID == selectedVehicleVariantID }) else {
            vehicleCatalogFeedbackIsError = true
            vehicleCatalogFeedbackKey = "profile.vehicleData.selectVariant"
            return
        }

        cancelVehicleCatalogLookup(clearVariants: false)
        let request = VehicleCatalogLookupRequest(id: UUID(), profile: profile)
        activeVehicleCatalogRequestID = request.id
        isLoadingVehicleCatalog = true
        vehicleCatalogFeedbackKey = nil
        vehicleCatalogTask = Task {
            defer { finishVehicleCatalogRequest(request.id) }
            do {
                let specification = try await LocalizedVehicleCatalogClient.fetchSpecification(
                    variant: variant,
                    expectedYear: year,
                    expectedMake: profile.vehicleBrand,
                    expectedModel: profile.vehicleModel,
                    expectedFuelType: fuelType
                )
                guard !Task.isCancelled,
                      request.canCommit(
                        activeRequestID: activeVehicleCatalogRequestID,
                        currentProfile: onboardingStore.profile
                      ) else {
                    return
                }
                try onboardingStore.updateVehicleSpecification(specification)
                vehicleVariants = []
                self.selectedVehicleVariantID = nil
                vehicleCatalogFeedbackIsError = false
                vehicleCatalogFeedbackKey = "profile.vehicleData.saved"
            } catch {
                guard !Task.isCancelled, activeVehicleCatalogRequestID == request.id else {
                    return
                }
                vehicleCatalogFeedbackIsError = true
                vehicleCatalogFeedbackKey = "profile.vehicleData.unavailable"
            }
        }
    }

    private func finishVehicleCatalogRequest(_ requestID: UUID) {
        guard activeVehicleCatalogRequestID == requestID else {
            return
        }
        vehicleCatalogTask = nil
        activeVehicleCatalogRequestID = nil
        isLoadingVehicleCatalog = false
    }

    private func cancelVehicleCatalogLookup(clearVariants: Bool = false) {
        vehicleCatalogTask?.cancel()
        vehicleCatalogTask = nil
        activeVehicleCatalogRequestID = nil
        isLoadingVehicleCatalog = false
        if clearVariants {
            vehicleVariants = []
            selectedVehicleVariantID = nil
        }
    }

    private func loadFuelSettings() {
        let settings = onboardingStore.fuelSettings
        selectedFuelType = onboardingStore.profile?.fuelType ?? settings.fuelType
        selectedCurrency = settings.currency
        fuelPriceText = settings.canSnapshotCost && settings.fuelType == selectedFuelType
            ? FuelPriceEditorPolicy.priceText(settings.pricePerLiter)
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

        do {
            let settingsToSave = FuelPriceEditorPolicy.settingsForSave(
                currentSettings: onboardingStore.fuelSettings,
                selectedFuelType: selectedFuelType,
                selectedCurrency: selectedCurrency,
                parsedPrice: price,
                now: Date()
            )
            try onboardingStore.updateFuelConfiguration(
                fuelType: selectedFuelType,
                settings: settingsToSave
            )
            feedbackIsError = false
            feedbackKey = "profile.fuel.saved"
        } catch {
            feedbackIsError = true
            feedbackKey = "profile.fuel.invalid"
        }
    }

    private func saveFullTankFillUp() {
        dismissKeyboard()
        guard let profile = onboardingStore.profile,
              let odometer = Self.decimalValue(fillUpOdometerText),
              let liters = Self.decimalValue(fillUpLitersText) else {
            fillUpFeedbackIsError = true
            fillUpFeedbackKey = "profile.fuelCalibration.invalid"
            return
        }
        do {
            try tripManager.recordFullTankFillUp(
                profile: profile,
                odometerKm: odometer,
                liters: liters,
                fullTankConfirmed: isFullTankConfirmed
            )
            fillUpOdometerText = ""
            fillUpLitersText = ""
            isFullTankConfirmed = false
            refreshFuelCalibration()
            fillUpFeedbackIsError = false
            fillUpFeedbackKey = fuelCalibration == nil
                ? "profile.fuelCalibration.savedPending"
                : "profile.fuelCalibration.savedCalibrated"
        } catch {
            fillUpFeedbackIsError = true
            switch error as? FuelFillUpValidationError {
            case .fullTankConfirmationRequired:
                fillUpFeedbackKey = "profile.fuelCalibration.confirmRequired"
            case .nonMonotonicOdometer, .nonMonotonicDate:
                fillUpFeedbackKey = "profile.fuelCalibration.nonMonotonic"
            default:
                fillUpFeedbackKey = "profile.fuelCalibration.invalid"
            }
        }
    }

    private func refreshFuelCalibration() {
        fuelCalibration = tripManager.fuelCalibration(for: onboardingStore.profile)
        if let profile = onboardingStore.profile {
            latestFuelFillUp = try? tripManager.fuelFillUps(for: profile, limit: 1).first
        } else {
            latestFuelFillUp = nil
        }
    }

    private func deleteLatestFullTankFillUp() {
        guard let profile = onboardingStore.profile else { return }
        do {
            try tripManager.deleteLatestFullTankFillUp(profile: profile)
            refreshFuelCalibration()
            fillUpFeedbackIsError = false
            fillUpFeedbackKey = "profile.fuelCalibration.deleted"
        } catch {
            fillUpFeedbackIsError = true
            fillUpFeedbackKey = "profile.fuelCalibration.deleteFailed"
        }
    }

    private static func decimalValue(_ text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    private func beginOfficialPriceLookup() {
        guard let selectedFuelType, selectedFuelType.supportsLiquidFuelEstimate else {
            feedbackIsError = true
            feedbackKey = "profile.fuelType.required"
            return
        }

        fuelPriceLookupTask?.cancel()
        let request = FuelPriceLookupRequest(
            id: UUID(),
            profile: onboardingStore.profile,
            settings: onboardingStore.fuelSettings,
            fuelType: selectedFuelType
        )
        activeFuelPriceLookupID = request.id
        isLoadingOfficialPrice = true
        feedbackKey = nil
        fuelPriceLookupTask = Task {
            await loadOfficialLocalPrice(request: request)
        }
    }

    private func cancelOfficialPriceLookup() {
        fuelPriceLookupTask?.cancel()
        fuelPriceLookupTask = nil
        activeFuelPriceLookupID = nil
        isLoadingOfficialPrice = false
    }

    @MainActor
    private func loadOfficialLocalPrice(request: FuelPriceLookupRequest) async {
        defer {
            if activeFuelPriceLookupID == request.id {
                fuelPriceLookupTask = nil
                activeFuelPriceLookupID = nil
                isLoadingOfficialPrice = false
            }
        }

        let requestedAt = Date()
        locationService.requestCurrentLocation()
        var location: CLLocation?
        for _ in 0..<20 {
            guard !Task.isCancelled, activeFuelPriceLookupID == request.id else {
                return
            }
            if let candidate = locationService.latestLocation,
               candidate.horizontalAccuracy > 0,
               candidate.horizontalAccuracy <= 1_000,
               candidate.timestamp >= requestedAt.addingTimeInterval(-60) {
                location = candidate
                break
            }
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }
        }

        guard let location else {
            feedbackIsError = true
            feedbackKey = "profile.fuel.official.locationUnavailable"
            return
        }

        var resolvedCountryCode: String?
        var resolvedRegionCode: String?
        var resolvedLocality: String?
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
                  let locality = FuelPriceLookupRequest.coarseLocality(
                    locality: placemark.locality,
                    regionCode: regionCode
                  ) else {
                throw BackendAPIError.invalidResponse
            }
            resolvedCountryCode = countryCode
            resolvedRegionCode = regionCode
            resolvedLocality = locality

            let quote = try await OfficialFuelPriceLookupCoordinator.shared.fetchCurrentPrice(
                countryCode: countryCode,
                regionCode: regionCode,
                locality: locality,
                fuelType: request.fuelType
            )
            guard !Task.isCancelled,
                  request.canCommit(
                    activeRequestID: activeFuelPriceLookupID,
                    currentProfile: onboardingStore.profile,
                    currentSettings: onboardingStore.fuelSettings,
                    selectedFuelType: selectedFuelType
                  ),
                  quote.fuelType == request.fuelType else {
                throw BackendAPIError.invalidResponse
            }

            let officialSettings = FuelSettings(
                    currency: quote.currency,
                    pricePerLiter: quote.pricePerLiter,
                    source: .officialPublicData,
                    capturedAt: quote.observedAt,
                    fuelType: quote.fuelType,
                    sourceIdentifier: quote.source,
                    sourceURL: quote.sourceURL,
                    locality: quote.locality,
                    locationEvidence: FuelPriceLocationEvidence(
                        countryCode: countryCode,
                        regionCode: regionCode,
                        locality: locality,
                        resolvedAt: Date()
                    )
                )
            try onboardingStore.updateFuelConfiguration(
                fuelType: request.fuelType,
                settings: officialSettings
            )
            selectedCurrency = quote.currency
            fuelPriceText = FuelPriceEditorPolicy.priceText(quote.pricePerLiter)
            feedbackIsError = false
            feedbackKey = "profile.fuel.official.loaded"
        } catch let error as BackendAPIError {
            guard !Task.isCancelled, activeFuelPriceLookupID == request.id else {
                return
            }
            feedbackIsError = true
            if request.canReuseCachedOfficialPrice(
                activeRequestID: activeFuelPriceLookupID,
                currentProfile: onboardingStore.profile,
                currentSettings: onboardingStore.fuelSettings,
                selectedFuelType: selectedFuelType,
                countryCode: resolvedCountryCode,
                regionCode: resolvedRegionCode,
                locality: resolvedLocality,
                at: Date()
            ) {
                feedbackKey = "profile.fuel.official.cached"
            } else if case .apiStatus(_, let code) = error, code == "fuel_price_unavailable" {
                feedbackKey = "profile.fuel.official.unavailable"
            } else {
                feedbackKey = "profile.fuel.official.failed"
            }
        } catch {
            guard !Task.isCancelled, activeFuelPriceLookupID == request.id else {
                return
            }
            feedbackIsError = true
            feedbackKey = "profile.fuel.official.failed"
        }
    }

    private var editorFuelSettings: FuelSettings? {
        let settings = onboardingStore.fuelSettings
        guard settings.fuelType == selectedFuelType,
              settings.currency == selectedCurrency else {
            return nil
        }
        return settings
    }

    private func synchronizeFuelEditorToSelection() {
        if let settings = editorFuelSettings, settings.canSnapshotCost {
            fuelPriceText = FuelPriceEditorPolicy.priceText(settings.pricePerLiter)
        } else {
            fuelPriceText = ""
        }
        feedbackKey = nil
    }

    private func officialPriceDetail(settings: FuelSettings) -> String {
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

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

enum FuelPriceEditorPolicy {
    static func priceText(_ value: Double, locale: Locale = .current) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)).locale(locale))
    }

    static func settingsForSave(
        currentSettings: FuelSettings,
        selectedFuelType: VehicleFuelType,
        selectedCurrency: SupportedCurrency,
        parsedPrice: Double,
        now: Date
    ) -> FuelSettings {
        if currentSettings.source == .officialPublicData,
           currentSettings.fuelType == selectedFuelType,
           currentSettings.currency == selectedCurrency,
           abs(currentSettings.pricePerLiter - parsedPrice) < 0.000_001 {
            return currentSettings
        }
        return FuelSettings(
            currency: selectedCurrency,
            pricePerLiter: parsedPrice,
            source: .userProvided,
            capturedAt: now,
            fuelType: selectedFuelType
        )
    }
}

struct FuelPriceLookupRequest: Equatable {
    let id: UUID
    let profile: UserProfile?
    let settings: FuelSettings
    let fuelType: VehicleFuelType

    func canCommit(
        activeRequestID: UUID?,
        currentProfile: UserProfile?,
        currentSettings: FuelSettings,
        selectedFuelType: VehicleFuelType?
    ) -> Bool {
        activeRequestID == id &&
            currentProfile == profile &&
            currentSettings == settings &&
            selectedFuelType == fuelType
    }

    func canReuseCachedOfficialPrice(
        activeRequestID: UUID?,
        currentProfile: UserProfile?,
        currentSettings: FuelSettings,
        selectedFuelType: VehicleFuelType?,
        countryCode: String?,
        regionCode: String?,
        locality: String?,
        at date: Date
    ) -> Bool {
        guard canCommit(
            activeRequestID: activeRequestID,
            currentProfile: currentProfile,
            currentSettings: currentSettings,
            selectedFuelType: selectedFuelType
        ),
            settings.source == .officialPublicData &&
            settings.fuelType == fuelType &&
            settings.canSnapshotCost(at: date),
            FuelPriceGeographyMatcher.acquisitionMatchesPrice(settings),
            let countryCode,
            let regionCode,
            let locality,
            let cachedLocality = settings.locality else {
            return false
        }

        let country = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let region = Self.normalize(regionCode)
        let normalizedCachedLocality = Self.normalize(cachedLocality)
        switch settings.sourceIdentifier {
        case OfficialFuelPriceEvidenceContract.ontarioIdentifier:
            let expected = OntarioPublicFuelPriceClient.evidenceLocality(locality: locality)
            return country == "CA" &&
                ["on", "ontario"].contains(region) &&
                (normalizedCachedLocality == "ontario" ||
                    normalizedCachedLocality == Self.normalize(expected))
        case OfficialFuelPriceEvidenceContract.statisticsCanadaIdentifier:
            guard country == "CA" else { return false }
            let expected = StatisticsCanadaPublicFuelPriceClient.evidenceLocality(
                region: regionCode,
                locality: locality
            )
            return normalizedCachedLocality == Self.normalize(expected)
        default:
            return false
        }
    }

    static func coarseLocality(locality: String?, regionCode: String) -> String? {
        let region = regionCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !region.isEmpty else {
            return nil
        }
        let city = locality?.trimmingCharacters(in: .whitespacesAndNewlines)
        return city?.isEmpty == false ? city : region
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "fr_CA")
            )
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }
}

struct VehicleCatalogLookupRequest: Equatable {
    let id: UUID
    let profile: UserProfile

    func canCommit(activeRequestID: UUID?, currentProfile: UserProfile?) -> Bool {
        activeRequestID == id && currentProfile == profile
    }
}
