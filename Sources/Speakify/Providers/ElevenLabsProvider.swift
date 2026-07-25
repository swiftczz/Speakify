import Foundation

struct ElevenLabsProvider: TTSProvider {
    let id = "elevenlabs"
    let displayName = "ElevenLabs"

    let capabilities = TTSProviderCapabilities(
        outputFormats: ["mp3_44100_128", "mp3_44100_192", "mp3_22050_32", "wav_44100"],
        defaultOutputFormat: "mp3_44100_128",
        defaultModelID: "eleven_v3",
        reportsQuota: true,
        providesSubtitles: true,
        providesCharacterAlignment: true,
        acceptsLanguageHint: true,
        meteredSynthesis: true,
        apiKeyHint: "Create a key at elevenlabs.io under Profile → API Keys.",
        defaultCharacterLimit: 5_000,
        modelCharacterLimits: [
            "eleven_v3": 5_000,
            "eleven_multilingual_v2": 10_000,
            "eleven_flash_v2_5": 40_000
        ],
        creditPolicy: .characters(
            defaultMultiplier: 1,
            modelMultipliers: ["eleven_flash_v2_5": 0.5]
        ),
        voiceSettings: TTSVoiceSettingsCapabilities(
            stabilityRange: 0...1,
            similarityRange: 0...1,
            styleRange: 0...1,
            speedRange: 0.7...1.2,
            modelsWithoutSpeed: ["eleven_v3"],
            supportsSpeakerBoost: true
        )
    )

    static let supportedModelIDs = [
        "eleven_v3",
        "eleven_multilingual_v2",
        "eleven_flash_v2_5"
    ]

    /// Offline fallback for the anonymous `/v1/voices` catalog.
    static let publicDefaultVoices: [TTSVoice] = [
        publicVoice(id: "CwhRBWXzGAHq8TQ4Fs17", name: "Roger - Laid-Back, Casual, Resonant", gender: "male"),
        publicVoice(id: "EXAVITQu4vr4xnSDxMaL", name: "Sarah - Mature, Reassuring, Confident", gender: "female"),
        publicVoice(id: "FGY2WhTYpPnrIDTdsKH5", name: "Laura - Enthusiast, Quirky Attitude", gender: "female"),
        publicVoice(id: "IKne3meq5aSn9XLyUdCD", name: "Charlie - Deep, Confident, Energetic", gender: "male"),
        publicVoice(id: "JBFqnCBsd6RMkjVDRZzb", name: "George - Warm, Captivating Storyteller", gender: "male"),
        publicVoice(id: "N2lVS1w4EtoT3dr4eOWO", name: "Callum - Husky Trickster", gender: "male"),
        publicVoice(id: "SAz9YHcvj6GT2YYXdXww", name: "River - Relaxed, Neutral, Informative", gender: nil),
        publicVoice(id: "SOYHLrjzK2X1ezoPC6cr", name: "Harry - Fierce Warrior", gender: "male"),
        publicVoice(id: "TX3LPaxmHKxFdv7VOQHJ", name: "Liam - Energetic, Social Media Creator", gender: "male"),
        publicVoice(id: "Xb7hH8MSUJpSbSDYk0k2", name: "Alice - Clear, Engaging Educator", gender: "female"),
        publicVoice(id: "XrExE9yKIg1WjnnlVkGX", name: "Matilda - Knowledgable, Professional", gender: "female"),
        publicVoice(id: "bIHbv24MWmeRgasZH58o", name: "Will - Relaxed Optimist", gender: "male"),
        publicVoice(id: "cgSgspJ2msm6clMCkdW9", name: "Jessica - Playful, Bright, Warm", gender: "female"),
        publicVoice(id: "cjVigY5qzO86Huf0OWal", name: "Eric - Smooth, Trustworthy", gender: "male"),
        publicVoice(id: "hpp4J3VqNfWAUOO0d1Us", name: "Bella - Professional, Bright, Warm", gender: "female"),
        publicVoice(id: "iP95p4xoKVk53GoZ742B", name: "Chris - Charming, Down-to-Earth", gender: "male"),
        publicVoice(id: "nPczCjzI2devNBz1zQrb", name: "Brian - Deep, Resonant and Comforting", gender: "male"),
        publicVoice(id: "onwK4e9ZLuTAKqWW03F9", name: "Daniel - Steady Broadcaster", gender: "male"),
        publicVoice(id: "pFZP5JQG7iQjIQuC4Bku", name: "Lily - Velvety Actress", gender: "female"),
        publicVoice(id: "pNInz6obpgDQGcFmaJgB", name: "Adam - Dominant, Firm", gender: "male"),
        publicVoice(id: "pqHfZKP75CvOlQylNhV4", name: "Bill - Wise, Mature, Balanced", gender: "male")
    ]

    var fallbackModels: [TTSModel] {
        [
            TTSModel(id: "eleven_v3", name: "Eleven v3", canDoTextToSpeech: true, servesProVoices: false),
            TTSModel(id: "eleven_multilingual_v2", name: "Eleven Multilingual v2", canDoTextToSpeech: true, servesProVoices: false),
            TTSModel(id: "eleven_flash_v2_5", name: "Eleven Flash v2.5", canDoTextToSpeech: true, servesProVoices: false)
        ]
    }

    private let baseURL = URL(string: "https://api.elevenlabs.io")!
    private let session: URLSession

    init(session: URLSession = ElevenLabsProvider.makeSession()) {
        self.session = session
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        // Guards against a request that stalls forever; synthesis of long text is
        // allowed to take a while as long as the connection keeps delivering data.
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration)
    }

    func fetchModels(apiKey: String) async throws -> [TTSModel] {
        let resolvedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard resolvedAPIKey.isEmpty == false else {
            return fallbackModels
        }

        var request = URLRequest(url: baseURL.appending(path: "/v1/models"))
        request.httpMethod = "GET"
        request.setValue(resolvedAPIKey, forHTTPHeaderField: "xi-api-key")

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        let decoded = try JSONDecoder().decode([ElevenLabsModel].self, from: data)
        let supportedIDs = Self.supportedModelIDs
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

        return models.isEmpty ? fallbackModels : models
    }

    func fetchVoiceCatalog(apiKey: String) async throws -> TTSVoiceCatalog {
        let publicVoices = await fetchPublicVoices()
        let resolvedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard resolvedAPIKey.isEmpty == false else {
            return TTSVoiceCatalog(publicVoices: publicVoices, accountVoices: [])
        }

        // The account half failing (bad key, rate limit, outage) must not take the
        // public half down with it: a usable picker beats an empty one.
        do {
            let accountVoices = try await fetchAccountVoices(apiKey: resolvedAPIKey)
            return TTSVoiceCatalog(publicVoices: publicVoices, accountVoices: accountVoices)
        } catch {
            try Task.checkCancellation()
            return TTSVoiceCatalog(
                publicVoices: publicVoices,
                accountVoices: [],
                accountFailure: error.localizedDescription
            )
        }
    }

    private func fetchPublicVoices() async -> [TTSVoice] {
        var request = URLRequest(url: baseURL.appending(path: "/v1/voices"))
        request.httpMethod = "GET"

        do {
            let (data, response) = try await session.data(for: request)
            try validate(response: response, data: data)
            let voices = try decodeVoices(from: data)
            return voices.isEmpty ? Self.publicDefaultVoices : voices
        } catch {
            return Self.publicDefaultVoices
        }
    }

    /// `/v2/voices` pages at 100 entries, so an account with more cloned voices than
    /// that needs every page followed before the picker shows a complete list.
    private func fetchAccountVoices(apiKey: String) async throws -> [TTSVoice] {
        var voices: [ElevenLabsVoice] = []
        var nextPageToken: String?
        var pagesFetched = 0

        repeat {
            try Task.checkCancellation()

            var components = URLComponents(url: baseURL.appending(path: "/v2/voices"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "page_size", value: "100"),
                URLQueryItem(name: "include_total_count", value: "false")
            ] + (nextPageToken.map { [URLQueryItem(name: "next_page_token", value: $0)] } ?? [])

            var request = URLRequest(url: components.url!)
            request.httpMethod = "GET"
            request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

            let (data, response) = try await session.data(for: request)
            try validate(response: response, data: data)

            let page = try JSONDecoder().decode(ElevenLabsVoicesResponse.self, from: data)
            voices += page.voices
            nextPageToken = page.hasMore ? page.nextPageToken : nil
            pagesFetched += 1
        } while nextPageToken != nil && pagesFetched < Self.maxVoicePages

        return normalized(voices)
    }

    /// A stop so a service that keeps handing back a token can never spin forever.
    private static let maxVoicePages = 20

    private func decodeVoices(from data: Data) throws -> [TTSVoice] {
        normalized(try JSONDecoder().decode(ElevenLabsVoicesResponse.self, from: data).voices)
    }

    private func normalized(_ voices: [ElevenLabsVoice]) -> [TTSVoice] {
        voices
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

    func fetchQuota(apiKey: String) async throws -> TTSQuota? {
        guard apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw TTSProviderError.missingAPIKey
        }

        var request = URLRequest(url: baseURL.appending(path: "/v1/user/subscription"))
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        return try JSONDecoder().decode(ElevenLabsSubscriptionResponse.self, from: data).quota
    }

    func synthesize(request speechRequest: SpeechRequest, apiKey: String) async throws -> GeneratedSpeech {
        guard apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw TTSProviderError.missingAPIKey
        }

        var components = URLComponents(
            url: baseURL.appending(path: "/v1/text-to-speech/\(speechRequest.voice.id)/with-timestamps"),
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

        let (data, response) = try await session.data(for: urlRequest)
        try validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(ElevenLabsTimestampedSpeech.self, from: data)
        guard let audioData = Data(base64Encoded: decoded.audioBase64), audioData.isEmpty == false else {
            throw TTSProviderError.invalidResponse
        }

        let alignment = [decoded.alignment, decoded.normalizedAlignment]
            .compactMap { $0 }
            .first(where: \.isValid)

        return GeneratedSpeech(
            audioData: audioData,
            fileExtension: speechRequest.outputFormat.hasPrefix("wav") ? "wav" : "mp3",
            request: speechRequest,
            alignment: alignment
        )
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSProviderError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let failure = ElevenLabsErrorMessage.parse(from: data)
            throw TTSProviderError.httpStatus(
                status: httpResponse.statusCode,
                message: failure.message,
                code: failure.code
            )
        }
    }
}

private func publicVoice(id: String, name: String, gender: String?) -> TTSVoice {
    TTSVoice(
        id: id,
        name: name,
        category: "default",
        detail: nil,
        previewURL: nil,
        gender: gender,
        accent: nil,
        locale: nil,
        language: "English"
    )
}

private struct ElevenLabsTimestampedSpeech: Decodable {
    let audioBase64: String
    let alignment: SpeechAlignment?
    let normalizedAlignment: SpeechAlignment?

    enum CodingKeys: String, CodingKey {
        case audioBase64 = "audio_base64"
        case alignment
        case normalizedAlignment = "normalized_alignment"
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
    let hasMore: Bool
    let nextPageToken: String?

    enum CodingKeys: String, CodingKey {
        case voices
        case hasMore = "has_more"
        case nextPageToken = "next_page_token"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        voices = try container.decode([ElevenLabsVoice].self, forKey: .voices)
        // `/v1/voices` returns neither field and is never paged.
        hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
        nextPageToken = try container.decodeIfPresent(String.self, forKey: .nextPageToken)
    }
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

    init(from decoder: any Decoder) throws {
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
    /// Omitted when nil so the model detects the language from the text itself.
    let languageCode: String?
    let voiceSettings: ElevenLabsVoiceSettings

    init(from request: SpeechRequest) {
        text = request.text
        modelID = request.modelID
        languageCode = request.languageCode
        voiceSettings = ElevenLabsVoiceSettings(
            from: request.voiceSettings,
            includesSpeed: request.modelID != "eleven_v3"
        )
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
    let speed: Double?

    init(from settings: VoiceSettings, includesSpeed: Bool) {
        stability = settings.stability
        similarityBoost = settings.similarityBoost
        style = settings.style
        useSpeakerBoost = settings.speakerBoost
        speed = includesSpeed ? settings.speed : nil
    }

    enum CodingKeys: String, CodingKey {
        case stability
        case similarityBoost = "similarity_boost"
        case style
        case useSpeakerBoost = "use_speaker_boost"
        case speed
    }
}

private struct ElevenLabsSubscriptionResponse: Decodable {
    let characterCount: Int
    let characterLimit: Int
    let canExtendCharacterLimit: Bool?

    var quota: TTSQuota {
        TTSQuota(
            characterCount: characterCount,
            characterLimit: characterLimit,
            canExtendCharacterLimit: canExtendCharacterLimit ?? false
        )
    }

    enum CodingKeys: String, CodingKey {
        case characterCount = "character_count"
        case characterLimit = "character_limit"
        case canExtendCharacterLimit = "can_extend_character_limit"
    }
}

private enum ElevenLabsErrorMessage {
    static func parse(from data: Data) -> (message: String, code: String?) {
        guard data.isEmpty == false else {
            return ("No error body returned.", nil)
        }

        if let decoded = try? JSONDecoder().decode(DetailEnvelope.self, from: data) {
            return (decoded.readableMessage, decoded.detail?.status)
        }

        return (String(data: data, encoding: .utf8) ?? "Unreadable error body.", nil)
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
