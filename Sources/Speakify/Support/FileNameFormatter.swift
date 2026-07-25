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

    private static let disallowedNameCharacters: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: ". -_")
        return allowed.inverted
    }()

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
        if fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            return true
        }
        guard let companionExtension else { return false }
        let companionURL = url.deletingPathExtension().appendingPathExtension(companionExtension)
        return fileManager.fileExists(atPath: companionURL.path(percentEncoded: false))
    }
}
