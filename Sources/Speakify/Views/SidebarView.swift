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
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .safeAreaBar(edge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                if reportsQuota {
                    QuotaWidget(quota: displayedQuota)
                }

                SettingsFooterRow()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// Sits below the list, so it has to earn its row appearance by hand. .borderless rendered
// it as flat secondary text with no hover — next to real sidebar rows that highlight and
// take the primary colour, it read as a disabled item rather than the way into Settings.
private struct SettingsFooterRow: View {
    @State private var isHovering = false

    var body: some View {
        SettingsLink {
            Label {
                Text("Settings")
            } icon: {
                Image(systemName: "gearshape")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(
            isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
            in: .rect(cornerRadius: 6)
        )
        .onHover { isHovering = $0 }
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

    private var ratioText: String {
        "\(usedCredits) / \(quota?.characterLimit ?? 0)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Credits (Used/Total)")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.secondary)

            Text(verbatim: ratioText)
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(.secondary)

            QuotaBar(value: progressValue)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Credits (Used/Total)"))
        .accessibilityValue(Text(verbatim: ratioText))
    }
}

// Drawn by hand because neither stock control is the right weight here. The original
// Gauge(.accessoryLinearCapacity) is a watchOS complication style — thick and fully
// saturated, which left a glancing figure as the loudest thing in the sidebar. Swapping it
// for a linear ProgressView only changed the colour: on macOS that style renders at the very
// same height, and a solid grey bar of that thickness reads heavier still. Two capsules give
// an exact height and a fill subtle enough for a number nobody stares at. Running low is
// already reported in words by the status row, so this does not need to raise an alarm.
private struct QuotaBar: View {
    let value: Double
    @ScaledMetric private var height: CGFloat = 3

    var body: some View {
        Capsule()
            .fill(.quaternary)
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(.tertiary)
                        .frame(width: proxy.size.width * min(max(value, 0), 1))
                }
            }
            .accessibilityHidden(true)
    }
}
