import AppKit
import SwiftData
import SwiftUI

/// The transport bar: progress, elapsed time, speed, play/cancel and download.
/// A floating cluster of controls rather than content, so it is the one surface
/// in the window that takes a Liquid Glass treatment.
struct PlayerBar: View {
    @Environment(\.modelContext) private var modelContext
    let settings: AppSettings
    let viewModel: SpeechViewModel
    let playback: PlaybackStore
    /// Bumped on each press so the SF Symbol replays its bounce; the value itself
    /// is never read.
    @State private var playFeedback = 0
    @State private var downloadFeedback = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric private var timeWidth: CGFloat = 92
    @ScaledMetric private var audioStatusHeight: CGFloat = 38
    @ScaledMetric private var transportButtonSize: CGFloat = 28

    private var playButtonSymbol: String {
        if viewModel.isGenerating {
            return "stop.circle.fill"
        }
        return playback.isPlaying ? "pause.circle.fill" : "play.circle.fill"
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
        // One glass surface for the whole transport, declared inside a container so
        // every glass element in this region samples the scene together rather than
        // each resolving on its own.
        //
        // The controls sitting on it are plain or bordered — never glass themselves.
        // The speed button used to be `.buttonStyle(.glass)`, which put glass directly
        // on glass: the two layers of refraction muddied whatever showed through and
        // left both sets of specular highlights competing.
        GlassEffectContainer(spacing: 16) {
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
            .padding(.horizontal, 14)
            .glassEffect(.regular, in: .rect(cornerRadius: 14, style: .continuous))
        }
        // Polls only while audio is actually playing; an always-on timer woke the
        // whole window ten times a second even when nothing was happening.
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

            if viewModel.isGenerating {
                viewModel.cancelGeneration()
            } else if playback.isPlaying {
                viewModel.stop()
            } else {
                Task { await viewModel.play(modelContext: modelContext) }
            }
        } label: {
            Image(systemName: playButtonSymbol)
                .font(.title)
                .symbolRenderingMode(.monochrome)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: reduceMotion ? 0 : playFeedback)
                .foregroundStyle(.primary)
                .frame(width: transportButtonSize, height: transportButtonSize)
        }
        .buttonStyle(.plain)
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
            Image(systemName: "arrow.down.circle.fill")
                .font(.title)
                .symbolRenderingMode(.monochrome)
                .symbolEffect(.bounce, value: reduceMotion ? 0 : downloadFeedback)
                // `.disabled` below already dims this. Painting the disabled state by
                // hand at 0.35 opacity both double-dimmed it and ignored whatever the
                // system does for disabled controls under Increase Contrast.
                .foregroundStyle(.primary)
                .frame(width: transportButtonSize, height: transportButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.canGenerate == false)
        .help(downloadHelp)
        .accessibilityLabel(Text("Export audio"))
        // Reveals what the last export actually produced. The URLs were already
        // being captured; until now nothing offered a way to reach them.
        .contextMenu {
            if let feedback = viewModel.downloadFeedback {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [feedback.audioURL, feedback.subtitleURL].compactMap { $0 }
                    )
                }
            }
        }
    }

    /// What the export will produce, and where it will land.
    ///
    /// A help tag rather than a hand-built overlay. This is hover information, which
    /// on macOS is exactly what a help tag is for — and the overlay it replaces was a
    /// second slab of glass floating over the first, positioned by a hardcoded
    /// `offset(y: -58)` that only lined up at one type size and one bar height.
    private var downloadHelp: String {
        [
            L10n.string("Export audio", defaultValue: "Export audio"),
            downloadContentsDescription,
            settings.downloadDirectoryPath
        ].joined(separator: "\n")
    }
}

/// The waveform badge plus a scrubbable position slider. `ProgressView` looked
/// right but could not be dragged, which made re-listening to a sentence — the
/// app's whole point — impossible.
private struct AudioStatusView: View {
    let isActive: Bool
    let playback: PlaybackStore
    @State private var scrubTime: TimeInterval?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric private var minimumSliderWidth: CGFloat = 90

    private var position: Binding<Double> {
        Binding(
            get: { scrubTime ?? playback.currentTime },
            set: { scrubTime = $0 }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isActive ? "waveform.circle.fill" : "waveform")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .symbolEffect(.pulse, isActive: isActive && reduceMotion == false)

            Slider(
                value: position,
                in: 0...max(playback.duration, 0.01)
            ) { isEditing in
                // Commit only when the drag ends, so the 10 Hz progress poll cannot
                // yank the knob out from under the pointer mid-scrub.
                if isEditing == false, let scrubTime {
                    playback.seek(to: scrubTime)
                    self.scrubTime = nil
                }
            }
            .controlSize(.small)
            // No `tint`. It was pinned to the label colour, which painted the filled
            // half of the track near-black and threw away whatever accent the user
            // picked in System Settings. A slider is one of the controls the accent
            // colour exists for.
            .frame(minWidth: minimumSliderWidth)
            .disabled(playback.isPlaying == false)
            .accessibilityLabel(Text("Playback position"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PlaybackRateControl: View {
    @Bindable var settings: AppSettings
    @State private var showsPopover = false
    @ScaledMetric private var labelWidth: CGFloat = 76
    @ScaledMetric private var popoverWidth: CGFloat = 260

    var body: some View {
        Button {
            showsPopover.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "speedometer")
                Text(Self.label(for: settings.playbackRate))
                    .monospacedDigit()
            }
            .font(.callout.weight(.semibold))
            .frame(width: labelWidth)
        }
        // Bordered, not `.glass`: this button sits on the transport bar's own glass,
        // and a second glass layer on top of the first is the one combination the
        // material is not meant to be used in.
        .buttonStyle(.bordered)
        .controlSize(.large)
        .help(Text("Playback speed"))
        .popover(isPresented: $showsPopover, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Playback speed")
                        .font(.headline)
                    Spacer()
                    Text(Self.label(for: settings.playbackRate))
                        .font(.headline)
                        .monospacedDigit()
                }

                Slider(value: $settings.playbackRate, in: 0.25...2.0, step: 0.25)

                HStack {
                    Text(verbatim: "0.25x")
                    Spacer()
                    Text(verbatim: "2.0x")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(width: popoverWidth)
        }
    }

    static func label(for rate: Double) -> String {
        let roundedRate = (rate * 100).rounded() / 100
        if roundedRate.rounded() == roundedRate {
            return String(format: "%.1fx", roundedRate)
        }
        if (roundedRate * 10).rounded() == roundedRate * 10 {
            return String(format: "%.1fx", roundedRate)
        }
        return String(format: "%.2fx", roundedRate)
    }
}
