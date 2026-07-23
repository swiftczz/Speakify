import Foundation

struct SpeechExportResult: Sendable {
    let audioURL: URL
    let subtitleURL: URL?
}

/// Serializes export naming and file I/O away from the main actor.
actor SpeechExportStore {
    func export(
        speech: GeneratedSpeech,
        subtitle: String?,
        to directory: URL
    ) throws -> SpeechExportResult {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileName = FileNameFormatter.speechFileName(
            text: speech.request.text,
            voiceName: speech.request.voice.name,
            fileExtension: speech.fileExtension
        )
        let audioURL = FileNameFormatter.availableURL(
            in: directory,
            fileName: fileName,
            companionExtension: subtitle == nil ? nil : "srt"
        )
        let subtitleURL = subtitle == nil
            ? nil
            : audioURL.deletingPathExtension().appendingPathExtension("srt")

        do {
            try speech.audioData.write(to: audioURL, options: .atomic)
            if let subtitle, let subtitleURL {
                try subtitle.write(to: subtitleURL, atomically: true, encoding: .utf8)
            }
        } catch {
            try? fileManager.removeItem(at: audioURL)
            if let subtitleURL {
                try? fileManager.removeItem(at: subtitleURL)
            }
            throw error
        }

        return SpeechExportResult(audioURL: audioURL, subtitleURL: subtitleURL)
    }
}
