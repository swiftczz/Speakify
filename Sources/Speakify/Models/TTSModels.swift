import Foundation

struct TTSModel: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let canDoTextToSpeech: Bool
    let servesProVoices: Bool
}

/// A provider-neutral view of "how much can I still synthesize".
struct TTSQuota: Equatable, Sendable {
    let characterCount: Int
    let characterLimit: Int
    let canExtendCharacterLimit: Bool

    init(characterCount: Int, characterLimit: Int, canExtendCharacterLimit: Bool = false) {
        self.characterCount = characterCount
        self.characterLimit = characterLimit
        self.canExtendCharacterLimit = canExtendCharacterLimit
    }

    var remaining: Int { max(0, characterLimit - characterCount) }
    var usedFraction: Double {
        guard characterLimit > 0 else { return 0 }
        return min(1, Double(characterCount) / Double(characterLimit))
    }

}

enum OutputFormat {
    /// Human-readable label for a provider format ID such as `mp3_44100_128` or `wav`.
    static func displayName(for format: String) -> String {
        let parts = format.split(separator: "_").map(String.init)
        guard let codec = parts.first else { return format }

        var components = [codec.uppercased()]
        if parts.count > 1, let hertz = Int(parts[1]) {
            components.append(String(format: "%g kHz", Double(hertz) / 1_000))
        }
        if parts.count > 2, let kbps = Int(parts[2]) {
            components.append("\(kbps) kbps")
        }
        return components.joined(separator: " · ")
    }
}

struct TTSVoice: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let category: String?
    let detail: String?
    let previewURL: URL?
    let gender: String?
    let accent: String?
    let locale: String?
    let language: String?

    var subtitle: String {
        [formattedGender, countryDisplayName, accent, category]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " - ")
    }

    var displayName: String {
        let metadata = [formattedGender, countryCode]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
        return metadata.isEmpty ? name : "\(name) · \(metadata)"
    }

    var isProfessionalVoice: Bool {
        category?.localizedCaseInsensitiveContains("professional") == true
    }

    private var formattedGender: String? {
        guard let gender, gender.isEmpty == false else { return nil }
        switch gender.lowercased() {
        case "male":
            return "Male"
        case "female":
            return "Female"
        default:
            return gender.capitalized
        }
    }

    private var countryCode: String? {
        guard let locale else { return nil }
        let identifier = locale.replacingOccurrences(of: "-", with: "_")
        return Locale(identifier: identifier).region?.identifier
    }

    private var countryDisplayName: String? {
        guard let countryCode else { return nil }
        return Locale.current.localizedString(forRegionCode: countryCode)
    }
}

enum TTSLimits {
    static let maxCharacterCount = 5_000
}

enum SpeechLanguage {
    /// An empty code means the field is omitted so the model detects the language from the text.
    static let autoDetect = ""

    static let supportedCodes = [
        autoDetect,
        "en", "zh", "ja", "ko", "es", "fr", "de", "it", "pt", "ru",
        "hi", "ar", "nl", "pl", "tr", "sv", "id", "vi", "cs", "uk"
    ]

    static func displayName(for code: String, locale: Locale = .current) -> String {
        guard code.isEmpty == false else {
            return L10n.string("Auto detect", defaultValue: "Auto detect")
        }
        return (locale.localizedString(forLanguageCode: code) ?? code).localizedCapitalized
    }
}

struct VoiceSettings: Codable, Equatable, Sendable {
    var stability: Double = 0.5
    var similarityBoost: Double = 0.75
    var style: Double = 0.0
    var speed: Double = 1.0
    var speakerBoost: Bool = true
}

struct SpeechRequest: Equatable, Sendable {
    var text: String
    var voice: TTSVoice
    var modelID: String
    var outputFormat: String
    var languageCode: String?
    var voiceSettings: VoiceSettings
}

struct GeneratedSpeech: Sendable {
    let audioData: Data
    let fileExtension: String
    let request: SpeechRequest
    let alignment: SpeechAlignment?
}

struct SpeechAlignment: Codable, Equatable, Sendable {
    let characters: [String]
    let characterStartTimesSeconds: [TimeInterval]
    let characterEndTimesSeconds: [TimeInterval]

    /// Matching lengths alone are not enough to build a subtitle from: a cue needs
    /// finite, forward-moving timestamps. Anything else is rejected here so callers
    /// fall back to an estimated timeline instead of emitting a broken SRT.
    var isValid: Bool {
        guard characters.isEmpty == false,
              characters.count == characterStartTimesSeconds.count,
              characters.count == characterEndTimesSeconds.count else {
            return false
        }

        var previousStart = -Double.greatestFiniteMagnitude
        for index in characters.indices {
            let start = characterStartTimesSeconds[index]
            let end = characterEndTimesSeconds[index]
            guard start.isFinite, end.isFinite, start >= 0, end >= start, start >= previousStart else {
                return false
            }
            previousStart = start
        }
        return true
    }

    enum CodingKeys: String, CodingKey {
        case characters
        case characterStartTimesSeconds = "character_start_times_seconds"
        case characterEndTimesSeconds = "character_end_times_seconds"
    }
}

enum TTSProviderError: LocalizedError, Sendable {
    case missingAPIKey
    case missingVoice
    case invalidText
    case textTooLong(count: Int, limit: Int)
    case insufficientCredits(required: Int, remaining: Int)
    case invalidResponse
    case requestChanged
    /// `code` is the service's machine-readable identifier (e.g. `voice_not_found`),
    /// kept separate so callers never have to pattern-match the human-readable message.
    case httpStatus(status: Int, message: String, code: String?)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return L10n.string(
                "error.missing-api-key",
                defaultValue: "Please add the speech service's API key in Settings first."
            )
        case .missingVoice:
            return L10n.string(
                "error.missing-voice",
                defaultValue: "Please choose a reader voice."
            )
        case .invalidText:
            return L10n.string(
                "error.invalid-text",
                defaultValue: "Please enter text to read."
            )
        case let .textTooLong(count, limit):
            let format = L10n.string(
                "error.text-too-long",
                defaultValue: "The text is %1$lld characters, which is over the %2$lld-character limit. Please shorten it."
            )
            return String(format: format, Int64(count), Int64(limit))
        case let .insufficientCredits(required, remaining):
            let format = L10n.string(
                "error.insufficient-credits",
                defaultValue: "Not enough credits: this text is estimated to need %1$lld, but only %2$lld remain. Shorten the text or add credits."
            )
            return String(format: format, Int64(required), Int64(remaining))
        case .invalidResponse:
            return L10n.string(
                "error.invalid-response",
                defaultValue: "The speech service returned an invalid response."
            )
        case .requestChanged:
            return L10n.string(
                "error.request-changed",
                defaultValue: "The speech request changed. Press play again to generate the latest text."
            )
        case let .httpStatus(status, message, _):
            let format = L10n.string(
                "error.http-status",
                defaultValue: "Speech service error %1$lld: %2$@"
            )
            return String(format: format, Int64(status), message)
        }
    }
}
