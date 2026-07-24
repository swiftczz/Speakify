import CryptoKit
import Foundation

/// Keeps the last successful provider catalog available across launches. Account
/// keys are represented only by a SHA-256 scope and never written to the cache.
actor VoiceCatalogCacheStore {
    private struct Record: Codable {
        let publicVoices: [TTSVoice]
        let accountVoices: [TTSVoice]
        let savedAt: Date
    }

    private let retention: TimeInterval
    private let fileManager: FileManager
    private let overrideDirectoryURL: URL?
    private var resolvedDirectoryURL: URL?

    private var directoryURL: URL {
        if let resolvedDirectoryURL {
            return resolvedDirectoryURL
        }
        let url = overrideDirectoryURL
            ?? AppDataLocation.voiceCatalogCacheDirectoryURL(fileManager: fileManager)
        resolvedDirectoryURL = url
        return url
    }

    init(
        retention: TimeInterval = 14 * 24 * 60 * 60,
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.retention = retention
        self.overrideDirectoryURL = directoryURL
        self.fileManager = fileManager
    }

    func catalog(providerID: String, apiKey: String) -> TTSVoiceCatalog? {
        let url = recordURL(providerID: providerID, apiKey: apiKey)
        guard let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(Record.self, from: data) else {
            return nil
        }
        guard Date().timeIntervalSince(record.savedAt) <= retention else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        return TTSVoiceCatalog(
            publicVoices: record.publicVoices,
            accountVoices: record.accountVoices
        )
    }

    func store(_ catalog: TTSVoiceCatalog, providerID: String, apiKey: String) {
        guard catalog.accountFailure == nil else { return }
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let record = Record(
                publicVoices: catalog.publicVoices,
                accountVoices: catalog.accountVoices,
                savedAt: .now
            )
            let data = try JSONEncoder().encode(record)
            try data.write(
                to: recordURL(providerID: providerID, apiKey: apiKey),
                options: .atomic
            )
        } catch {
            // Catalog caching is a launch/offline optimization; a write failure
            // must never make a successfully loaded provider unusable.
        }
    }

    private func recordURL(providerID: String, apiKey: String) -> URL {
        let scope = CredentialScope.identifier(providerID: providerID, apiKey: apiKey)
        let digest = SHA256.hash(data: Data(scope.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directoryURL.appending(path: "\(digest).json")
    }
}
