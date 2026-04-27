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
    var voiceSettings: VoiceSettings
}

struct GeneratedSpeech: Sendable {
    let audioData: Data
    let fileExtension: String
    let request: SpeechRequest
}

enum TTSProviderError: LocalizedError, Sendable {
    case missingAPIKey
    case missingVoice
    case invalidText
    case invalidResponse
    case requestChanged
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Please configure your ElevenLabs API key first."
        case .missingVoice:
            return "Please choose a reader voice."
        case .invalidText:
            return "Please enter English text to read."
        case .invalidResponse:
            return "The speech service returned an invalid response."
        case .requestChanged:
            return "The speech request changed. Press play again to generate the latest text."
        case let .httpStatus(status, message):
            return "Speech service error \(status): \(message)"
        }
    }
}
