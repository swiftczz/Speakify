import Foundation
import XCTest
@testable import Speakify

final class MiMoProviderTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testSynthesizeSendsOpenAICompatibleBody() async throws {
        MockURLProtocol.responder = { _ in
            (Self.httpResponse(statusCode: 200), try Self.successPayload(audio: Data([0x01, 0x02])))
        }

        let provider = MiMoProvider(session: MockURLProtocol.makeSession())
        _ = try await provider.synthesize(request: Self.makeRequest(), apiKey: "test-key")

        let body = try XCTUnwrap(MockURLProtocol.lastRequestBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(json["model"] as? String, "mimo-v2.5-tts")
        XCTAssertEqual(json["stream"] as? Bool, false)

        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?["role"] as? String, "assistant")
        XCTAssertEqual(messages.first?["content"] as? String, "你好，世界")

        let audio = try XCTUnwrap(json["audio"] as? [String: Any])
        XCTAssertEqual(audio["format"] as? String, "mp3")
        XCTAssertEqual(audio["voice"] as? String, "冰糖")
    }

    func testSynthesizeDecodesBase64AudioWithoutAlignment() async throws {
        let audioBytes = Data([0x52, 0x49, 0x46, 0x46, 0x00])
        MockURLProtocol.responder = { _ in
            (Self.httpResponse(statusCode: 200), try Self.successPayload(audio: audioBytes))
        }

        let provider = MiMoProvider(session: MockURLProtocol.makeSession())
        let speech = try await provider.synthesize(request: Self.makeRequest(), apiKey: "test-key")

        XCTAssertEqual(speech.audioData, audioBytes)
        XCTAssertEqual(speech.fileExtension, "mp3")
        XCTAssertNil(speech.alignment, "MiMo returns no character timing; Speakify estimates SRT cue timing.")
    }

    func testSynthesizeSurfacesServiceErrorDetailAndType() async throws {
        MockURLProtocol.responder = { _ in
            let payload: [String: Any] = [
                "error": [
                    "message": "Param Incorrect",
                    "param": "Unknown voice: nope. Available voices: [mimo_default]",
                    "code": "400",
                    "type": "invalid_request"
                ]
            ]
            return (Self.httpResponse(statusCode: 400), try JSONSerialization.data(withJSONObject: payload))
        }

        let provider = MiMoProvider(session: MockURLProtocol.makeSession())
        do {
            _ = try await provider.synthesize(request: Self.makeRequest(), apiKey: "test-key")
            XCTFail("Expected synthesis to throw.")
        } catch {
            guard case let TTSProviderError.httpStatus(status, message, code) = error else {
                return XCTFail("Expected an HTTP status error, got \(error).")
            }
            XCTAssertEqual(status, 400)
            XCTAssertTrue(message.contains("Unknown voice: nope"))
            XCTAssertEqual(code, "invalid_request")
        }
    }

    /// The service rejects unknown voices, so the shipped roster must match the
    /// list its own error message enumerates.
    func testPresetVoicesMatchServiceRoster() {
        let serviceRoster = ["mimo_default", "冰糖", "茉莉", "苏打", "白桦", "Mia", "Chloe", "Milo", "Dean"]
        XCTAssertEqual(MiMoProvider.presetVoices.map(\.id), serviceRoster)
    }

    func testCatalogAnswersLocallyAndQuotaIsUnsupported() async throws {
        let provider = MiMoProvider(session: MockURLProtocol.makeSession())

        let models = try await provider.fetchModels(apiKey: "")
        let catalog = try await provider.fetchVoiceCatalog(apiKey: "   ")
        let quota = try await provider.fetchQuota(apiKey: "")

        XCTAssertEqual(models.map(\.id), ["mimo-v2.5-tts"])
        XCTAssertEqual(catalog.publicVoices, MiMoProvider.presetVoices)
        XCTAssertTrue(catalog.accountVoices.isEmpty)
        XCTAssertNil(quota)
        XCTAssertNil(MockURLProtocol.lastRequest, "The fixed catalog must not hit the network.")
    }

    func testMP3IsDefaultAndSubtitleExportUsesEstimatedTiming() {
        let capabilities = MiMoProvider().capabilities

        XCTAssertEqual(capabilities.outputFormats, ["mp3", "wav"])
        XCTAssertEqual(capabilities.defaultOutputFormat, "mp3")
        XCTAssertTrue(capabilities.providesSubtitles)
        XCTAssertFalse(capabilities.providesCharacterAlignment)
    }

    func testMissingAPIKeyFailsBeforeAnyRequest() async {
        let provider = MiMoProvider(session: MockURLProtocol.makeSession())
        do {
            _ = try await provider.synthesize(request: Self.makeRequest(), apiKey: "   ")
            XCTFail("Expected synthesis to throw.")
        } catch {
            XCTAssertTrue(error is TTSProviderError)
        }
    }

    private static func successPayload(audio: Data) throws -> Data {
        let payload: [String: Any] = [
            "choices": [
                [
                    "message": [
                        "role": "assistant",
                        "audio": ["data": audio.base64EncodedString()]
                    ]
                ]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    private static func httpResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.xiaomimimo.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    private static func makeRequest() -> SpeechRequest {
        SpeechRequest(
            text: "你好，世界",
            voice: MiMoProvider.presetVoices.first { $0.id == "冰糖" }!,
            modelID: "mimo-v2.5-tts",
            outputFormat: "mp3",
            languageCode: nil,
            voiceSettings: VoiceSettings()
        )
    }
}

/// Hits the real MiMo endpoint only when explicitly opted in. Requiring a second
/// switch prevents an exported developer key from turning every unit-test run into
/// a billable, network-dependent integration test.
final class MiMoProviderLiveTests: XCTestCase {
    @MainActor
    func testLiveSynthesisReturnsPlayableMP3() async throws {
        let apiKey = ProcessInfo.processInfo.environment["MIMO_API_KEY"] ?? ""
        let runsLiveTests = ProcessInfo.processInfo.environment["RUN_LIVE_TTS_TESTS"] == "1"
        try XCTSkipUnless(
            runsLiveTests,
            "Set RUN_LIVE_TTS_TESTS=1 to enable live provider tests."
        )
        try XCTSkipIf(apiKey.isEmpty, "MIMO_API_KEY not set; skipping live synthesis test.")

        let provider = MiMoProvider()
        let request = SpeechRequest(
            text: "Speakify integration check.",
            voice: MiMoProvider.presetVoices.first { $0.id == "Chloe" }!,
            modelID: "mimo-v2.5-tts",
            outputFormat: "mp3",
            languageCode: nil,
            voiceSettings: VoiceSettings()
        )

        let speech = try await provider.synthesize(request: request, apiKey: apiKey)
        let duration = try AudioPlaybackService().duration(data: speech.audioData)

        XCTAssertEqual(speech.fileExtension, "mp3")
        XCTAssertGreaterThan(speech.audioData.count, 1_000)
        XCTAssertGreaterThan(duration, 0)
    }
}
