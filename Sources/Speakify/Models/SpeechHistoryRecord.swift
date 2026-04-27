import Foundation
import SwiftData

@Model
final class SpeechHistoryRecord {
    var title: String
    var voiceName: String
    var voiceID: String
    var modelID: String
    var outputFormat: String
    var duration: TimeInterval?
    var createdAt: Date
    var requestKey: String

    init(
        title: String,
        voiceName: String,
        voiceID: String,
        modelID: String,
        outputFormat: String,
        duration: TimeInterval?,
        createdAt: Date = .now,
        requestKey: String
    ) {
        self.title = title
        self.voiceName = voiceName
        self.voiceID = voiceID
        self.modelID = modelID
        self.outputFormat = outputFormat
        self.duration = duration
        self.createdAt = createdAt
        self.requestKey = requestKey
    }

    var preview: String {
        let collapsed = title
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(collapsed.prefix(34)) + (collapsed.count > 34 ? "..." : "")
    }

    var durationText: String {
        guard let duration else { return "--:--" }
        let seconds = max(Int(duration.rounded()), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

