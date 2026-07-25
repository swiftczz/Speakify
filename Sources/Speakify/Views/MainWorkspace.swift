import SwiftUI

/// The centre pane: the text editor and the transport bar below it.
struct MainWorkspace: View {
    let settings: AppSettings
    @Bindable var viewModel: SpeechViewModel
    /// The transport bar holds a row of controls sized to their text, so its height has
    /// to grow with the text rather than sit at a constant.
    @ScaledMetric private var transportHeight: CGFloat = 80

    var body: some View {
        VStack(spacing: 18) {
            EditorCard(viewModel: viewModel)
                .frame(maxHeight: .infinity)

            PlayerBar(
                settings: settings,
                viewModel: viewModel,
                playback: viewModel.playback
            )
                .frame(height: transportHeight)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        // The window background, one step above the editor card's surface. Both come
        // from the same system hierarchy now, so the step between them is the system's
        // to define rather than a pair of colours chosen to sit near each other.
        .background(.background)
        // The heading used to be a `Text` drawn at the top of this pane while the real
        // window title was suppressed. It is the window's title; the toolbar shows it.
        //
        // Resolved through `L10n`, not as a `LocalizedStringKey`. A navigation title
        // becomes the *window's* title, and that is settled at the scene level — outside
        // the view tree carrying `\.locale` — so a literal here followed the system
        // language while every other string in the window followed the app's own picker.
        // Same reason `SpeechCommands` cannot use literals either.
        .navigationTitle(Text(verbatim: L10n.string("Text to Speech", defaultValue: "Text to Speech")))
    }
}

private struct EditorCard: View {
    @Bindable var viewModel: SpeechViewModel
    @FocusState private var isEditorFocused: Bool
    @ScaledMetric private var minimumHeight: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $viewModel.text)
                .font(.title3)
                .lineSpacing(8)
                .scrollContentBackground(.hidden)
                .focused($isEditorFocused)
                .padding(22)

            HStack(alignment: .center, spacing: 16) {
                Text("\(viewModel.characterCount) / \(viewModel.characterLimit)")
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(viewModel.isTextOverLimit ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))

                Spacer(minLength: 12)

                GenerationStatusView(viewModel: viewModel)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
        .frame(minHeight: minimumHeight)
        // Content, not chrome: a text surface stays opaque so the writing behind it
        // never competes with the glass on the transport bar below. Opaque, but taken
        // from the system's background hierarchy one step down from the window's own —
        // it used to be two hand-mixed RGB values, right in the two appearances they
        // were sampled in and nowhere else. Neither answered Increase Contrast, Reduce
        // Transparency or a colour filter.
        //
        // The drop shadows went with them. A pair of stacked `.black` shadows is a web
        // card idiom; in dark mode they are invisible noise, and macOS 26 separates
        // content regions with a step in material rather than by casting them into the
        // air. No border stands in for them either.
        //
        // `ConcentricRectangle` rather than a stated radius: the corner is derived from
        // the container it sits in, so it stays concentric with the window instead of
        // holding a constant 14 that only matched one window corner radius.
        .background(.background.secondary, in: ConcentricRectangle())
    }
}

private struct GenerationStatusView: View {
    let viewModel: SpeechViewModel
    @ScaledMetric private var maximumWidth: CGFloat = 420

    private var foregroundStyle: AnyShapeStyle {
        switch viewModel.visibleStatusTone {
        case .info:
            return AnyShapeStyle(.secondary)
        case .success:
            return AnyShapeStyle(.green)
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
