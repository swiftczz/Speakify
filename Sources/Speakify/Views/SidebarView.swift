import AppKit
import SwiftUI

/// The window's left pane: navigation, the remaining-credit readout, and the
/// Settings link. A plain `List` in the sidebar style, so row selection and hover
/// still come from the system even though the pane is placed by hand.
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

                SettingsLink {
                    Label {
                        Text("Settings")
                    } icon: {
                        Image(systemName: "gearshape")
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        // Outside a `NavigationSplitView` the list no longer inherits the window's
        // sidebar material, so it paints its own — and `ignoresSafeArea` carries that
        // material up behind the toolbar. Without it the pane started below the
        // toolbar and left a white strip across its top, which the system container
        // never showed.
        .background(SidebarMaterial().ignoresSafeArea())
    }
}

/// The genuine sidebar vibrancy. `.regularMaterial` reads noticeably greyer than a
/// real sidebar, and the window-background colour is flat, so this uses the same
/// AppKit material the system container would have supplied.
private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
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
        // The `Spacer` has to sit outside the `Label`, not inside its title. Nested
        // in the title it made the label greedy for width, and a squeezed sidebar
        // then overflowed its column to the *leading* side — icons clipped away and
        // "Text to Speech" rendered as "xt to Speech" — instead of truncating.
        HStack(spacing: 8) {
            Label {
                Text(LocalizedStringKey(item.title))
                    .lineLimit(1)
                    .truncationMode(.tail)
            } icon: {
                Image(systemName: item.icon)
            }

            Spacer(minLength: 4)

            if let badge = item.badge {
                Text(LocalizedStringKey(badge))
                    .font(.caption)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .layoutPriority(1)
            }
        }
        .tag(item.id)
        .opacity(item.isAvailable ? 1 : 0.52)
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
