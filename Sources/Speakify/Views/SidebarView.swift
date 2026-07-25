import SwiftUI

struct SidebarView: View {
    let reportsQuota: Bool
    let displayedQuota: TTSQuota?
    @State private var selection: String? = "text-to-speech"

    private let primaryItems = [
        NavItem(id: "text-to-speech", title: "Text to Speech", icon: "waveform"),
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
        List(selection: $selection) {
            Section {
                ForEach(primaryItems) { item in
                    SidebarRow(item: item)
                }
            }

            Section {
                ForEach(secondaryItems) { item in
                    SidebarRow(item: item)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                if reportsQuota {
                    QuotaWidget(quota: displayedQuota)
                }

                SettingsLink {
                    Label {
                        Text("Settings")
                    } icon: {
                        Image(systemName: "gearshape")
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct NavItem: Identifiable {
    let id: String
    let title: String
    let icon: String
    var badge: String?

    var isAvailable: Bool {
        badge == nil
    }
}

private struct SidebarRow: View {
    let item: NavItem

    var body: some View {
        Label {
            Text(LocalizedStringKey(item.title))
                .lineLimit(1)
                .truncationMode(.tail)
        } icon: {
            Image(systemName: item.icon)
        }
        .badge(item.badge.map { Text(LocalizedStringKey($0)) })
        .foregroundStyle(item.isAvailable ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .tag(item.id)
        .disabled(item.isAvailable == false)
    }
}

private struct QuotaWidget: View {
    let quota: TTSQuota?

    private var usedCredits: Int {
        quota?.characterCount ?? 0
    }

    private var progressValue: Double {
        quota?.usedFraction ?? 0
    }

    private var progressColor: Color {
        if progressValue >= 0.9 {
            return .red
        }
        if progressValue >= 0.7 {
            return .yellow
        }
        return .green
    }

    private var ratioText: String {
        "\(usedCredits) / \(quota?.characterLimit ?? 0)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Credits (Used/Total)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(verbatim: ratioText)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)

            ProgressView(value: progressValue)
                .tint(progressColor)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Credits (Used/Total)"))
        .accessibilityValue(Text(verbatim: ratioText))
    }
}
