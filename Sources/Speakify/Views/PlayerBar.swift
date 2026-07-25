import SwiftData
import SwiftUI

struct PlayerBar: View {
    @Environment(\.modelContext) private var modelContext
    let settings: AppSettings
    let viewModel: SpeechViewModel
    let playback: PlaybackStore
    @State private var playFeedback = 0
    @State private var downloadFeedback = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric private var timeWidth: CGFloat = 92
    @ScaledMetric private var audioStatusHeight: CGFloat = 38

    private var playButtonSymbol: String {
        if viewModel.isGenerating {
            return "stop.fill"
        }
        return playback.isPlaying ? "pause.fill" : "play.fill"
    }

    private var downloadContentsDescription: String {
        let capabilities = viewModel.activeProvider.capabilities
        guard capabilities.providesSubtitles else {
            return L10n.string("Audio", defaultValue: "Audio")
        }
        return capabilities.providesCharacterAlignment
            ? L10n.string("Audio + SRT subtitle", defaultValue: "Audio + SRT subtitle")
            : L10n.string(
                "Audio + estimated SRT subtitle",
                defaultValue: "Audio + estimated SRT subtitle"
            )
    }

    var body: some View {
        HStack(spacing: 16) {
            AudioStatusView(
                isActive: playback.isPlaying || viewModel.isGenerating,
                playback: playback
            )
                .frame(height: audioStatusHeight)

            Text(viewModel.isGenerating ? "Generating" : playback.timeText)
                .font(.title3)
                .foregroundStyle(.primary)
                .monospacedDigit()
                .frame(width: timeWidth, alignment: .trailing)

            PlaybackRateControl(settings: settings)

            playButton

            downloadButton
        }
        .padding(.horizontal, 20)
        .task(id: playback.isPlaying) {
            while playback.isPlaying, Task.isCancelled == false {
                try? await Task.sleep(for: .milliseconds(100))
                guard Task.isCancelled == false else { return }
                viewModel.refreshPlaybackProgress()
            }
        }
        .onChange(of: viewModel.downloadFeedback?.id) { _, newValue in
            guard newValue != nil else { return }
            downloadFeedback += 1
        }
    }

    private var playButton: some View {
        Button {
            playFeedback += 1
            Task { await viewModel.togglePlayPause(modelContext: modelContext) }
        } label: {
            Image(systemName: playButtonSymbol)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: reduceMotion ? 0 : playFeedback)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .disabled(
                viewModel.canGenerate == false
                && playback.isPlaying == false
                && viewModel.isGenerating == false
        )
        .help(viewModel.isGenerating ? Text("Cancel generation") : Text("Play"))
        .accessibilityLabel(
            viewModel.isGenerating
                ? Text("Cancel generation")
                : (playback.isPlaying ? Text("Pause") : Text("Play"))
        )
    }

    private var downloadButton: some View {
        Button {
            downloadFeedback += 1
            Task { await viewModel.download(modelContext: modelContext) }
        } label: {
            Image(systemName: "arrow.down")
                .symbolEffect(.bounce, value: reduceMotion ? 0 : downloadFeedback)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .disabled(viewModel.canGenerate == false)
        .help(downloadHelp)
        .accessibilityLabel(Text("Export audio"))
    }

    private var downloadHelp: String {
        [
            L10n.string("Export audio", defaultValue: "Export audio"),
            downloadContentsDescription,
            settings.downloadDirectoryPath
        ].joined(separator: "\n")
    }
}

private struct AudioStatusView: View {
    let isActive: Bool
    let playback: PlaybackStore
    @State private var scrubTime: TimeInterval?
    @ScaledMetric private var minimumSliderWidth: CGFloat = 90

    private var position: Binding<Double> {
        Binding(
            get: { scrubTime ?? playback.currentTime },
            set: { scrubTime = $0 }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            AnimatedWaveformIcon(isAnimating: isActive)
                .foregroundStyle(.primary)
                .accessibilityHidden(true)

            Slider(
                value: position,
                in: 0...max(playback.duration, 0.01)
            ) { isEditing in
                if isEditing == false, let scrubTime {
                    playback.seek(to: scrubTime)
                    self.scrubTime = nil
                }
            }
            .controlSize(.small)
            .frame(minWidth: minimumSliderWidth)
            .disabled(playback.canSeek == false)
            .accessibilityLabel(Text("Playback position"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PlaybackRateControl: View {
    @Bindable var settings: AppSettings
    @State private var showsPopover = false
    @ScaledMetric private var labelWidth: CGFloat = 40
    @ScaledMetric private var popoverWidth: CGFloat = 260

    private static let range: ClosedRange<Double> = 0.25...2

    var body: some View {
        Button {
            showsPopover.toggle()
        } label: {
            Text(verbatim: Self.label(for: settings.playbackRate))
                .monospacedDigit()
                .frame(width: labelWidth)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .help(Text("Playback speed"))
        .accessibilityLabel(Text("Playback speed"))
        .popover(isPresented: $showsPopover, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Playback speed")
                    Spacer(minLength: 12)
                    Text(verbatim: Self.label(for: settings.playbackRate))
                        .monospacedDigit()
                }
                .font(.headline)

                Slider(
                    value: $settings.playbackRate,
                    in: Self.range,
                    step: 0.25
                ) {
                    Text("Playback speed")
                } minimumValueLabel: {
                    Text(verbatim: Self.label(for: Self.range.lowerBound))
                } maximumValueLabel: {
                    Text(verbatim: Self.label(for: Self.range.upperBound))
                } tick: { value in
                    SliderTick(value)
                }
                .labelsHidden()
                .font(.caption)
            }
            .padding(16)
            .frame(width: popoverWidth)
        }
    }

    static func label(for rate: Double) -> String {
        rate.formatted(
            .number.precision(.fractionLength(0...2)).locale(L10n.locale)
        ) + "\u{00D7}"
    }
}
