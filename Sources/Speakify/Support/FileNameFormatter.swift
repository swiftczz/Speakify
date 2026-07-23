import Foundation

enum FileNameFormatter {
    static func speechFileName(text: String, voiceName: String, fileExtension: String, date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmmss"

        let title = text
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? "speech"
        let primaryVoiceName = primaryVoiceName(from: voiceName)

        let base = "\(formatter.string(from: date))-\(primaryVoiceName)-\(title)"
        let sanitized = base
            .components(separatedBy: disallowedNameCharacters).joined()
            .replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-_ "))

        return truncated(sanitized) + ".\(fileExtension)"
    }

    /// Everything outside letters, digits and the three separators a file name
    /// reads well with. Letters are Unicode-wide, so Chinese and other non-Latin
    /// scripts survive; only punctuation and symbols are dropped.
    private static let disallowedNameCharacters: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: ". -_")
        return allowed.inverted
    }()

    /// HFS+/APFS cap file names at 255 bytes, and one CJK character costs three,
    /// so a character-only limit is not enough to stay inside it.
    private static func truncated(_ name: String, characterLimit: Int = 80, byteLimit: Int = 180) -> String {
        var result = String(name.prefix(characterLimit))
        while result.utf8.count > byteLimit {
            result.removeLast()
        }
        return result
    }

    private static func primaryVoiceName(from voiceName: String) -> String {
        let separators = [" - ", " – ", " — ", " / ", " · ", ", "]
        let firstSeparator = separators
            .compactMap { voiceName.range(of: $0)?.lowerBound }
            .min()
        let name = firstSeparator.map { String(voiceName[..<$0]) } ?? voiceName
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Voice" : trimmedName
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
