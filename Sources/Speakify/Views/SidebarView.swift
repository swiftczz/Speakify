import SwiftUI

/// The left pane: navigation, the remaining-credit readout, and the Settings link.
struct SidebarView: View {
    let reportsQuota: Bool
    let displayedQuota: TTSQuota?
    @State private var isHoveringSettings = false

    private let primaryItems = [
        NavItem(id: "text-to-speech", title: "Text to Speech", icon: "waveform", selected: true),
        NavItem(id: "voices", title: "Voices", icon: "person.wave.2", badge: "Soon"),
        NavItem(id: "voice-cloning", title: "Voice Cloning", icon: "person.crop.circle.badge.plus", badge: "Soon"),
        NavItem(id: "voice-library", title: "Voice Library", icon: "books.vertical", badge: "Soon"),
        NavItem(id: "projects", title: "Projects", icon: "folder", badge: "Soon")
    ]

    private let secondaryItems = [
        NavItem(id: "history", title: "History", icon: "clock.arrow.circlepath", badge: "Soon"),
        NavItem(id: "templates", title: "Templates", icon: "square.grid.2x2", badge: "Soon")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer().frame(height: 14)

            VStack(spacing: 5) {
                ForEach(primaryItems) { item in
                    SidebarRow(item: item)
                }
            }

            Divider()
                .padding(.trailing, 4)

            VStack(spacing: 5) {
                ForEach(secondaryItems) { item in
                    SidebarRow(item: item)
                }
            }

            Spacer(minLength: 20)

            if reportsQuota {
                QuotaWidget(quota: displayedQuota)
                    .padding(.bottom, 8)
            }

            SettingsLink {
                HStack(spacing: 14) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16))
                        .frame(width: 24)
                    Text("Settings")
                        .font(.system(size: 14, weight: .regular))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppPalette.controlBackground)
                    .opacity(isHoveringSettings ? 1 : 0)
            }
            .onHover { isHoveringSettings = $0 }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
        .background(AppPalette.sidebarBackground)
    }
}

private struct NavItem: Identifiable {
    let id: String
    let title: String
    let icon: String
    var selected = false
    var badge: String?

    var isAvailable: Bool {
        selected || badge == nil
    }
}

private struct SidebarRow: View {
    let item: NavItem

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.icon)
                .font(.system(size: 17))
                .frame(width: 24)

            Text(LocalizedStringKey(item.title))
                .font(.system(size: 14, weight: .regular))

            Spacer()

            if let badge = item.badge {
                Text(LocalizedStringKey(badge))
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppPalette.controlBackground.opacity(0.80), in: Capsule())
                    .overlay {
                        Capsule().stroke(AppPalette.stroke, lineWidth: 1)
                    }
            }
        }
        .foregroundStyle(item.selected ? AppPalette.accent : AppPalette.ink)
        .opacity(item.isAvailable ? 1 : 0.52)
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background {
            if item.selected {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(AppPalette.selectedNav)
            }
        }
    }
}

private struct QuotaWidget: View {
    let quota: TTSQuota?

    private var remainingCredits: Int {
        quota?.remaining ?? 0
    }

    private var progressValue: Double {
        quota?.usedFraction ?? 0
    }

    private var progressColor: Color {
        if remainingCredits < 1000 {
            return .red
        }
        if remainingCredits < 3000 {
            return .yellow
        }
        return .green
    }

    private var ratioText: String {
        "\(remainingCredits) / \(quota?.characterLimit ?? 0)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Credits (Remaining/Total)")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(AppPalette.ink)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Text(ratioText)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(AppPalette.ink)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(AppPalette.stroke.opacity(0.24))
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(AppPalette.stroke.opacity(0.45), lineWidth: 0.5)
                        }

                    Capsule(style: .continuous)
                        .fill(progressColor)
                        .frame(width: geo.size.width * progressValue)
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
