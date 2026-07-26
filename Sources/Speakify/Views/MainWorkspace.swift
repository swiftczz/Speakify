import SwiftUI

struct MainWorkspace: View {
    let settings: AppSettings
    @Bindable var viewModel: SpeechViewModel
    @Binding var isHistoryVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SpeechEditor(viewModel: viewModel)
            .safeAreaBar(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    EditorStatusRow(viewModel: viewModel)

                    PlayerBar(
                        settings: settings,
                        viewModel: viewModel,
                        playback: viewModel.playback
                    )
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                // Matching the toolbar means matching its tone, not hunting for a
                // translucent material. The toolbar reads as glass because it is the same
                // white as the editor and the hard scroll edge effect cuts the text off
                // cleanly underneath it — nothing shows through it either. Every material
                // tried here (.bar, .regularMaterial, .glassEffect) put a visibly greyer
                // slab under the controls, which is what read as "opaque".
                .background(.background)
            }
            // Top only. The bottom edge gets no effect from this at all: the style binds to
            // the window toolbar, and macOS has no bottom toolbar to bind to — .bottomBar is
            // unavailable on macOS, and safeAreaBar does not stand in for one. Declaring
            // .vertical here looks symmetric and does nothing. Verified by A/B build.
            .scrollEdgeEffectStyle(.hard, for: .top)
            // Declared on the detail column, not on the split view, so it lands in the
            // detail's own toolbar segment and stays pinned above the content area whether
            // or not the inspector is open. That frees the inspector's segment for the
            // system search field, which is the only way to have .searchable and still have
            // it line up with the column it filters.
            .toolbar {
                ToolbarSpacer(.flexible, placement: .automatic)

                // A Button rather than a Toggle: .toggleStyle(.button) fills the on state with
                // the accent colour, which is far louder than this control deserves and does
                // not match its pair — the sidebar toggle NavigationSplitView puts on the
                // leading side shows no on state either. The state still reaches VoiceOver
                // through the selected trait, it just isn't shouted in colour.
                ToolbarItem(placement: .automatic) {
                    Button {
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) {
                            isHistoryVisible.toggle()
                        }
                    } label: {
                        Label {
                            Text("History")
                        } icon: {
                            Image(systemName: "sidebar.trailing")
                        }
                    }
                    .help(isHistoryVisible ? Text("Hide History") : Text("Show History"))
                    .accessibilityAddTraits(isHistoryVisible ? .isSelected : [])
                }
            }
            .navigationTitle(Text(verbatim: L10n.string("Text to Speech", defaultValue: "Text to Speech")))
    }
}

// The editor is the detail column's scroll view, running edge to edge so its text
// passes under the toolbar and the bottom bar. That is what gives the toolbar
// something to refract and lets the scroll edge effects resolve on their own; the
// earlier inset card left an opaque strip under the toolbar and neither could show.
private struct SpeechEditor: View {
    @Bindable var viewModel: SpeechViewModel
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        TextEditor(text: $viewModel.text)
            .font(.title3)
            .lineSpacing(8)
            .scrollContentBackground(.hidden)
            .focused($isEditorFocused)
            .padding(.horizontal, 24)
            .background(.background)
    }
}

private struct EditorStatusRow: View {
    let viewModel: SpeechViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("\(viewModel.characterCount) / \(viewModel.characterLimit)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(viewModel.isTextOverLimit ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))

            Spacer(minLength: 12)

            GenerationStatusView(viewModel: viewModel)
        }
        .padding(.horizontal, 20)
    }
}

private struct GenerationStatusView: View {
    let viewModel: SpeechViewModel
    @ScaledMetric private var maximumWidth: CGFloat = 420

    // Success stays neutral. Colour in a status line is a signal that something needs
    // attention, and spending green on "this worked" both drains it of that meaning and
    // leaves a coloured string sitting in the bar through every successful run. The
    // checkmark already carries the outcome. Red is kept, because errors do need it.
    private var foregroundStyle: AnyShapeStyle {
        switch viewModel.visibleStatusTone {
        case .info, .success:
            return AnyShapeStyle(.secondary)
        case .error:
            return AnyShapeStyle(.red)
        }
    }

    private var symbolName: String {
        switch viewModel.visibleStatusTone {
        case .info:
            return viewModel.isGenerating ? "hourglass" : "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbolName)
                .font(.caption2.weight(.semibold))
                .contentTransition(.symbolEffect(.replace))

            Text(viewModel.visibleStatusMessage)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(foregroundStyle)
        .frame(maxWidth: maximumWidth, alignment: .trailing)
        .help(viewModel.visibleStatusMessage)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            L10n.format(
                "Speech status: %@",
                defaultValue: "Speech status: %@",
                viewModel.visibleStatusMessage
            )
        )
    }
}
