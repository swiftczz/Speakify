import Foundation

struct TTSModel: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let canDoTextToSpeech: Bool
    let servesProVoices: Bool

    static let supportedIDs = [
        "eleven_v3",
        "eleven_multilingual_v2",
        "eleven_flash_v2_5"
    ]

    static let fallbackModels: [TTSModel] = [
        TTSModel(id: "eleven_v3", name: "Eleven v3", canDoTextToSpeech: true, servesProVoices: false),
        TTSModel(id: "eleven_multilingual_v2", name: "Eleven Multilingual v2", canDoTextToSpeech: true, servesProVoices: false),
        TTSModel(id: "eleven_flash_v2_5", name: "Eleven Flash v2.5", canDoTextToSpeech: true, servesProVoices: false)
    ]
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

    static func displayName(for code: String) -> String {
        guard code.isEmpty == false else { return "Auto detect" }
        return (Locale.current.localizedString(forLanguageCode: code) ?? code).localizedCapitalized
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

    var isValid: Bool {
        characters.isEmpty == false
            && characters.count == characterStartTimesSeconds.count
            && characters.count == characterEndTimesSeconds.count
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
    case invalidResponse
    case requestChanged
    /// `code` is the service's machine-readable identifier (e.g. `voice_not_found`),
    /// kept separate so callers never have to pattern-match the human-readable message.
    case httpStatus(status: Int, message: String, code: String?)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Please configure your ElevenLabs API key first."
        case .missingVoice:
            return "Please choose a reader voice."
        case .invalidText:
            return "Please enter text to read."
        case let .textTooLong(count, limit):
            return "The text is \(count) characters, which is over the \(limit)-character limit. Please shorten it."
        case .invalidResponse:
            return "The speech service returned an invalid response."
        case .requestChanged:
            return "The speech request changed. Press play again to generate the latest text."
        case let .httpStatus(status, message, _):
            return "Speech service error \(status): \(message)"
        }
    }
}
