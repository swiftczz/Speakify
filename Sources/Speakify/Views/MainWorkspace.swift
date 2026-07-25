import SwiftUI

/// The centre pane: the title, the text editor, and the transport bar below it.
struct MainWorkspace: View {
    let settings: AppSettings
    @Bindable var viewModel: SpeechViewModel

    var body: some View {
        VStack(spacing: 18) {
            Text("Text to Speech")
                .font(.title2.bold())
                .foregroundStyle(AppPalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            EditorCard(viewModel: viewModel)
                .frame(minHeight: 320, maxHeight: .infinity)

            PlayerBar(
                settings: settings,
                viewModel: viewModel,
                playback: viewModel.playback
            )
                .frame(height: 80)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(AppPalette.contentBackground)
    }
}

private struct EditorCard: View {
    @Bindable var viewModel: SpeechViewModel
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $viewModel.text)
                .font(.title3)
                .lineSpacing(8)
                .scrollContentBackground(.hidden)
                .foregroundStyle(AppPalette.ink)
                .focused($isEditorFocused)
                .padding(22)

            HStack(alignment: .center, spacing: 16) {
                Text("\(viewModel.characterCount) / \(viewModel.characterLimit)")
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(viewModel.isTextOverLimit ? Color.red : AppPalette.muted)

                Spacer(minLength: 12)

                GenerationStatusView(viewModel: viewModel)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
        // Content, not chrome: a text surface stays opaque so the writing behind it
        // never competes with the glass on the transport bar below.
        .background(AppPalette.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 1)
        .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 0)
        .onAppear { isEditorFocused = true }
        // The ⌘L menu command bumps a counter rather than reaching into this
        // view's focus state, which lives too deep to expose as a focused value.
        .onChange(of: viewModel.editorFocusRequests) { _, _ in
            isEditorFocused = true
        }
    }
}

private struct GenerationStatusView: View {
    let viewModel: SpeechViewModel

    private var foregroundColor: Color {
        switch viewModel.visibleStatusTone {
        case .info:
            return AppPalette.muted
        case .success:
            return .green
        case .error:
            return .red
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
        .foregroundStyle(foregroundColor.opacity(0.82))
        .frame(maxWidth: 420, alignment: .trailing)
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
