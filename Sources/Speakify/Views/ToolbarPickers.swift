import SwiftUI

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
        .frame(minWidth: 150, idealWidth: 200, maxWidth: 228)
        .help(Text("Speech service and model"))
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

struct VoiceToolbarPicker: View {
    let viewModel: SpeechViewModel
    @State private var previewPlayer = VoicePreviewPlayer()
    @State private var isPresented = false
    @ScaledMetric private var labelWidth: CGFloat = 138

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(viewModel.selectedVoice?.name ?? "Select Voice")
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: labelWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .helpIfPresent(voiceHelp)
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

    private var voiceHelp: String? {
        guard let voice = viewModel.selectedVoice else {
            return L10n.string("Select a voice", defaultValue: "Select a voice")
        }
        return voice.displayName == voice.name ? nil : voice.displayName
    }
}

private extension View {
    @ViewBuilder
    func helpIfPresent(_ text: String?) -> some View {
        if let text {
            help(text)
        } else {
            self
        }
    }
}

private struct VoiceSelectionPopover: View {
    @Bindable var viewModel: SpeechViewModel
    let previewPlayer: VoicePreviewPlayer
    @Binding var isPresented: Bool
    @ScaledMetric private var width: CGFloat = 360
    @ScaledMetric private var height: CGFloat = 360

    private var previewConfiguration: VoicePreviewConfiguration {
        VoicePreviewConfiguration(
            provider: viewModel.activeProvider,
            modelID: viewModel.settings.modelID,
            apiKey: viewModel.settings.apiKey
        )
    }

    private var selection: Binding<TTSVoice.ID?> {
        Binding {
            viewModel.selectedVoice?.id
        } set: { newValue in
            guard let voice = voice(withID: newValue) else { return }
            previewPlayer.stop()
            viewModel.selectedVoice = voice
        }
    }

    var body: some View {
        List(selection: selection) {
            if viewModel.publicVoices.isEmpty == false {
                Section {
                    ForEach(viewModel.publicVoices) { voice in
                        row(for: voice)
                    }
                } header: {
                    Text("Voices")
                }
            }

            if viewModel.accountVoices.isEmpty == false {
                Section {
                    ForEach(viewModel.accountVoices) { voice in
                        row(for: voice)
                    }
                } header: {
                    Text("My Voices")
                }
            }
        }
        .listStyle(.sidebar)
        .frame(width: width, height: height)
        .onKeyPress(.return) {
            isPresented = false
            return .handled
        }
        .onDisappear {
            previewPlayer.stop()
        }
    }

    private func row(for voice: TTSVoice) -> some View {
        VoiceOptionRow(
            voice: voice,
            previewPlayer: previewPlayer,
            previewConfiguration: previewConfiguration,
            onCommit: { commit(voice) }
        )
            .tag(voice.id)
    }

    private func commit(_ voice: TTSVoice) {
        previewPlayer.stop()
        viewModel.selectedVoice = voice
        isPresented = false
    }

    private func voice(withID id: TTSVoice.ID?) -> TTSVoice? {
        guard let id else { return nil }
        return viewModel.publicVoices.first { $0.id == id }
            ?? viewModel.accountVoices.first { $0.id == id }
    }
}

private struct VoiceOptionRow: View {
    let voice: TTSVoice
    let previewPlayer: VoicePreviewPlayer
    let previewConfiguration: VoicePreviewConfiguration
    let onCommit: () -> Void
    @State private var previewState = VoicePreviewRowState()
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
                defaultValue: "Add this provider\u{2019}s API key in Settings to preview voices"
            )
        }
        return previewConfiguration.requiresExplicitStart(for: voice)
            ? L10n.format(
                "preview.click-metered",
                defaultValue: "Click to preview %@ \u{2014} this synthesizes a short sample and uses credits",
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
            Button(action: onCommit) {
                Text(voice.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            previewButton
        }
    }

    private var previewButton: some View {
        Button {
            previewPlayer.togglePreview(
                for: voice,
                configuration: previewConfiguration,
                state: previewState
            )
        } label: {
            AnimatedWaveformIcon(isAnimating: isPreviewPlaying)
                .foregroundStyle(previewIconStyle)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
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
        .help(Text("Voice settings"))
        .accessibilityLabel("Voice settings")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VoiceSettingsPopover(viewModel: viewModel)
        }
    }
}

private struct VoiceSettingsPopover: View {
    @Bindable var viewModel: SpeechViewModel
    @ScaledMetric private var width: CGFloat = 340

    private var capabilities: TTSVoiceSettingsCapabilities? {
        viewModel.voiceSettingsCapabilities
    }

    var body: some View {
        Form {
            if let capabilities {
                Section {
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
                        Toggle("Speaker Boost", isOn: binding(\.speakerBoost))
                    }
                } header: {
                    Text("Voice Settings")
                }

                Section {
                    Button("Reset Voice Settings") {
                        viewModel.voiceSettings = VoiceSettings()
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: width)
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
        LabeledContent {
            HStack(spacing: 8) {
                Slider(value: $value, in: range)

                Text(value, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text(title)
        }
    }
}
