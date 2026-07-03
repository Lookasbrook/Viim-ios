import SwiftUI

struct AssistanceView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ViimCard {
                        StatusRow(
                            titleKey: "assistance.realtime.title",
                            detailKey: "status.enabled",
                            systemImage: "cross.case.fill",
                            tint: ViimColors.red
                        )
                    }

                    ViimCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("assistance.family.title")
                                .font(.headline)
                            Text("assistance.family.empty")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ViimCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("assistance.medical.title")
                                .font(.headline)
                            Text("assistance.medical.privacy")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("assistance.footer.publisher")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
                .padding()
            }
            .background(ViimColors.background)
            .navigationTitle("assistance.title")
        }
    }
}
