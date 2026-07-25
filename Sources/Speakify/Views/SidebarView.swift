import SwiftUI

/// The window's left pane: navigation, the remaining-credit readout, and the
/// Settings link. A plain `List` in the sidebar style, sitting in the split
/// view's sidebar column, so selection, hover and the Liquid Glass background all
/// come from the system.
struct SidebarView: View {
    let reportsQuota: Bool
    let displayedQuota: TTSQuota?
    /// The only destination that exists today. Held in state so the row draws with
    /// the system's real selection treatment rather than a hand-painted highlight.
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
        // The List has to be the column's root view. Wrapping it in a VStack cost it
        // the sidebar's leading inset — icons vanished and every label was clipped —
        // and pinning a footer with `.safeAreaInset` laid that footer out against the
        // whole window, so it overflowed the column. The footer is a trailing section
        // instead; with seven fixed rows above it, nothing ever scrolls out of reach.
        //
        // Nothing paints a background here. In the split view's sidebar column the
        // system supplies the material, and on macOS 26 that material is Liquid Glass:
        // an `NSVisualEffectView` set to `.sidebar` used to stand in for it, which
        // pinned the pane to the flat vibrancy of the previous design language.
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

            Section {
                if reportsQuota {
                    QuotaWidget(quota: displayedQuota)
                }

                // `.borderless`, not `.plain`. A plain button draws nothing at all,
                // so this row alone had no hover and no pressed state while every row
                // above it did — it read as something that had fallen out of the list.
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
        }
        .listStyle(.sidebar)
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
        // `.badge` and `.disabled`, not a hand-drawn capsule and a hand-set opacity.
        // The list places the badge, styles it, flips it for the selected row and dims
        // the whole row when disabled — all of which the `HStack` + `Capsule` +
        // `.opacity(0.52)` this replaces had to approximate, and did not get right in
        // the selected state.
        Label {
            Text(LocalizedStringKey(item.title))
                .lineLimit(1)
                .truncationMode(.tail)
        } icon: {
            Image(systemName: item.icon)
        }
        .badge(item.badge.map { Text(LocalizedStringKey($0)) })
        // `.disabled` stops the row being chosen but does not dim it in a sidebar list,
        // so the unavailable rows read as available. `.secondary` is the system's own
        // "less prominent" style — the `.opacity(0.52)` this replaces was a fixed
        // fraction that ignored Increase Contrast.
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
        // Stacked rather than one row: at the 200pt minimum sidebar width the label
        // and the ratio could not share a line, and the label was clipped.
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
