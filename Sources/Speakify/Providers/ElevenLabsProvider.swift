import Foundation

struct ElevenLabsProvider: TTSProvider {
    let id = "elevenlabs"
    let displayName = "ElevenLabs"

    private let baseURL = URL(string: "https://api.elevenlabs.io")!

    func fetchModels(apiKey: String) async throws -> [TTSModel] {
        guard apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw TTSProviderError.missingAPIKey
        }

        var request = URLRequest(url: baseURL.appending(path: "/v1/models"))
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        let decoded = try JSONDecoder().decode([ElevenLabsModel].self, from: data)
        let supportedIDs = TTSModel.supportedIDs
        let models = decoded
            .filter { model in
                model.canDoTextToSpeech && supportedIDs.contains(model.modelID)
            }
            .map {
                TTSModel(
                    id: $0.modelID,
                    name: $0.name,
                    canDoTextToSpeech: $0.canDoTextToSpeech,
                    servesProVoices: $0.servesProVoices
                )
            }
            .sorted { first, second in
                (supportedIDs.firstIndex(of: first.id) ?? Int.max)
                    < (supportedIDs.firstIndex(of: second.id) ?? Int.max)
            }

        return models.isEmpty ? TTSModel.fallbackModels : models
    }

    func fetchVoices(apiKey: String) async throws -> [TTSVoice] {
        guard apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw TTSProviderError.missingAPIKey
        }

        var components = URLComponents(url: baseURL.appending(path: "/v2/voices"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "page_size", value: "100"),
            URLQueryItem(name: "include_total_count", value: "false")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(ElevenLabsVoicesResponse.self, from: data)
        return decoded.voices
            .map {
                TTSVoice(
                    id: $0.voiceID,
                    name: $0.name,
                    category: $0.category,
                    detail: $0.description,
                    previewURL: $0.previewURL,
                    gender: $0.labels?["gender"],
                    accent: $0.labels?["accent"] ?? $0.verifiedLanguages.first?.accent,
                    locale: $0.labels?["locale"] ?? $0.verifiedLanguages.first?.locale,
                    language: $0.labels?["language"] ?? $0.verifiedLanguages.first?.language
                )
            }
            .filter { voice in
                voice.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    && voice.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func fetchSubscription(apiKey: String) async throws -> ElevenLabsSubscription {
        guard apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw TTSProviderError.missingAPIKey
        }

        var request = URLRequest(url: baseURL.appending(path: "/v1/user/subscription"))
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        return try JSONDecoder().decode(ElevenLabsSubscription.self, from: data)
    }

    func synthesize(request speechRequest: SpeechRequest, apiKey: String) async throws -> GeneratedSpeech {
        guard apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw TTSProviderError.missingAPIKey
        }

        var components = URLComponents(
            url: baseURL.appending(path: "/v1/text-to-speech/\(speechRequest.voice.id)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "output_format", value: speechRequest.outputFormat)
        ]

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(ElevenLabsSpeechBody(from: speechRequest))

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try validate(response: response, data: data)

        return GeneratedSpeech(
            audioData: data,
            fileExtension: speechRequest.outputFormat.hasPrefix("wav") ? "wav" : "mp3",
            request: speechRequest
        )
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSProviderError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = ElevenLabsErrorMessage.message(from: data)
            throw TTSProviderError.httpStatus(httpResponse.statusCode, message)
        }
    }
}

private struct ElevenLabsModel: Decodable {
    let modelID: String
    let name: String
    let canDoTextToSpeech: Bool
    let servesProVoices: Bool

    enum CodingKeys: String, CodingKey {
        case modelID = "model_id"
        case name
        case canDoTextToSpeech = "can_do_text_to_speech"
        case servesProVoices = "serves_pro_voices"
    }
}

private struct ElevenLabsVoicesResponse: Decodable {
    let voices: [ElevenLabsVoice]
}

private struct ElevenLabsVoice: Decodable {
    let voiceID: String
    let name: String
    let category: String?
    let description: String?
    let previewURL: URL?
    let labels: [String: String]?
    let verifiedLanguages: [ElevenLabsVerifiedLanguage]

    enum CodingKeys: String, CodingKey {
        case voiceID = "voice_id"
        case name
        case category
        case description
        case previewURL = "preview_url"
        case labels
        case verifiedLanguages = "verified_languages"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        voiceID = try container.decode(String.self, forKey: .voiceID)
        name = try container.decode(String.self, forKey: .name)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        previewURL = try container.decodeIfPresent(URL.self, forKey: .previewURL)
        labels = try container.decodeIfPresent([String: String].self, forKey: .labels)
        verifiedLanguages = try container.decodeIfPresent([ElevenLabsVerifiedLanguage].self, forKey: .verifiedLanguages) ?? []
    }
}

private struct ElevenLabsVerifiedLanguage: Decodable {
    let language: String?
    let accent: String?
    let locale: String?
}

private struct ElevenLabsSpeechBody: Encodable {
    let text: String
    let modelID: String
    let languageCode: String
    let voiceSettings: ElevenLabsVoiceSettings

    init(from request: SpeechRequest) {
        text = request.text
        modelID = request.modelID
        languageCode = "en"
        voiceSettings = ElevenLabsVoiceSettings(from: request.voiceSettings)
    }

    enum CodingKeys: String, CodingKey {
        case text
        case modelID = "model_id"
        case languageCode = "language_code"
        case voiceSettings = "voice_settings"
    }
}

private struct ElevenLabsVoiceSettings: Encodable {
    let stability: Double
    let similarityBoost: Double
    let style: Double
    let useSpeakerBoost: Bool
    let speed: Double

    init(from settings: VoiceSettings) {
        stability = settings.stability
        similarityBoost = settings.similarityBoost
        style = settings.style
        useSpeakerBoost = settings.speakerBoost
        speed = settings.speed
    }

    enum CodingKeys: String, CodingKey {
        case stability
        case similarityBoost = "similarity_boost"
        case style
        case useSpeakerBoost = "use_speaker_boost"
        case speed
    }
}

struct ElevenLabsSubscription: Decodable, Equatable, Sendable {
    let characterCount: Int
    let characterLimit: Int

    var remaining: Int { max(0, characterLimit - characterCount) }
    var usedFraction: Double {
        guard characterLimit > 0 else { return 0 }
        return min(1, Double(characterCount) / Double(characterLimit))
    }

    enum CodingKeys: String, CodingKey {
        case characterCount = "character_count"
        case characterLimit = "character_limit"
    }
}

private enum ElevenLabsErrorMessage {
    static func message(from data: Data) -> String {
        guard data.isEmpty == false else {
            return "No error body returned."
        }

        if let decoded = try? JSONDecoder().decode(DetailEnvelope.self, from: data) {
            return decoded.readableMessage
        }

        return String(data: data, encoding: .utf8) ?? "Unreadable error body."
    }

    private struct DetailEnvelope: Decodable {
        let detail: Detail?
        let message: String?

        var readableMessage: String {
            message ?? detail?.message ?? detail?.status ?? "Unknown service error."
        }
    }

    private struct Detail: Decodable {
        let status: String?
        let message: String?
    }
}
