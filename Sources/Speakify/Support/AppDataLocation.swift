import Foundation

package enum AppDataLocation {
    private static let rootDirectoryName = ".speakify"
    private static let legacyDirectoryName = "com.local.Speakify"
    private static let historyStoreFileName = "History.store"

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

    package static func defaultExportsDirectoryURL(fileManager: FileManager = .default) -> URL {
        prepare(fileManager: fileManager)
        let directoryURL = rootDirectoryURL(fileManager: fileManager)
            .appending(path: "Exports", directoryHint: .isDirectory)
        ensureDirectoryExists(at: directoryURL, fileManager: fileManager)
        return directoryURL
    }

    private static func migrateLegacyDataIfNeeded(to rootURL: URL, fileManager: FileManager) {
        let legacyRootURL = legacyRootDirectoryURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: legacyRootURL.path()) else { return }

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
        guard fileManager.fileExists(atPath: legacyCacheURL.path()) else { return }

        let newCacheURL = rootURL.appending(path: "AudioCache", directoryHint: .isDirectory)
        ensureDirectoryExists(at: newCacheURL, fileManager: fileManager)

        guard let cacheFiles = try? fileManager.contentsOfDirectory(
            at: legacyCacheURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for fileURL in cacheFiles {
            let destinationURL = newCacheURL.appending(path: fileURL.lastPathComponent)
            moveItemIfNeeded(from: fileURL, to: destinationURL, fileManager: fileManager)
        }

        try? fileManager.removeItem(at: legacyCacheURL)
    }

    private static func moveItemIfNeeded(from sourceURL: URL, to destinationURL: URL, fileManager: FileManager) {
        guard fileManager.fileExists(atPath: sourceURL.path()) else { return }
        guard fileManager.fileExists(atPath: destinationURL.path()) == false else { return }

        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        } catch {
            try? fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    private static func ensureDirectoryExists(at directoryURL: URL, fileManager: FileManager) {
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private static func legacyRootDirectoryURL(fileManager: FileManager) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appending(path: legacyDirectoryName, directoryHint: .isDirectory)
            ?? URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
                .appending(path: "Library/Application Support/\(legacyDirectoryName)", directoryHint: .isDirectory)
    }
}