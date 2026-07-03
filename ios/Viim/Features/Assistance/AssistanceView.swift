import SwiftUI

struct AssistanceView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    AssistanceHero()

                    ViimCard {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Label("assistance.realtime.title", systemImage: "dot.radiowaves.left.and.right")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(ViimColors.text)
                                Spacer()
                                ViimChip(titleKey: "status.enabled", style: .success)
                            }
                            Text("assistance.realtime.detail")
                                .font(.caption)
                                .foregroundStyle(ViimColors.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    ViimCard {
                        VStack(spacing: 0) {
                            AssistanceListRow(icon: "location.fill", titleKey: "assistance.location.title", detailKey: "assistance.row.open", tint: ViimColors.blue)
                            AssistanceListRow(icon: "person.2.fill", titleKey: "assistance.contacts.title", detailKey: "assistance.contacts.status", tint: ViimColors.navy)
                            AssistanceListRow(icon: "cross.case.fill", titleKey: "assistance.medical.title", detailKey: "assistance.medical.status", tint: ViimColors.green)
                            AssistanceListRow(icon: "doc.text.fill", titleKey: "assistance.report.title", detailKey: "assistance.row.open", tint: ViimColors.gold)
                            AssistanceListRow(icon: "wrench.and.screwdriver.fill", titleKey: "assistance.towing.title", detailKey: "assistance.row.open", tint: ViimColors.warning, showsDivider: false)
                        }
                    }

                    SectionHeader(titleKey: "assistance.emergency.section", tint: ViimColors.red)

                    HStack(spacing: 10) {
                        EmergencyButton(titleKey: "assistance.firefighters.title", detailKey: "assistance.firefighters.detail", tint: ViimColors.red)
                        EmergencyButton(titleKey: "assistance.police.title", detailKey: "assistance.police.detail", tint: ViimColors.navy)
                    }

                    ViimCard {
                        AssistanceListRow(icon: "cross.vial.fill", titleKey: "assistance.hospitals.title", detailKey: "assistance.hospitals.detail", tint: ViimColors.red, showsDivider: false)
                    }

                    Text("assistance.medical.privacy")
                        .font(.caption)
                        .foregroundStyle(ViimColors.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)

                    Text("assistance.footer.publisher")
                        .font(.caption2)
                        .foregroundStyle(Color(hex: 0xA9B8C6))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(ViimColors.background.ignoresSafeArea())
            .navigationTitle("assistance.title")
        }
    }
}

private struct AssistanceHero: View {
    var body: some View {
        ZStack(alignment: .leading) {
            LinearGradient(
                colors: [Color(hex: 0x7A1010), ViimColors.red],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 78, weight: .bold))
                .foregroundStyle(.white.opacity(0.13))
                .offset(x: 210, y: 10)
            VStack(alignment: .leading, spacing: 6) {
                Text("assistance.title")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("assistance.hero.detail")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .padding(18)
        }
        .frame(height: 132)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct AssistanceListRow: View {
    let icon: String
    let titleKey: LocalizedStringKey
    let detailKey: LocalizedStringKey
    let tint: Color
    var showsDivider = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.12))
                    .clipShape(Circle())
                Text(titleKey)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ViimColors.text)
                Spacer(minLength: 8)
                Text(detailKey)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ViimColors.muted)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            .frame(minHeight: 48)

            if showsDivider {
                Divider()
                    .padding(.leading, 45)
            }
        }
    }
}

private struct SectionHeader: View {
    let titleKey: LocalizedStringKey
    let tint: Color

    var body: some View {
        Text(titleKey)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(ViimColors.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
    }
}

private struct EmergencyButton: View {
    let titleKey: LocalizedStringKey
    let detailKey: LocalizedStringKey
    let tint: Color

    var body: some View {
        Button(action: {}) {
            VStack(spacing: 4) {
                Text(titleKey)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(detailKey)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(tint)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
