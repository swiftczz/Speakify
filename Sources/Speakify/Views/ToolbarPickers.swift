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

/// The toolbar's voice button and the popover it opens.
struct VoiceToolbarPicker: View {
    let viewModel: SpeechViewModel
    @State private var previewPlayer = VoicePreviewPlayer()
    @State private var isPresented = false
    @ScaledMetric private var labelWidth: CGFloat = 138

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            // No `Spacer` here. As its own toolbar item this label is measured on its
            // own, and a greedy spacer made it report an unbounded width — which the
            // toolbar reads as a flexible gap rather than a control, and drops. Pushing
            // the chevron over with a `maxWidth` on the title keeps the same layout
            // while the label still measures to a definite 138.
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
    @ScaledMetric private var width: CGFloat = 360
    @ScaledMetric private var height: CGFloat = 360

    private var previewConfiguration: VoicePreviewConfiguration {
        VoicePreviewConfiguration(
            provider: viewModel.activeProvider,
            modelID: viewModel.settings.modelID,
            apiKey: viewModel.settings.apiKey
        )
    }

    /// Drives the list's highlight and the live choice together, so arrowing down the
    /// list changes the voice as it goes. That is what selection means in a macOS
    /// list, and it is what the old stack of rows had no way to express: the highlight
    /// was a hand-drawn rounded rectangle and the choice only moved on a click.
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
        // `.sidebar`, not `.inset`. An inset list draws the selection as a square,
        // edge-to-edge blue bar with a hairline under every row — the list look from
        // before Big Sur. The sidebar style is what macOS 26 uses for a chooser like
        // this: an inset highlight with the container's own corner radius, and no
        // per-row rules.
        .listStyle(.sidebar)
        // A fixed height, not `rowCount * 36 + 12`. That arithmetic hardcoded the row
        // height, so the popover measured itself wrongly the moment the system text
        // size moved off its default. A container the list scrolls inside makes no
        // assumption about how tall a row turns out to be.
        .frame(width: width, height: height)
        // Return commits the highlighted voice, which selection has already applied.
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
        // No selection checkmark, no hand-drawn hover fill and no fixed row height.
        // The list draws all three, and unlike the hand-drawn versions its highlight
        // follows the window's focus state.
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

    /// Hover to preview, and click to preview too.
    ///
    /// Hovering the waveform starts the sample; leaving stops it. `beginPreview`
    /// refuses metered voices on its own, so for those the hover does nothing and the
    /// click is the way in — which is why the help tag differs between them.
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

private struct AnimatedWaveformIcon: View {
    let isAnimating: Bool
    /// Stops the bars moving, and stops the timeline waking the view 24 times a
    /// second, when the user has asked for less motion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric private var scale: CGFloat = 1
    private let restingHeights: [CGFloat] = [6, 11, 16, 11, 6]

    private var isMoving: Bool {
        isAnimating && reduceMotion == false
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: isMoving == false)) { timeline in
            HStack(spacing: 2 * scale) {
                ForEach(restingHeights.indices, id: \.self) { index in
                    Capsule()
                        .frame(
                            width: 1.5 * scale,
                            height: barHeight(at: index, date: timeline.date) * scale
                        )
                }
            }
            .frame(width: 20 * scale, height: 18 * scale)
        }
    }

    private func barHeight(at index: Int, date: Date) -> CGFloat {
        guard isMoving else { return restingHeights[index] }
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
        // A `Form`, not a hand-stacked `VStack`.
        //
        // The rows disagreed with each other before: "Generation Speed" used
        // `LabeledContent` when the model did not support it, and every other row was a
        // hand-built `HStack` with its own `Spacer`. So the labels did not share a
        // column, and switching to a model without speed control made the layout jump.
        // A form aligns the label column, spaces the rows and reflows them with the
        // text size, none of which the stack was doing.
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

                // Its own section rather than the `Divider()` that used to be drawn in
                // by hand — the form draws the boundary.
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
        // `LabeledContent` so the title sits in the form's label column with every
        // other row, instead of being pushed over by a `Spacer` of its own.
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
