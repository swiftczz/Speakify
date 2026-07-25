import Foundation
import XCTest
@testable import Speakify

final class ElevenLabsProviderTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testSynthesizeOmitsLanguageCodeWhenAutoDetecting() async throws {
        let body = try await synthesisRequestBody(languageCode: nil)

        XCTAssertNil(body["language_code"])
        XCTAssertEqual(body["model_id"] as? String, "eleven_v3")
        XCTAssertEqual(body["text"] as? String, "Hello")
    }

    func testSynthesizeSendsExplicitLanguageCode() async throws {
        let body = try await synthesisRequestBody(languageCode: "zh")

        XCTAssertEqual(body["language_code"] as? String, "zh")
    }

    func testElevenV3OmitsUnsupportedSpeedSetting() async throws {
        let body = try await synthesisRequestBody(
            languageCode: nil,
            modelID: "eleven_v3",
            voiceSettings: VoiceSettings(speed: 1.15)
        )
        let settings = try XCTUnwrap(body["voice_settings"] as? [String: Any])

        XCTAssertNil(settings["speed"])
    }

    func testMultilingualModelSendsAdvancedVoiceSettings() async throws {
        let expected = VoiceSettings(
            stability: 0.3,
            similarityBoost: 0.85,
            style: 0.4,
            speed: 1.15,
            speakerBoost: false
        )
        let body = try await synthesisRequestBody(
            languageCode: "en",
            modelID: "eleven_multilingual_v2",
            voiceSettings: expected
        )
        let settings = try XCTUnwrap(body["voice_settings"] as? [String: Any])

        XCTAssertEqual(settings["stability"] as? Double, expected.stability)
        XCTAssertEqual(settings["similarity_boost"] as? Double, expected.similarityBoost)
        XCTAssertEqual(settings["style"] as? Double, expected.style)
        XCTAssertEqual(settings["speed"] as? Double, expected.speed)
        XCTAssertEqual(settings["use_speaker_boost"] as? Bool, expected.speakerBoost)
    }

    func testQuotaDecodesWhetherOverageIsAvailable() async throws {
        MockURLProtocol.responder = { _ in
            let payload: [String: Any] = [
                "character_count": 8_426,
                "character_limit": 10_000,
                "can_extend_character_limit": true
            ]
            return (Self.httpResponse(statusCode: 200), try JSONSerialization.data(withJSONObject: payload))
        }

        let provider = ElevenLabsProvider(session: MockURLProtocol.makeSession())
        let fetchedQuota = try await provider.fetchQuota(apiKey: "key")
        let quota = try XCTUnwrap(fetchedQuota)

        XCTAssertEqual(quota.remaining, 1_574)
        XCTAssertTrue(quota.canExtendCharacterLimit)
    }

    func testCatalogWithoutAPIKeyLoadsAnonymousPublicVoices() async throws {
        MockURLProtocol.responder = { request in
            guard request.url?.path == "/v1/voices",
                  request.value(forHTTPHeaderField: "xi-api-key") == nil else {
                throw URLError(.userAuthenticationRequired)
            }
            let payload: [String: Any] = [
                "voices": [
                    [
                        "voice_id": "public-voice",
                        "name": "Public Voice",
                        "category": "premade",
                        "labels": ["gender": "female"]
                    ]
                ]
            ]
            return (Self.httpResponse(statusCode: 200), try JSONSerialization.data(withJSONObject: payload))
        }

        let provider = ElevenLabsProvider(session: MockURLProtocol.makeSession())
        let models = try await provider.fetchModels(apiKey: " ")
        let catalog = try await provider.fetchVoiceCatalog(apiKey: "")

        XCTAssertEqual(models.map(\.id), ElevenLabsProvider.supportedModelIDs)
        XCTAssertEqual(catalog.publicVoices.map(\.id), ["public-voice"])
        XCTAssertTrue(catalog.accountVoices.isEmpty)
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.path, "/v1/voices")
    }

    func testCatalogWithAPIKeyMergesPublicAndAccountVoicesWithoutDuplicates() async throws {
        MockURLProtocol.responder = { request in
            let voices: [[String: Any]]
            switch request.url?.path {
            case "/v1/voices":
                guard request.value(forHTTPHeaderField: "xi-api-key") == nil else {
                    throw URLError(.userAuthenticationRequired)
                }
                voices = [
                    [
                        "voice_id": "public-voice",
                        "name": "Public Voice",
                        "category": "premade"
                    ]
                ]
            case "/v2/voices":
                guard request.value(forHTTPHeaderField: "xi-api-key") == "account-key" else {
                    throw URLError(.userAuthenticationRequired)
                }
                voices = [
                    [
                        "voice_id": "public-voice",
                        "name": "Public Voice",
                        "category": "premade"
                    ],
                    [
                        "voice_id": "personal-voice",
                        "name": "My Voice",
                        "category": "cloned",
                        "labels": ["gender": "female"]
                    ]
                ]
            default:
                throw URLError(.badURL)
            }
            let payload: [String: Any] = ["voices": voices]
            return (Self.httpResponse(statusCode: 200), try JSONSerialization.data(withJSONObject: payload))
        }

        let provider = ElevenLabsProvider(session: MockURLProtocol.makeSession())
        let catalog = try await provider.fetchVoiceCatalog(apiKey: " account-key ")

        XCTAssertEqual(catalog.publicVoices.map(\.id), ["public-voice"])
        XCTAssertEqual(catalog.accountVoices.map(\.id), ["personal-voice"])
        XCTAssertEqual(catalog.voices.map(\.id), ["public-voice", "personal-voice"])
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.path, "/v2/voices")
    }

    func testAccountVoicesFollowEveryPage() async throws {
        nonisolated(unsafe) var requestedTokens: [String?] = []
        MockURLProtocol.responder = { request in
            guard request.url?.path == "/v2/voices" else {
                let payload: [String: Any] = ["voices": []]
                return (Self.httpResponse(statusCode: 200), try JSONSerialization.data(withJSONObject: payload))
            }

            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            let token = components?.queryItems?.first { $0.name == "next_page_token" }?.value
            requestedTokens.append(token)

            let payload: [String: Any]
            switch token {
            case nil:
                payload = [
                    "voices": [["voice_id": "page-1", "name": "Page One"]],
                    "has_more": true,
                    "next_page_token": "token-2"
                ]
            case "token-2":
                payload = [
                    "voices": [["voice_id": "page-2", "name": "Page Two"]],
                    "has_more": false
                ]
            default:
                throw URLError(.badURL)
            }
            return (Self.httpResponse(statusCode: 200), try JSONSerialization.data(withJSONObject: payload))
        }

        let provider = ElevenLabsProvider(session: MockURLProtocol.makeSession())
        let catalog = try await provider.fetchVoiceCatalog(apiKey: "account-key")

        XCTAssertEqual(requestedTokens, [nil, "token-2"])
        XCTAssertEqual(catalog.accountVoices.map(\.id).sorted(), ["page-1", "page-2"])
        XCTAssertNil(catalog.accountFailure)
    }

    func testAccountVoiceFailureKeepsPublicVoicesAndReportsTheFailure() async throws {
        MockURLProtocol.responder = { request in
            guard request.url?.path == "/v1/voices" else {
                let payload = ["detail": ["status": "invalid_api_key", "message": "Invalid API key."]]
                return (Self.httpResponse(statusCode: 401), try JSONSerialization.data(withJSONObject: payload))
            }
            let payload: [String: Any] = [
                "voices": [["voice_id": "public-voice", "name": "Public Voice"]]
            ]
            return (Self.httpResponse(statusCode: 200), try JSONSerialization.data(withJSONObject: payload))
        }

        let provider = ElevenLabsProvider(session: MockURLProtocol.makeSession())
        let catalog = try await provider.fetchVoiceCatalog(apiKey: "bad-key")

        XCTAssertEqual(catalog.publicVoices.map(\.id), ["public-voice"])
        XCTAssertTrue(catalog.accountVoices.isEmpty)
        XCTAssertEqual(catalog.accountFailure?.contains("Invalid API key."), true)
    }

    func testAnonymousCatalogFallsBackToBundledVoicesWhenRequestFails() async throws {
        MockURLProtocol.responder = { _ in
            (Self.httpResponse(statusCode: 503), Data())
        }

        let provider = ElevenLabsProvider(session: MockURLProtocol.makeSession())
        let catalog = try await provider.fetchVoiceCatalog(apiKey: "")

        XCTAssertEqual(catalog.publicVoices, ElevenLabsProvider.publicDefaultVoices)
        XCTAssertEqual(catalog.publicVoices.count, 21)
        XCTAssertTrue(catalog.publicVoices.contains { $0.name.hasPrefix("Adam") })
        XCTAssertTrue(catalog.publicVoices.contains { $0.name.hasPrefix("Bella") })
    }

    func testSynthesizeSurfacesServiceErrorMessageAndCode() async throws {
        let error = try await synthesisError(
            statusCode: 401,
            detail: ["status": "invalid_api_key", "message": "Invalid API key."]
        )

        guard case let TTSProviderError.httpStatus(status, message, code) = error else {
            return XCTFail("Expected an HTTP status error, got \(error).")
        }
        XCTAssertEqual(status, 401)
        XCTAssertEqual(message, "Invalid API key.")
        XCTAssertEqual(code, "invalid_api_key")
    }

    func testUnavailableVoiceIsDetectedByCodeNotMessageText() async throws {
        let voiceNotFound = try await synthesisError(
            statusCode: 400,
            detail: ["status": "voice_not_found", "message": "A voice with voice_id was not found."]
        )
        XCTAssertTrue(SpeechViewModel.isUnavailableVoiceError(voiceNotFound))
    }

    func testQuotaErrorMentioningNotAvailableIsNotTreatedAsUnavailableVoice() async throws {
        let quotaExceeded = try await synthesisError(
            statusCode: 401,
            detail: [
                "status": "quota_exceeded",
                "message": "Your quota is spent; this voice_id is not available and does not exist for you."
            ]
        )
        XCTAssertFalse(SpeechViewModel.isUnavailableVoiceError(quotaExceeded))
    }

    private func synthesisError(statusCode: Int, detail: [String: String]) async throws -> Error {
        MockURLProtocol.responder = { _ in
            let payload = ["detail": detail]
            return (Self.httpResponse(statusCode: statusCode), try JSONSerialization.data(withJSONObject: payload))
        }

        let provider = ElevenLabsProvider(session: MockURLProtocol.makeSession())
        do {
            _ = try await provider.synthesize(request: Self.makeRequest(languageCode: nil), apiKey: "key")
        } catch {
            return error
        }
        throw SynthesisDidNotThrow()
    }

    private struct SynthesisDidNotThrow: Error {}

    private func synthesisRequestBody(
        languageCode: String?,
        modelID: String = "eleven_v3",
        voiceSettings: VoiceSettings = VoiceSettings()
    ) async throws -> [String: Any] {
        MockURLProtocol.responder = { _ in
            let payload = ["audio_base64": Data([0x01, 0x02, 0x03]).base64EncodedString()]
            return (Self.httpResponse(statusCode: 200), try JSONSerialization.data(withJSONObject: payload))
        }

        let provider = ElevenLabsProvider(session: MockURLProtocol.makeSession())
        _ = try await provider.synthesize(
            request: Self.makeRequest(
                languageCode: languageCode,
                modelID: modelID,
                voiceSettings: voiceSettings
            ),
            apiKey: "test-key"
        )

        let requestBody = try XCTUnwrap(MockURLProtocol.lastRequestBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
    }

    private static func httpResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.elevenlabs.io")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    private static func makeRequest(
        languageCode: String?,
        modelID: String = "eleven_v3",
        voiceSettings: VoiceSettings = VoiceSettings()
    ) -> SpeechRequest {
        SpeechRequest(
            text: "Hello",
            voice: TTSVoice(
                id: "voice-id",
                name: "Aria",
                category: "premade",
                detail: nil,
                previewURL: nil,
                gender: nil,
                accent: nil,
                locale: nil,
                language: nil
            ),
            modelID: modelID,
            outputFormat: "mp3_44100_128",
            languageCode: languageCode,
            voiceSettings: voiceSettings
        )
    }
}

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responder: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequestBody: Data?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func reset() {
        responder = nil
        lastRequestBody = nil
        lastRequest = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.lastRequest = request
        MockURLProtocol.lastRequestBody = request.readBody()

        guard let responder = MockURLProtocol.responder else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try responder(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension URLRequest {
    func readBody() -> Data? {
        if let httpBody {
            return httpBody
        }
        guard let stream = httpBodyStream else { return nil }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let readCount = stream.read(&buffer, maxLength: buffer.count)
            guard readCount > 0 else { break }
            data.append(buffer, count: readCount)
        }
        return data
    }
}
