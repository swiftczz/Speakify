import Foundation
import OSLog
import Synchronization

package enum AppDataLocation {
    private static let rootDirectoryName = ".speakify"
    private static let legacyDirectoryName = "com.local.Speakify"
    private static let historyStoreFileName = "History.store"
    private static let logger = Logger(subsystem: "Speakify", category: "LocalData")

    package static func prepare(fileManager: FileManager = .default) {
        let rootURL = rootDirectoryURL(fileManager: fileManager)
        migrateLegacyDataIfNeeded(to: rootURL, fileManager: fileManager)
    }

    package static func rootDirectoryURL(fileManager: FileManager = .default) -> URL {
        let rootURL = URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
            .appending(path: rootDirectoryName, directoryHint: .isDirectory)
        ensureDirectoryExists(at: rootURL, fileManager: fileManager)
        return rootURL
    }

    package static func historyStoreURL(fileManager: FileManager = .default) -> URL {
        prepare(fileManager: fileManager)
        return rootDirectoryURL(fileManager: fileManager).appending(path: historyStoreFileName)
    }

    package static func audioCacheDirectoryURL(fileManager: FileManager = .default) -> URL {
        prepare(fileManager: fileManager)
        let directoryURL = rootDirectoryURL(fileManager: fileManager)
            .appending(path: "AudioCache", directoryHint: .isDirectory)
        ensureDirectoryExists(at: directoryURL, fileManager: fileManager)
        return directoryURL
    }

    package static func voiceCatalogCacheDirectoryURL(fileManager: FileManager = .default) -> URL {
        prepare(fileManager: fileManager)
        let directoryURL = rootDirectoryURL(fileManager: fileManager)
            .appending(path: "VoiceCatalogCache", directoryHint: .isDirectory)
        ensureDirectoryExists(at: directoryURL, fileManager: fileManager)
        return directoryURL
    }

    package static func voicePreviewCacheDirectoryURL(fileManager: FileManager = .default) -> URL {
        prepare(fileManager: fileManager)
        let directoryURL = rootDirectoryURL(fileManager: fileManager)
            .appending(path: "VoicePreviewCache", directoryHint: .isDirectory)
        ensureDirectoryExists(at: directoryURL, fileManager: fileManager)
        return directoryURL
    }

    package static func defaultExportsDirectoryURL(fileManager: FileManager = .default) -> URL {
        prepare(fileManager: fileManager)
        let directoryURL = rootDirectoryURL(fileManager: fileManager)
            .appending(path: "Exports", directoryHint: .isDirectory)
        ensureDirectoryExists(at: directoryURL, fileManager: fileManager)
        return directoryURL
    }

    /// Set when a damaged history store had to be set aside at launch, so the UI can
    /// tell the user where the old file went instead of silently losing their history.
    /// Written once during launch and read from the main actor; a mutex keeps that
    /// cross-context access defined without pinning the type to an actor.
    private static let quarantinedHistoryStoreURLStorage = Mutex<URL?>(nil)

    package static var quarantinedHistoryStoreURL: URL? {
        quarantinedHistoryStoreURLStorage.withLock { $0 }
    }

    /// Moves an unreadable store out of the way so a fresh one can be created. The
    /// old file is kept, never deleted — a corrupt store is still the user's data.
    @discardableResult
    package static func quarantineHistoryStore(fileManager: FileManager = .default) -> URL? {
        let rootURL = rootDirectoryURL(fileManager: fileManager)
        let storeURL = rootURL.appending(path: historyStoreFileName)
        guard fileManager.fileExists(atPath: storeURL.path(percentEncoded: false)) else { return nil }

        let stamp = DateFormatter.quarantineStamp.string(from: .now)
        let quarantineURL = rootURL.appending(path: "\(historyStoreFileName).corrupt-\(stamp)")

        for suffix in ["", "-wal", "-shm"] {
            let source = rootURL.appending(path: "\(historyStoreFileName)\(suffix)")
            guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else { continue }
            let destination = rootURL.appending(path: "\(quarantineURL.lastPathComponent)\(suffix)")
            do {
                try fileManager.moveItem(at: source, to: destination)
            } catch {
                logger.error("Could not quarantine a history database file: \(error.localizedDescription, privacy: .public)")
            }
        }

        quarantinedHistoryStoreURLStorage.withLock { $0 = quarantineURL }
        return quarantineURL
    }

    private static func migrateLegacyDataIfNeeded(to rootURL: URL, fileManager: FileManager) {
        let legacyRootURL = legacyRootDirectoryURL(fileManager: fileManager)
        // `path()` percent-encodes, and the legacy path contains "Application Support";
        // checking the encoded string never matched, so the migration never ran.
        guard fileManager.fileExists(atPath: legacyRootURL.path(percentEncoded: false)) else { return }

        migrateLegacyData(from: legacyRootURL, to: rootURL, fileManager: fileManager)
    }

    /// Kept internal so migration behavior can be tested entirely in a temporary
    /// directory without touching the user's real Application Support folder.
    static func migrateLegacyData(from legacyRootURL: URL, to rootURL: URL, fileManager: FileManager = .default) {
        ensureDirectoryExists(at: rootURL, fileManager: fileManager)
        migrateHistoryStoreIfNeeded(from: legacyRootURL, to: rootURL, fileManager: fileManager)
        migrateAudioCacheIfNeeded(from: legacyRootURL, to: rootURL, fileManager: fileManager)
    }

    private static func migrateHistoryStoreIfNeeded(from legacyRootURL: URL, to rootURL: URL, fileManager: FileManager) {
        guard let legacyFiles = try? fileManager.contentsOfDirectory(
            at: legacyRootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        let historyFiles = legacyFiles.filter { fileURL in
            let name = fileURL.lastPathComponent
            return name == historyStoreFileName || name.hasPrefix("\(historyStoreFileName)-") || name.hasPrefix("\(historyStoreFileName).")
        }

        for fileURL in historyFiles {
            let destinationURL = rootURL.appending(path: fileURL.lastPathComponent)
            moveItemIfNeeded(from: fileURL, to: destinationURL, fileManager: fileManager)
        }
    }

    private static func migrateAudioCacheIfNeeded(from legacyRootURL: URL, to rootURL: URL, fileManager: FileManager) {
        let legacyCacheURL = legacyRootURL.appending(path: "AudioCache", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: legacyCacheURL.path(percentEncoded: false)) else { return }

        let newCacheURL = rootURL.appending(path: "AudioCache", directoryHint: .isDirectory)
        ensureDirectoryExists(at: newCacheURL, fileManager: fileManager)

        guard let cacheFiles = try? fileManager.contentsOfDirectory(
            at: legacyCacheURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        var everyFileArrived = true
        for fileURL in cacheFiles {
            let destinationURL = newCacheURL.appending(path: fileURL.lastPathComponent)
            let arrived = moveItemIfNeeded(from: fileURL, to: destinationURL, fileManager: fileManager)
            everyFileArrived = everyFileArrived && arrived
        }

        // Reclaim the old directory only once every file is confirmed at its new
        // location; otherwise a failed move would quietly destroy cached audio.
        if everyFileArrived {
            do {
                try fileManager.removeItem(at: legacyCacheURL)
            } catch {
                logger.error("Could not remove the migrated legacy audio cache: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Returns whether the item is present at the destination afterwards, which is
    /// what callers actually need to know before they clean up the source.
    @discardableResult
    private static func moveItemIfNeeded(from sourceURL: URL, to destinationURL: URL, fileManager: FileManager) -> Bool {
        let destinationPath = destinationURL.path(percentEncoded: false)
        guard fileManager.fileExists(atPath: sourceURL.path(percentEncoded: false)) else { return true }
        guard fileManager.fileExists(atPath: destinationPath) == false else { return true }

        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        } catch let moveError {
            do {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            } catch {
                logger.error(
                    "Local data migration failed after move error \(moveError.localizedDescription, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        return fileManager.fileExists(atPath: destinationPath)
    }

    private static func ensureDirectoryExists(at directoryURL: URL, fileManager: FileManager) {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            logger.error("Could not create a local data directory: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func legacyRootDirectoryURL(fileManager: FileManager) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appending(path: legacyDirectoryName, directoryHint: .isDirectory)
            ?? URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
                .appending(path: "Library/Application Support/\(legacyDirectoryName)", directoryHint: .isDirectory)
    }
}

private extension DateFormatter {
    static let quarantineStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter
    }()
}
