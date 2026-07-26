import Foundation
import SwiftData

extension SpeechViewModel {
    func download(modelContext: ModelContext) async {
        // Cached audio is exportable even when a fresh synthesis would be refused — writing a
        // file the app already holds costs no credits and issues no request. Play has always
        // allowed this; download rejected it, so an exhausted quota greyed out the export of
        // audio sitting right there in the cache. Mirrors the guard in play().
        guard canGenerate || hasCachedSpeechForCurrentRequest else {
            updateStatus(validationMessage(), tone: .error)
            return
        }

        do {
            let includesSubtitles = downloadIncludesSubtitles
            let speech = try await currentSpeech(
                refreshQuotaOnCacheHit: true,
                requireAlignment: includesSubtitles
                    && activeProvider.capabilities.providesCharacterAlignment
            )
            let subtitle: String?
            if includesSubtitles {
                if let alignment = speech.alignment, alignment.isValid {
                    subtitle = try SubtitleFormatter.srt(from: alignment)
                } else {
                    let duration = playback.duration > 0
                        ? playback.duration
                        : try playback.measuredDuration(data: speech.audioData)
                    subtitle = try SubtitleFormatter.estimatedSRT(
                        text: speech.request.text,
                        duration: duration
                    )
                }
            } else {
                subtitle = nil
            }
            let result = try await exportStore.export(
                speech: speech,
                subtitle: subtitle,
                to: settings.downloadDirectoryURL
            )
            downloadFeedback = DownloadFeedback(
                audioURL: result.audioURL,
                subtitleURL: result.subtitleURL
            )
            if let subtitleDestination = result.subtitleURL {
                updateStatus(
                    L10n.format(
                        "status.saved-audio-subtitle",
                        defaultValue: "Saved %1$@ and %2$@.",
                        result.audioURL.lastPathComponent,
                        subtitleDestination.lastPathComponent
                    ),
                    tone: .success
                )
            } else {
                updateStatus(
                    L10n.format(
                        "status.saved-audio",
                        defaultValue: "Saved %@.",
                        result.audioURL.lastPathComponent
                    ),
                    tone: .success
                )
            }
            recordHistory(
                speech: speech,
                duration: playback.duration > 0 ? playback.duration : nil,
                modelContext: modelContext
            )
        } catch {
            reportGenerationFailure(error)
        }
    }
}
