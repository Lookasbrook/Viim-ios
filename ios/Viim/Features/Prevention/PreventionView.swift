import SwiftUI

struct PreventionView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ViimCard {
                        StatusRow(
                            titleKey: "prevention.dangerZones.title",
                            detailKey: "status.disabled",
                            systemImage: "map.fill",
                            tint: ViimColors.green
                        )
                    }

                    ViimCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("prevention.road.title")
                                .font(.headline)
                                .foregroundStyle(ViimColors.text)
                            Text("prevention.road.placeholder")
                                .font(.subheadline)
                                .foregroundStyle(ViimColors.muted)
                        }
                    }

                    ViimCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("prevention.maintenance.title")
                                .font(.headline)
                                .foregroundStyle(ViimColors.text)
                            Text("prevention.maintenance.placeholder")
                                .font(.subheadline)
                                .foregroundStyle(ViimColors.muted)
                        }
                    }
                }
                .padding()
            }
            .background(ViimColors.background)
            .navigationTitle("prevention.title")
        }
    }
}
