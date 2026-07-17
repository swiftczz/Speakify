import Foundation

/// One cached speech, which is an audio file plus its optional alignment sidecar.
/// The files share a cache key, so they are always evicted together.
struct AudioCacheEntry: Equatable {
    let key: String
    let urls: [URL]
    let modifiedAt: Date
    let size: Int
}

enum AudioCachePruner {
    /// Entries to delete: everything past `retention`, plus the oldest survivors
    /// while the cache is still over `sizeLimit`.
    static func entriesToEvict(
        from entries: [AudioCacheEntry],
        now: Date,
        retention: TimeInterval,
        sizeLimit: Int
    ) -> [AudioCacheEntry] {
        var expired: [AudioCacheEntry] = []
        var live: [AudioCacheEntry] = []

        for entry in entries {
            if now.timeIntervalSince(entry.modifiedAt) > retention {
                expired.append(entry)
            } else {
                live.append(entry)
            }
        }

        var liveSize = live.reduce(0) { $0 + $1.size }
        guard liveSize > sizeLimit else { return expired }

        var evicted = expired
        for entry in live.sorted(by: { $0.modifiedAt < $1.modifiedAt }) {
            guard liveSize > sizeLimit else { break }
            evicted.append(entry)
            liveSize -= entry.size
        }
        return evicted
    }

    /// Groups a directory listing into entries. Files are keyed by the filename up
    /// to the first dot, which is the request hash shared by an audio file and its
    /// `.alignment.json` sidecar.
    static func entries(from fileURLs: [URL], fileManager: FileManager = .default) -> [AudioCacheEntry] {
        var grouped: [String: (urls: [URL], modifiedAt: Date, size: Int)] = [:]

        for fileURL in fileURLs {
            guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modifiedAt = values.contentModificationDate else {
                continue
            }

            let key = fileURL.lastPathComponent.components(separatedBy: ".").first ?? fileURL.lastPathComponent
            var group = grouped[key] ?? (urls: [], modifiedAt: .distantPast, size: 0)
            group.urls.append(fileURL)
            group.modifiedAt = max(group.modifiedAt, modifiedAt)
            group.size += values.fileSize ?? 0
            grouped[key] = group
        }

        return grouped.map { key, group in
            AudioCacheEntry(key: key, urls: group.urls, modifiedAt: group.modifiedAt, size: group.size)
        }
    }
}
