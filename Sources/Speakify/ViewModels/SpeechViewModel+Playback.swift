import Foundation
import SwiftData

extension SpeechViewModel {
    func play(modelContext: ModelContext) async {
        nowPlayingModelContext = modelContext
        guard canGenerate || hasCachedSpeechForCurrentRequest else {
            updateStatus(validationMessage(), tone: .error)
            return
        }

        do {
            let speech = try await currentSpeech(refreshQuotaOnCacheHit: true)
            let duration = try playback.play(
                data: speech.audioData,
                rate: settings.playbackRate,
                fileExtension: speech.fileExtension
            )
            publishNowPlaying(for: speech, duration: duration)
            updateStatus(
                L10n.format(
                    "status.playing",
                    defaultValue: "Playing %@.",
                    speech.request.voice.displayName
                ),
                tone: .success
            )
            try? historyStore.record(
                speech: speech,
                providerID: settings.providerID,
                apiKey: settings.apiKey,
                duration: duration,
                modelContext: modelContext
            )
        } catch {
            playback.stop()
            guard Self.isCancellation(error) == false else { return }
            removeSelectedVoiceIfUnavailable(error)
            updateStatus(error.localizedDescription, tone: .error)
        }
    }

    func cancelGeneration() {
        guard isGenerating else { return }
        synthesisTask?.cancel()
        synthesisTask = nil
        generationToken += 1
        isGenerating = false
        updateStatus(
            L10n.string("status.generation-cancelled", defaultValue: "Generation cancelled."),
            tone: .info
        )
    }

    func refreshPlaybackProgress() {
        if playback.refresh() {
            nowPlaying.clear()
            finishPlayback()
        } else {
            nowPlaying.updateElapsed(playback.currentTime)
        }
    }

    func stop() {
        playback.stop()
        nowPlaying.clear()
        updateStatus(
            L10n.string("status.playback-stopped", defaultValue: "Playback stopped."),
            tone: .info
        )
    }

    func pause() {
        guard playback.isPlaying else { return }
        playback.pause()
        nowPlaying.updateElapsed(playback.currentTime)
        updateStatus(
            L10n.string("status.playback-paused", defaultValue: "Playback paused."),
            tone: .info
        )
    }

    func resume() {
        guard playback.isPaused else { return }
        playback.resume()
        nowPlaying.updateElapsed(playback.currentTime)
        if let voice = selectedVoice {
            updateStatus(
                L10n.format("status.playing", defaultValue: "Playing %@.", voice.displayName),
                tone: .info
            )
        }
    }

    func togglePlayPause(modelContext: ModelContext) async {
        if isGenerating {
            cancelGeneration()
        } else if playback.isPlaying {
            pause()
        } else if playback.isPaused {
            resume()
        } else {
            await play(modelContext: modelContext)
        }
    }

    private func publishNowPlaying(for speech: GeneratedSpeech, duration: TimeInterval) {
        nowPlaying.configure(
            onPlay: { [weak self] in
                guard let self else { return }
                if self.playback.isPaused {
                    self.resume()
                } else if let modelContext = self.nowPlayingModelContext {
                    Task { await self.play(modelContext: modelContext) }
                }
            },
            onStop: { [weak self] in self?.pause() }
        )
        nowPlaying.update(
            title: NowPlayingController.title(for: speech.request.text),
            voiceName: speech.request.voice.displayName,
            duration: duration,
            elapsed: 0,
            rate: settings.playbackRate
        )
    }

    private func finishPlayback() {
        updateStatus(
            L10n.string("status.playback-finished", defaultValue: "Playback finished."),
            tone: .success
        )
    }
}
