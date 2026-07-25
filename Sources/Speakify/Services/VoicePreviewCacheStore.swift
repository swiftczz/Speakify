import CryptoKit
import Foundation

struct CachedVoicePreview: Sendable {
    let data: Data
    let fileExtension: String
}

actor VoicePreviewCacheStore {
    private let retention: TimeInterval
    private let sizeLimit: Int
    private let fileManager: FileManager
    private let overrideDirectoryURL: URL?
    private var resolvedDirectoryURL: URL?

    private var directoryURL: URL {
        if let resolvedDirectoryURL {
            return resolvedDirectoryURL
        }
        let url = overrideDirectoryURL
            ?? AppDataLocation.voicePreviewCacheDirectoryURL(fileManager: fileManager)
        resolvedDirectoryURL = url
        return url
    }

    init(
        retention: TimeInterval = 30 * 24 * 60 * 60,
        sizeLimit: Int = 40 * 1_024 * 1_024,
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.retention = retention
        self.sizeLimit = sizeLimit
        self.overrideDirectoryURL = directoryURL
        self.fileManager = fileManager
    }

    func preview(for key: String) -> CachedVoicePreview? {
        for fileExtension in ["mp3", "wav"] {
            let url = fileURL(key: key, fileExtension: fileExtension)
            guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
                continue
            }
            if isExpired(url) {
                try? fileManager.removeItem(at: url)
                return nil
            }
            guard let data = try? Data(contentsOf: url), data.isEmpty == false else {
                return nil
            }
            return CachedVoicePreview(data: data, fileExtension: fileExtension)
        }
        return nil
    }

    func store(_ preview: CachedVoicePreview, for key: String) {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try preview.data.write(
                to: fileURL(key: key, fileExtension: preview.fileExtension),
                options: .atomic
            )
            prune()
        } catch {
        }
    }

    func prune() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let evicted = AudioCachePruner.entriesToEvict(
            from: AudioCachePruner.entries(from: files, fileManager: fileManager),
            now: .now,
            retention: retention,
            sizeLimit: sizeLimit
        )
        for entry in evicted {
            entry.urls.forEach { try? fileManager.removeItem(at: $0) }
        }
    }

    static func cacheKey(
        providerID: String,
        modelID: String,
        credentialFingerprint: String,
        voiceID: String
    ) -> String {
        let source = [providerID, modelID, credentialFingerprint, voiceID]
            .joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(source.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func fileURL(key: String, fileExtension: String) -> URL {
        directoryURL.appending(path: "\(key).\(fileExtension)")
    }

    private func isExpired(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
              let modifiedAt = values.contentModificationDate else {
            return false
        }
        return Date().timeIntervalSince(modifiedAt) > retention
    }
}
