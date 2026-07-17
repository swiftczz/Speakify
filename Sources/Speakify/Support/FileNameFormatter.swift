import Foundation

enum FileNameFormatter {
    static func speechFileName(text: String, voiceName: String, fileExtension: String, date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        let title = text
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? "speech"

        let base = "\(formatter.string(from: date))-\(voiceName)-\(title)"
        let sanitized = base
            .replacingOccurrences(of: "[^A-Za-z0-9._ -]+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-_ "))

        return String(sanitized.prefix(80)) + ".\(fileExtension)"
    }

    /// A destination that collides with neither an existing file nor its companion
    /// sidecar (audio and subtitle are written as a pair and must stay in step),
    /// appending " (2)", " (3)", ... until both slots are free.
    static func availableURL(
        in directory: URL,
        fileName: String,
        companionExtension: String? = nil,
        fileManager: FileManager = .default
    ) -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let fileExtension = (fileName as NSString).pathExtension

        var candidate = directory.appending(path: fileName)
        var suffix = 2
        while isTaken(candidate, companionExtension: companionExtension, fileManager: fileManager) {
            candidate = directory.appending(path: "\(base) (\(suffix)).\(fileExtension)")
            suffix += 1
        }
        return candidate
    }

    private static func isTaken(
        _ url: URL,
        companionExtension: String?,
        fileManager: FileManager
    ) -> Bool {
        // `path()` percent-encodes, and the " (2)" suffix contains a space, so the
        // encoded string would never match a real file on disk.
        if fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            return true
        }
        guard let companionExtension else { return false }
        let companionURL = url.deletingPathExtension().appendingPathExtension(companionExtension)
        return fileManager.fileExists(atPath: companionURL.path(percentEncoded: false))
    }
}
