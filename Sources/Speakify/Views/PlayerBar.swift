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
    @State private var isHoveringDownloadButton = false
    /// Bumped on each press so the SF Symbol replays its bounce; the value itself
    /// is never read.
    @State private var playFeedback = 0
    @State private var downloadFeedback = 0

    private var playButtonSymbol: String {
        if viewModel.isGenerating {
            return "stop.circle.fill"
        }
        return playback.isPlaying ? "pause.circle.fill" : "play.circle.fill"
    }

    private var downloadContentsLabel: LocalizedStringKey {
        let capabilities = viewModel.activeProvider.capabilities
        guard capabilities.providesSubtitles else { return "Audio" }
        return capabilities.providesCharacterAlignment
            ? "Audio + SRT subtitle"
            : "Audio + estimated SRT subtitle"
    }

    var body: some View {
        HStack(spacing: 16) {
            AudioStatusView(
                isActive: playback.isPlaying || viewModel.isGenerating,
                playback: playback
            )
                .frame(height: 38)

            Text(viewModel.isGenerating ? "Generating" : playback.timeText)
                .font(.title3)
                .foregroundStyle(AppPalette.ink)
                .monospacedDigit()
                .frame(width: 92, alignment: .trailing)

            PlaybackRateControl(settings: settings)

            playButton

            downloadButton
        }
        .padding(.horizontal, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if isHoveringDownloadButton {
                downloadDestinationTooltip
            }
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
                .symbolEffect(.bounce, value: playFeedback)
                .foregroundStyle(AppPalette.ink)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(
                viewModel.canGenerate == false
                && playback.isPlaying == false
                && viewModel.isGenerating == false
        )
        .help(
            viewModel.isGenerating
                ? L10n.string("Cancel generation", defaultValue: "Cancel generation")
                : L10n.string("Play", defaultValue: "Play")
        )
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
                .symbolEffect(.bounce, value: downloadFeedback)
                .foregroundStyle(
                    viewModel.canGenerate ? AppPalette.ink : AppPalette.ink.opacity(0.35)
                )
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.canGenerate == false)
        .zIndex(isHoveringDownloadButton ? 1 : 0)
        .onHover { isHovering in
            withAnimation(.easeOut(duration: 0.16)) {
                isHoveringDownloadButton = isHovering
            }
        }
        .help(L10n.string("Export audio", defaultValue: "Export audio"))
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

    private var downloadDestinationTooltip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(downloadContentsLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppPalette.muted)

            Text(settings.downloadDirectoryPath)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppPalette.ink)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .fixedSize(horizontal: true, vertical: false)
        .glassEffect(.regular, in: .rect(cornerRadius: 12, style: .continuous))
        .padding(.trailing, 10)
        .offset(y: -58)
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)))
        .allowsHitTesting(false)
    }
}

/// The waveform badge plus a scrubbable position slider. `ProgressView` looked
/// right but could not be dragged, which made re-listening to a sentence — the
/// app's whole point — impossible.
private struct AudioStatusView: View {
    let isActive: Bool
    let playback: PlaybackStore
    @State private var scrubTime: TimeInterval?

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
                .foregroundStyle(AppPalette.ink)
                .symbolEffect(.pulse, isActive: isActive)

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
            .tint(AppPalette.ink)
            .frame(minWidth: 90)
            .disabled(playback.isPlaying == false)
            .accessibilityLabel(Text("Playback position"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PlaybackRateControl: View {
    @Bindable var settings: AppSettings
    @State private var showsPopover = false

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
            .frame(width: 76, height: 30)
        }
        .buttonStyle(.glass)
        .help(L10n.string("Playback speed", defaultValue: "Playback speed"))
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
                .foregroundStyle(AppPalette.muted)
            }
            .padding(16)
            .frame(width: 260)
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
