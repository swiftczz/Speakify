import SwiftUI

struct MainWorkspace: View {
    let settings: AppSettings
    @Bindable var viewModel: SpeechViewModel
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
        .background(.background)
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
