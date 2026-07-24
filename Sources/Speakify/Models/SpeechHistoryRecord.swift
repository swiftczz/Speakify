import Foundation
import SwiftData

@Model
package final class SpeechHistoryRecord {
    var title: String
    /// Defaults preserve lightweight migration for records created before provider
    /// and voice configuration were captured.
    var providerID: String = ""
    var voiceName: String
    var voiceID: String
    var modelID: String
    var outputFormat: String
    var languageCode: String = ""
    var stability: Double = 0.5
    var similarityBoost: Double = 0.75
    var style: Double = 0
    var speed: Double = 1
    var speakerBoost: Bool = true
    var duration: TimeInterval?
    var createdAt: Date
    var requestKey: String

    init(
        title: String,
        providerID: String = "",
        voiceName: String,
        voiceID: String,
        modelID: String,
        outputFormat: String,
        languageCode: String = "",
        voiceSettings: VoiceSettings = VoiceSettings(),
        duration: TimeInterval?,
        createdAt: Date = .now,
        requestKey: String
    ) {
        self.title = title
        self.providerID = providerID
        self.voiceName = voiceName
        self.voiceID = voiceID
        self.modelID = modelID
        self.outputFormat = outputFormat
        self.languageCode = languageCode
        stability = voiceSettings.stability
        similarityBoost = voiceSettings.similarityBoost
        style = voiceSettings.style
        speed = voiceSettings.speed
        speakerBoost = voiceSettings.speakerBoost
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

    var draft: SpeechHistoryDraft {
        SpeechHistoryDraft(
            text: title,
            providerID: providerID,
            voiceID: voiceID,
            modelID: modelID,
            outputFormat: outputFormat,
            languageCode: languageCode,
            voiceSettings: VoiceSettings(
                stability: stability,
                similarityBoost: similarityBoost,
                style: style,
                speed: speed,
                speakerBoost: speakerBoost
            )
        )
    }
}

struct SpeechHistoryDraft: Equatable, Sendable {
    let text: String
    let providerID: String
    let voiceID: String
    let modelID: String
    let outputFormat: String
    let languageCode: String
    let voiceSettings: VoiceSettings
}
