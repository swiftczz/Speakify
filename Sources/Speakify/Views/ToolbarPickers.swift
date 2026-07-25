import SwiftUI

/// The toolbar's service + model picker. Service and model are chosen together so
/// one menu covers "which engine, which voice quality" in a single step.
struct ServiceModelToolbarPicker: View {
    let settings: AppSettings
    let viewModel: SpeechViewModel

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
        // Was a fixed 228. Together with the voice picker that overflowed the
        // centred toolbar region, and macOS silently dropped the item that no
        // longer fitted rather than shrinking anything.
        .frame(minWidth: 150, idealWidth: 200, maxWidth: 228)
        .help(
            L10n.string(
                "Speech service and model",
                defaultValue: "Speech service and model"
            )
        )
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
    let viewModel: SpeechViewModel
    @State private var previewPlayer = VoicePreviewPlayer()
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
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 96, idealWidth: 138, maxWidth: 138, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(
            viewModel.selectedVoice?.displayName
                ?? L10n.string("Select a voice", defaultValue: "Select a voice")
        )
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
    @Bindable var viewModel: SpeechViewModel
    let previewPlayer: VoicePreviewPlayer
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
    let previewPlayer: VoicePreviewPlayer
    let previewConfiguration: VoicePreviewConfiguration
    let onSelect: () -> Void
    @State private var previewState = VoicePreviewRowState()
    @State private var isHovered = false
    @State private var isPreviewButtonHovered = false

    private var isPreviewPlaying: Bool {
        previewState.isActive && previewState.isPlaying
    }

    private var previewError: String? {
        previewState.errorMessage
    }

    private var previewHint: String {
        guard previewConfiguration.canPreview(voice) else {
            return L10n.string(
                "preview.add-key",
                defaultValue: "Add this provider’s API key in Settings to preview voices"
            )
        }
        return previewConfiguration.requiresExplicitStart(for: voice)
            ? L10n.format(
                "preview.click-metered",
                defaultValue: "Click to preview %@ — this synthesizes a short sample and uses credits",
                voice.name
            )
            : L10n.format(
                "preview.hover",
                defaultValue: "Hover to preview %@",
                voice.name
            )
    }

    private var previewIconStyle: AnyShapeStyle {
        if previewError != nil {
            return AnyShapeStyle(.red)
        }
        return previewState.isActive || isPreviewButtonHovered
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
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                previewPlayer.togglePreview(
                    for: voice,
                    configuration: previewConfiguration,
                    state: previewState
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
                        configuration: previewConfiguration,
                        state: previewState
                    )
                } else {
                    previewPlayer.endPreview(for: voice.id)
                    previewPlayer.clearError(for: voice.id, state: previewState)
                }
            }
            .disabled(previewConfiguration.canPreview(voice) == false)
            .help(previewError ?? previewHint)
            .accessibilityLabel(
                L10n.format(
                    "preview.accessibility",
                    defaultValue: "Preview %@",
                    voice.name
                )
            )
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

struct VoiceSettingsToolbarButton: View {
    let viewModel: SpeechViewModel
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(L10n.string("Voice settings", defaultValue: "Voice settings"))
        .accessibilityLabel("Voice settings")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VoiceSettingsPopover(viewModel: viewModel)
        }
    }
}

private struct VoiceSettingsPopover: View {
    @Bindable var viewModel: SpeechViewModel

    private var capabilities: TTSVoiceSettingsCapabilities? {
        viewModel.voiceSettingsCapabilities
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Voice Settings")
                .font(.headline)

            if let capabilities {
                VoiceSettingSlider(
                    title: "Stability",
                    value: binding(\.stability),
                    range: capabilities.stabilityRange
                )
                VoiceSettingSlider(
                    title: "Similarity",
                    value: binding(\.similarityBoost),
                    range: capabilities.similarityRange
                )
                VoiceSettingSlider(
                    title: "Style",
                    value: binding(\.style),
                    range: capabilities.styleRange
                )

                if capabilities.supportsSpeed(modelID: viewModel.settings.modelID) {
                    VoiceSettingSlider(
                        title: "Generation Speed",
                        value: binding(\.speed),
                        range: capabilities.speedRange
                    )
                } else {
                    LabeledContent("Generation Speed") {
                        Text("Unavailable for this model")
                            .foregroundStyle(.secondary)
                    }
                }

                if capabilities.supportsSpeakerBoost {
                    Toggle(
                        "Speaker Boost",
                        isOn: binding(\.speakerBoost)
                    )
                }

                Divider()

                Button("Reset Voice Settings") {
                    viewModel.voiceSettings = VoiceSettings()
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(18)
        .frame(width: 320)
    }

    private func binding<Value>(
        _ keyPath: WritableKeyPath<VoiceSettings, Value>
    ) -> Binding<Value> {
        Binding {
            viewModel.voiceSettings[keyPath: keyPath]
        } set: { newValue in
            var settings = viewModel.voiceSettings
            settings[keyPath: keyPath] = newValue
            viewModel.voiceSettings = settings
        }
    }
}

private struct VoiceSettingSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                Spacer()
                Text(value, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}
