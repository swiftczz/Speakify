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

    /// A quota failure whose prose mentions "not available" must not be mistaken for
    /// a dead voice, which would drop a working voice from the picker.
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

    private func synthesisRequestBody(languageCode: String?) async throws -> [String: Any] {
        MockURLProtocol.responder = { _ in
            let payload = ["audio_base64": Data([0x01, 0x02, 0x03]).base64EncodedString()]
            return (Self.httpResponse(statusCode: 200), try JSONSerialization.data(withJSONObject: payload))
        }

        let provider = ElevenLabsProvider(session: MockURLProtocol.makeSession())
        _ = try await provider.synthesize(
            request: Self.makeRequest(languageCode: languageCode),
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

    private static func makeRequest(languageCode: String?) -> SpeechRequest {
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
            modelID: "eleven_v3",
            outputFormat: "mp3_44100_128",
            languageCode: languageCode,
            voiceSettings: VoiceSettings()
        )
    }
}

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responder: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequestBody: Data?

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func reset() {
        responder = nil
        lastRequestBody = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
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
    /// URLProtocol hands the body over as a stream rather than on `httpBody`.
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
