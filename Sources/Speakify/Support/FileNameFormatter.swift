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
}
