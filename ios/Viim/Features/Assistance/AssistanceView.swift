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
                                .foregroundStyle(ViimColors.text)
                            Text("assistance.family.empty")
                                .font(.subheadline)
                                .foregroundStyle(ViimColors.muted)
                        }
                    }

                    ViimCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("assistance.medical.title")
                                .font(.headline)
                                .foregroundStyle(ViimColors.text)
                            Text("assistance.medical.privacy")
                                .font(.subheadline)
                                .foregroundStyle(ViimColors.muted)
                        }
                    }

                    Text("assistance.footer.publisher")
                        .font(.caption2)
                        .foregroundStyle(ViimColors.muted)
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
