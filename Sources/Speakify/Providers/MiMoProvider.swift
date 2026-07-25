import Foundation

struct MiMoProvider: TTSProvider {
    let id = "mimo"
    let displayName = "Xiaomi MiMo"

    let capabilities = TTSProviderCapabilities(
        outputFormats: ["mp3", "wav"],
        defaultOutputFormat: "mp3",
        defaultModelID: "mimo-v2.5-tts",
        reportsQuota: false,
        providesSubtitles: true,
        providesCharacterAlignment: false,
        acceptsLanguageHint: false,
        meteredSynthesis: false,
        apiKeyHint: "Create a key at mimo.mi.com; synthesis is currently free of charge."
    )

    private let baseURL = URL(string: "https://api.xiaomimimo.com/v1")!
    private let session: URLSession

    init(session: URLSession = MiMoProvider.makeSession()) {
        self.session = session
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration)
    }

    var fallbackModels: [TTSModel] { Self.models }

    static let models = [
        TTSModel(id: "mimo-v2.5-tts", name: "MiMo TTS v2.5", canDoTextToSpeech: true, servesProVoices: false)
    ]

    static let presetVoices: [TTSVoice] = [
        presetVoice(id: "mimo_default", name: "MiMo Default", gender: nil, locale: nil, language: nil),
        presetVoice(id: "冰糖", name: "冰糖", gender: "female", locale: "zh-CN", language: "Chinese"),
        presetVoice(id: "茉莉", name: "茉莉", gender: "female", locale: "zh-CN", language: "Chinese"),
        presetVoice(id: "苏打", name: "苏打", gender: "male", locale: "zh-CN", language: "Chinese"),
        presetVoice(id: "白桦", name: "白桦", gender: "male", locale: "zh-CN", language: "Chinese"),
        presetVoice(id: "Mia", name: "Mia", gender: "female", locale: "en-US", language: "English"),
        presetVoice(id: "Chloe", name: "Chloe", gender: "female", locale: "en-US", language: "English"),
        presetVoice(id: "Milo", name: "Milo", gender: "male", locale: "en-US", language: "English"),
        presetVoice(id: "Dean", name: "Dean", gender: "male", locale: "en-US", language: "English")
    ]

    func fetchModels(apiKey: String) async throws -> [TTSModel] {
        Self.models
    }

    func fetchVoiceCatalog(apiKey: String) async throws -> TTSVoiceCatalog {
        TTSVoiceCatalog(publicVoices: Self.presetVoices, accountVoices: [])
    }

    func fetchQuota(apiKey: String) async throws -> TTSQuota? {
        nil
    }

    func synthesize(request speechRequest: SpeechRequest, apiKey: String) async throws -> GeneratedSpeech {
        guard apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw TTSProviderError.missingAPIKey
        }

        var urlRequest = URLRequest(url: baseURL.appending(path: "/chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(MiMoSpeechBody(from: speechRequest))

        let (data, response) = try await session.data(for: urlRequest)
        try validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(MiMoCompletionResponse.self, from: data)
        guard let encodedAudio = decoded.choices.first?.message.audio?.data,
              let audioData = Data(base64Encoded: encodedAudio),
              audioData.isEmpty == false else {
            throw TTSProviderError.invalidResponse
        }

        return GeneratedSpeech(
            audioData: audioData,
            fileExtension: speechRequest.outputFormat == "mp3" ? "mp3" : "wav",
            request: speechRequest,
            alignment: nil
        )
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSProviderError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let failure = MiMoErrorMessage.parse(from: data)
            throw TTSProviderError.httpStatus(
                status: httpResponse.statusCode,
                message: failure.message,
                code: failure.code
            )
        }
    }
}

private struct MiMoSpeechBody: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct Audio: Encodable {
        let format: String
        let voice: String
    }

    let model: String
    let messages: [Message]
    let audio: Audio
    let stream: Bool

    init(from request: SpeechRequest) {
        model = request.modelID
        messages = [Message(role: "assistant", content: request.text)]
        audio = Audio(format: request.outputFormat, voice: request.voice.id)
        stream = false
    }
}

private struct MiMoCompletionResponse: Decodable {
    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let audio: Audio?
    }

    struct Audio: Decodable {
        let data: String
    }

    let choices: [Choice]
}

private enum MiMoErrorMessage {
    static func parse(from data: Data) -> (message: String, code: String?) {
        guard data.isEmpty == false else {
            return ("No error body returned.", nil)
        }

        guard let decoded = try? JSONDecoder().decode(Envelope.self, from: data),
              let error = decoded.error else {
            return (String(data: data, encoding: .utf8) ?? "Unreadable error body.", nil)
        }

        let details = [error.message, error.param]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
        let message = details.isEmpty ? "Unknown service error." : details.joined(separator: ": ")
        let code = [error.type, error.code]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .first
        return (message, code)
    }

    private struct Envelope: Decodable {
        let error: Failure?
    }

    private struct Failure: Decodable {
        let message: String?
        let param: String?
        let code: String?
        let type: String?
    }
}

private func presetVoice(
    id: String,
    name: String,
    gender: String?,
    locale: String?,
    language: String?
) -> TTSVoice {
    TTSVoice(
        id: id,
        name: name,
        category: "preset",
        detail: nil,
        previewURL: nil,
        gender: gender,
        accent: nil,
        locale: locale,
        language: language
    )
}
