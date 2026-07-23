import SwiftUI

/// The toolbar's service + model picker. Service and model are chosen together so
/// one menu covers "which engine, which voice quality" in a single step.
struct ServiceModelToolbarPicker: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var viewModel: SpeechViewModel

    private var selection: Binding<ServiceModelSelection> {
        Binding {
            ServiceModelSelection(
                providerID: settings.providerID,
                modelID: settings.modelID
            )
        } set: { selection in
            if settings.providerID != selection.providerID {
                settings.providerID = selection.providerID
            }
            settings.modelID = selection.modelID
        }
    }

    var body: some View {
        Picker("Service and model", selection: selection) {
            ForEach(viewModel.providerOptions) { provider in
                Section(provider.name) {
                    ForEach(models(for: provider.id)) { model in
                        Text("\(provider.name) · \(model.name)")
                            .tag(
                                ServiceModelSelection(
                                    providerID: provider.id,
                                    modelID: model.id
                                )
                            )
                    }
                }
            }
        }
        .labelsHidden()
        .controlSize(.small)
        .frame(width: 228)
        .help("Speech service and model")
        .accessibilityLabel("Speech service and model")
    }

    private func models(for providerID: String) -> [TTSModel] {
        if providerID == settings.providerID, viewModel.models.isEmpty == false {
            return viewModel.models
        }
        return TTSProviderRegistry.provider(withID: providerID).fallbackModels
    }
}

private struct ServiceModelSelection: Hashable {
    let providerID: String
    let modelID: String
}

/// The toolbar's voice button and the popover it opens.
struct VoiceToolbarPicker: View {
    @ObservedObject var viewModel: SpeechViewModel
    @StateObject private var previewPlayer = VoicePreviewPlayer()
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(viewModel.selectedVoice?.name ?? "Select Voice")
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 138, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(viewModel.selectedVoice?.displayName ?? "Select a voice")
        .accessibilityLabel("Voice")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VoiceSelectionPopover(
                viewModel: viewModel,
                previewPlayer: previewPlayer,
                isPresented: $isPresented
            )
        }
        .onChange(of: viewModel.activeProvider.id) { _, _ in
            previewPlayer.stop()
            isPresented = false
        }
    }
}

private struct VoiceSelectionPopover: View {
    @ObservedObject var viewModel: SpeechViewModel
    @ObservedObject var previewPlayer: VoicePreviewPlayer
    @Binding var isPresented: Bool

    private var rowCount: Int {
        viewModel.publicVoices.count + viewModel.accountVoices.count
    }

    private var listHeight: CGFloat {
        min(max(CGFloat(rowCount) * 36 + 12, 48), 420)
    }

    private var previewConfiguration: VoicePreviewConfiguration {
        VoicePreviewConfiguration(
            provider: viewModel.activeProvider,
            modelID: viewModel.settings.modelID,
            apiKey: viewModel.settings.apiKey
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(viewModel.publicVoices) { voice in
                    VoiceOptionRow(
                        voice: voice,
                        isSelected: viewModel.selectedVoice?.id == voice.id,
                        previewPlayer: previewPlayer,
                        previewConfiguration: previewConfiguration,
                        onSelect: { select(voice) }
                    )
                }

                if viewModel.publicVoices.isEmpty == false,
                   viewModel.accountVoices.isEmpty == false {
                    Divider()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }

                ForEach(viewModel.accountVoices) { voice in
                    VoiceOptionRow(
                        voice: voice,
                        isSelected: viewModel.selectedVoice?.id == voice.id,
                        previewPlayer: previewPlayer,
                        previewConfiguration: previewConfiguration,
                        onSelect: { select(voice) }
                    )
                }
            }
            .padding(6)
        }
        .scrollIndicators(.visible)
        .frame(width: 360, height: listHeight)
        .onDisappear {
            previewPlayer.stop()
        }
    }

    private func select(_ voice: TTSVoice) {
        previewPlayer.stop()
        viewModel.selectedVoice = voice
        isPresented = false
    }
}

private struct VoiceOptionRow: View {
    let voice: TTSVoice
    let isSelected: Bool
    @ObservedObject var previewPlayer: VoicePreviewPlayer
    let previewConfiguration: VoicePreviewConfiguration
    let onSelect: () -> Void
    @State private var isHovered = false
    @State private var isPreviewButtonHovered = false

    private var isPreviewActive: Bool {
        previewPlayer.activeVoiceID == voice.id
    }

    private var isPreviewPlaying: Bool {
        isPreviewActive && previewPlayer.isPlaying
    }

    private var previewError: String? {
        guard previewPlayer.errorVoiceID == voice.id else { return nil }
        return previewPlayer.errorMessage
    }

    private var previewHint: String {
        previewConfiguration.requiresExplicitStart(for: voice)
            ? "Click to preview \(voice.name) — this synthesizes a short sample and uses credits"
            : "Hover to preview \(voice.name)"
    }

    private var previewIconStyle: AnyShapeStyle {
        if previewError != nil {
            return AnyShapeStyle(.red)
        }
        return isPreviewActive || isPreviewButtonHovered
            ? AnyShapeStyle(.primary)
            : AnyShapeStyle(.secondary)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    Text(voice.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                previewPlayer.togglePreview(
                    for: voice,
                    configuration: previewConfiguration
                )
            } label: {
                AnimatedWaveformIcon(isAnimating: isPreviewPlaying)
                    .foregroundStyle(previewIconStyle)
                    .frame(width: 26, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering in
                isPreviewButtonHovered = isHovering
                if isHovering {
                    previewPlayer.beginPreview(
                        for: voice,
                        configuration: previewConfiguration
                    )
                } else {
                    previewPlayer.endPreview(for: voice.id)
                    previewPlayer.clearError(for: voice.id)
                }
            }
            .help(previewError ?? previewHint)
            .accessibilityLabel("Preview \(voice.name)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(height: 34)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.07) : .clear)
        }
        .onHover { isHovered = $0 }
    }
}

private struct AnimatedWaveformIcon: View {
    let isAnimating: Bool
    private let restingHeights: [CGFloat] = [6, 11, 16, 11, 6]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: isAnimating == false)) { timeline in
            HStack(spacing: 2) {
                ForEach(restingHeights.indices, id: \.self) { index in
                    Capsule()
                        .frame(width: 1.5, height: barHeight(at: index, date: timeline.date))
                }
            }
            .frame(width: 20, height: 18)
        }
    }

    private func barHeight(at index: Int, date: Date) -> CGFloat {
        guard isAnimating else { return restingHeights[index] }
        let time = date.timeIntervalSinceReferenceDate
        let wave = abs(sin(time * 7 + Double(index) * 0.9))
        return 5 + CGFloat(wave) * 12
    }
}
