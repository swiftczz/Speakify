import SwiftData
import SwiftUI

/// The transport bar: progress, elapsed time, speed, play/cancel and download.
struct PlayerBar: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var settings: AppSettings
    @ObservedObject var viewModel: SpeechViewModel
    @ObservedObject var playback: PlaybackStore
    @State private var isAnimatingPlayButton = false
    @State private var isAnimatingDownloadButton = false
    @State private var isHoveringDownloadButton = false
    @State private var downloadCompletionProgress: CGFloat = 0
    @State private var downloadCompletionOpacity = 0.0
    @State private var showsDownloadCompletionRing = false
    @State private var dismissDownloadCompletionTask: Task<Void, Never>?

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
                progress: playback.progress
            )
                .frame(height: 38)

            Text(viewModel.isGenerating ? "Generating" : playback.timeText)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(AppPalette.ink)
                .monospacedDigit()
                .frame(width: 92, alignment: .trailing)

            PlaybackRateControl(settings: settings)

            playButton

            downloadButton
        }
        .padding(.horizontal, 14)
        .background(AppPalette.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 1)
        .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 0)
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
            playDownloadCompletionRing()
        }
    }

    private var playButton: some View {
        Button {
            flashPlayButton()

            if viewModel.isGenerating {
                viewModel.cancelGeneration()
            } else if playback.isPlaying {
                viewModel.stop()
            } else {
                Task { await viewModel.play(modelContext: modelContext) }
            }
        } label: {
            Image(systemName: playButtonSymbol)
                .font(.system(size: 24, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isAnimatingPlayButton ? AppPalette.accent : AppPalette.ink)
                .frame(width: 28, height: 28)
                .shadow(color: .black.opacity(0.10), radius: 5, x: 0, y: 2)
                .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 0)
                .scaleEffect(isAnimatingPlayButton ? 1.15 : 1)
        }
        .buttonStyle(.plain)
        .disabled(
                viewModel.canGenerate == false
                && playback.isPlaying == false
                && viewModel.isGenerating == false
        )
        .help(viewModel.isGenerating ? "Cancel generation" : "Play")
    }

    private var downloadButton: some View {
        Button {
            flashDownloadButton()
            Task { await viewModel.download(modelContext: modelContext) }
        } label: {
            ZStack {
                if showsDownloadCompletionRing {
                    Circle()
                        .trim(from: 0, to: downloadCompletionProgress)
                        .stroke(
                            AppPalette.accent,
                            style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
                        )
                        .frame(width: 34, height: 34)
                        .rotationEffect(.degrees(-90))
                        .opacity(downloadCompletionOpacity)
                }

                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 24, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(
                        viewModel.canGenerate
                            ? (isAnimatingDownloadButton ? AppPalette.accent : AppPalette.ink)
                            : AppPalette.ink.opacity(0.35)
                    )
                    .frame(width: 28, height: 28)
                    .shadow(color: .black.opacity(0.10), radius: 5, x: 0, y: 2)
                    .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 0)
                    .scaleEffect(isAnimatingDownloadButton ? 1.15 : 1)
            }
            .frame(width: 36, height: 36)
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
    }

    private var downloadDestinationTooltip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(downloadContentsLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppPalette.muted)

            Text(settings.downloadDirectoryPath)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppPalette.ink)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .fixedSize(horizontal: true, vertical: false)
        .background(AppPalette.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        .padding(.trailing, 10)
        .offset(y: -58)
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)))
        .allowsHitTesting(false)
    }

    private func flashPlayButton() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.55)) {
            isAnimatingPlayButton = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) {
                isAnimatingPlayButton = false
            }
        }
    }

    private func flashDownloadButton() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.55)) {
            isAnimatingDownloadButton = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) {
                isAnimatingDownloadButton = false
            }
        }
    }

    private func playDownloadCompletionRing() {
        dismissDownloadCompletionTask?.cancel()
        downloadCompletionProgress = 0
        downloadCompletionOpacity = 1
        showsDownloadCompletionRing = true

        withAnimation(.easeOut(duration: 0.55)) {
            downloadCompletionProgress = 1
        }

        dismissDownloadCompletionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(850))
            guard Task.isCancelled == false else { return }

            withAnimation(.easeOut(duration: 0.18)) {
                downloadCompletionOpacity = 0
            }

            try? await Task.sleep(for: .milliseconds(180))
            guard Task.isCancelled == false else { return }

            showsDownloadCompletionRing = false
            downloadCompletionProgress = 0
        }
    }
}

private struct AudioStatusView: View {
    let isActive: Bool
    let progress: Double

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isActive ? "waveform.circle.fill" : "waveform")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppPalette.ink)
                .symbolEffect(.pulse, isActive: isActive)

            ProgressView(value: progress)
                .tint(AppPalette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PlaybackRateControl: View {
    @ObservedObject var settings: AppSettings
    @State private var showsPopover = false

    var body: some View {
        Button {
            showsPopover.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "speedometer")
                    .font(.system(size: 12, weight: .semibold))
                Text(Self.label(for: settings.playbackRate))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(AppPalette.ink)
            .padding(.horizontal, 10)
            .frame(width: 76, height: 30)
            .background(AppPalette.controlBackground, in: Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsPopover, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Playback speed")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(Self.label(for: settings.playbackRate))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                }

                Slider(value: $settings.playbackRate, in: 0.25...2.0, step: 0.25)

                HStack {
                    Text("0.25x")
                    Spacer()
                    Text("2.0x")
                }
                .font(.system(size: 11, weight: .medium))
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
