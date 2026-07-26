import Foundation

actor SpeechCacheStore {
    private let retention: TimeInterval
    private let sizeLimit: Int
    private let fileManager: FileManager
    private let overrideDirectoryURL: URL?
    private var resolvedDirectoryURL: URL?

    private var directoryURL: URL {
        if let resolvedDirectoryURL {
            return resolvedDirectoryURL
        }
        let url = overrideDirectoryURL ?? AppDataLocation.audioCacheDirectoryURL(fileManager: fileManager)
        resolvedDirectoryURL = url
        return url
    }

    init(
        retention: TimeInterval,
        sizeLimit: Int,
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.retention = retention
        self.sizeLimit = sizeLimit
        self.overrideDirectoryURL = directoryURL
        self.fileManager = fileManager
    }

    func speech(for request: SpeechRequest, key: String) -> GeneratedSpeech? {
        let audioURL = audioURL(for: request, key: key)
        guard fileManager.fileExists(atPath: audioURL.path(percentEncoded: false)) else { return nil }

        if isExpired(audioURL) {
            try? fileManager.removeItem(at: audioURL)
            try? fileManager.removeItem(at: alignmentURL(for: key))
            return nil
        }

        guard let audioData = try? Data(contentsOf: audioURL), audioData.isEmpty == false else {
            return nil
        }

        return GeneratedSpeech(
            audioData: audioData,
            fileExtension: Self.fileExtension(for: request.outputFormat),
            request: request,
            alignment: alignment(for: key)
        )
    }

    func containsSpeech(for request: SpeechRequest, key: String) -> Bool {
        let audioURL = audioURL(for: request, key: key)
        guard fileManager.fileExists(atPath: audioURL.path(percentEncoded: false)) else {
            return false
        }

        if isExpired(audioURL) {
            try? fileManager.removeItem(at: audioURL)
            try? fileManager.removeItem(at: alignmentURL(for: key))
            return false
        }

        guard let values = try? audioURL.resourceValues(forKeys: [.fileSizeKey]) else {
            return false
        }
        return (values.fileSize ?? 0) > 0
    }

    func store(_ speech: GeneratedSpeech, key: String) {
        let audioURL = directoryURL.appending(path: "\(key).\(speech.fileExtension)")
        do {
            try speech.audioData.write(to: audioURL, options: .atomic)
            if let alignment = speech.alignment {
                let data = try JSONEncoder().encode(alignment)
                try data.write(to: alignmentURL(for: key), options: .atomic)
            }
            prune()
        } catch {
        }
    }

    func prune() {
        guard let cachedFiles = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let evicted = AudioCachePruner.entriesToEvict(
            from: AudioCachePruner.entries(from: cachedFiles, fileManager: fileManager),
            now: .now,
            retention: retention,
            sizeLimit: sizeLimit
        )

        for entry in evicted {
            entry.urls.forEach { try? fileManager.removeItem(at: $0) }
        }
    }

    private func alignmentURL(for key: String) -> URL {
        directoryURL.appending(path: "\(key).alignment.json")
    }

    private func audioURL(for request: SpeechRequest, key: String) -> URL {
        let fileExtension = Self.fileExtension(for: request.outputFormat)
        return directoryURL.appending(path: "\(key).\(fileExtension)")
    }

    private func alignment(for key: String) -> SpeechAlignment? {
        guard let data = try? Data(contentsOf: alignmentURL(for: key)),
              let alignment = try? JSONDecoder().decode(SpeechAlignment.self, from: data),
              alignment.isValid else {
            return nil
        }
        return alignment
    }

    private func isExpired(_ fileURL: URL) -> Bool {
        guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
              let modifiedAt = values.contentModificationDate else {
            return false
        }
        return Date().timeIntervalSince(modifiedAt) > retention
    }

    static func fileExtension(for outputFormat: String) -> String {
        outputFormat.hasPrefix("wav") ? "wav" : "mp3"
    }
}
