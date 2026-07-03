import SwiftUI

struct AccueilView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ViimCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("home.vehicle.title")
                                .font(.headline)
                            Text("home.vehicle.status")
                                .font(.subheadline)
                                .foregroundStyle(ViimColors.success)
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
                                detailKey: "status.enabled",
                                systemImage: "location.fill",
                                tint: ViimColors.success
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
}
