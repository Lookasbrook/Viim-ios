import SwiftUI

struct ConduiteView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ViimCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("driving.score.title")
                                .font(.headline)
                            Text("driving.score.calibration")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ViimCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("driving.portrait.title")
                                .font(.headline)
                            StatusRow(titleKey: "driving.criteria.speed", detailKey: "status.pendingCalibration", systemImage: "speedometer", tint: ViimColors.blue)
                            StatusRow(titleKey: "driving.criteria.smoothness", detailKey: "status.pendingCalibration", systemImage: "waveform.path.ecg", tint: ViimColors.blue)
                            StatusRow(titleKey: "driving.criteria.vigilance", detailKey: "status.pendingCalibration", systemImage: "iphone.slash", tint: ViimColors.blue)
                        }
                    }
                }
                .padding()
            }
            .background(ViimColors.background)
            .navigationTitle("driving.title")
        }
    }
}
