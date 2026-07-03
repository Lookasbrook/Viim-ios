import SwiftUI

struct AccueilView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var locationService: LocationService

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ViimCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("home.vehicle.title")
                                .font(.headline)
                            Text(vehicleDisplayName)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(ViimColors.text)
                            Text(locationService.tripPhase.statusKey)
                                .font(.subheadline)
                                .foregroundStyle(locationService.tripPhase.tint)
                        }
                    }

                    ViimCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("home.summary.title")
                                .font(.headline)
                            Text("home.summary.calibration")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ViimCard {
                        VStack(spacing: 12) {
                            StatusRow(
                                titleKey: "home.status.tripDetection",
                                detailKey: tripDetectionDetailKey,
                                systemImage: "location.fill",
                                tint: locationService.tripPhase.tint
                            )
                            StatusRow(
                                titleKey: "home.status.collisionDetection",
                                detailKey: "status.enabled",
                                systemImage: "exclamationmark.triangle.fill",
                                tint: ViimColors.success
                            )
                            StatusRow(
                                titleKey: "home.status.network",
                                detailKey: "status.offlineReady",
                                systemImage: "wifi",
                                tint: ViimColors.blue
                            )
                        }
                    }
                }
                .padding()
            }
            .background(ViimColors.background)
            .navigationTitle("home.title")
        }
    }

    private var vehicleDisplayName: String {
        onboardingStore.profile?.vehicleDisplayName ?? String(localized: "home.vehicle.empty")
    }

    private var tripDetectionDetailKey: LocalizedStringKey {
        guard locationService.authorizationState.canTrackLocation else {
            return locationService.authorizationState.statusKey
        }
        return locationService.isMonitoring ? locationService.tripPhase.statusKey : "location.monitoring.paused"
    }
}

private extension TripDetectionPhase {
    var statusKey: LocalizedStringKey {
        switch self {
        case .idle: "location.trip.idle"
        case .starting: "location.trip.starting"
        case .active: "location.trip.active"
        case .stopping: "location.trip.stopping"
        }
    }

    var tint: Color {
        switch self {
        case .idle: ViimColors.blue
        case .starting: ViimColors.green
        case .active: ViimColors.success
        case .stopping: ViimColors.red
        }
    }
}

private extension LocationAuthorizationState {
    var statusKey: LocalizedStringKey {
        switch self {
        case .notDetermined: "location.permission.notDetermined"
        case .restricted: "location.permission.restricted"
        case .denied: "location.permission.denied"
        case .authorizedWhenInUse: "location.permission.whenInUse"
        case .authorizedAlways: "location.permission.always"
        }
    }
}
