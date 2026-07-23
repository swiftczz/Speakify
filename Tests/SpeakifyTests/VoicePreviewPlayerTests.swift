import Foundation
import XCTest
@testable import Speakify

final class VoicePreviewPlayerTests: XCTestCase {
    @MainActor
    func testProviderWithoutPreviewURLSynthesizesAndCachesShortPreview() async throws {
        let recorder = PreviewRequestRecorder()
        let provider = PreviewTestProvider(
            recorder: recorder,
            audioData: Self.silentWAVData(duration: 0.8)
        )
        let voice = TTSVoice(
            id: "voice-without-sample",
            name: "测试音色",
            category: "preset",
            detail: nil,
            previewURL: nil,
            gender: "female",
            accent: nil,
            locale: "zh-CN",
            language: "Chinese"
        )
        let player = VoicePreviewPlayer(hoverDelay: .zero)
        let configuration = VoicePreviewConfiguration(
            provider: provider,
            modelID: "preview-model",
            apiKey: "provider-key"
        )
        defer { player.stop() }

        player.beginPreview(for: voice, configuration: configuration)
        try await waitUntilPreviewStarts(player)

        let firstRequest = await recorder.lastRequest
        let firstAPIKey = await recorder.lastAPIKey
        XCTAssertEqual(firstRequest?.text, "你好，很高兴认识你。")
        XCTAssertEqual(firstRequest?.voice.id, voice.id)
        XCTAssertEqual(firstRequest?.modelID, "preview-model")
        XCTAssertEqual(firstAPIKey, "provider-key")

        player.stop()
        player.beginPreview(for: voice, configuration: configuration)
        try await waitUntilPreviewStarts(player)

        let requestCount = await recorder.requestCount
        XCTAssertEqual(requestCount, 1, "Repeated hover previews should reuse the in-memory audio cache.")
    }

    /// Synthesizing a preview costs credits on a metered service, so hovering must
    /// not trigger one — only an explicit click may.
    @MainActor
    func testMeteredPreviewWithoutSampleWaitsForAClick() async throws {
        let recorder = PreviewRequestRecorder()
        let provider = PreviewTestProvider(
            meteredSynthesis: true,
            recorder: recorder,
            audioData: Self.silentWAVData(duration: 0.8)
        )
        let voice = TTSVoice(
            id: "metered-voice",
            name: "Metered",
            category: "premade",
            detail: nil,
            previewURL: nil,
            gender: nil,
            accent: nil,
            locale: "en-US",
            language: "English"
        )
        let player = VoicePreviewPlayer(hoverDelay: .zero)
        let configuration = VoicePreviewConfiguration(
            provider: provider,
            modelID: "preview-model",
            apiKey: "provider-key"
        )
        defer { player.stop() }

        player.beginPreview(for: voice, configuration: configuration)
        try await Task.sleep(for: .milliseconds(120))

        let hoverRequestCount = await recorder.requestCount
        XCTAssertEqual(hoverRequestCount, 0, "Hover must not spend credits on a metered preview.")
        XCTAssertNil(player.activeVoiceID)

        player.togglePreview(for: voice, configuration: configuration)
        try await waitUntilPreviewStarts(player)

        let clickRequestCount = await recorder.requestCount
        XCTAssertEqual(clickRequestCount, 1)
    }

    /// Two accounts can hold different voices under the same ID, so a preview cached
    /// for one must never be replayed for the other.
    func testPreviewCacheKeySeparatesAccounts() {
        let provider = PreviewTestProvider(recorder: PreviewRequestRecorder(), audioData: Data())
        let first = VoicePreviewConfiguration(provider: provider, modelID: "m", apiKey: "key-one")
        let second = VoicePreviewConfiguration(provider: provider, modelID: "m", apiKey: "key-two")

        XCTAssertNotEqual(first.accountFingerprint, second.accountFingerprint)
        XCTAssertFalse(first.accountFingerprint.contains("key-one"))
        XCTAssertEqual(
            VoicePreviewConfiguration(provider: provider, modelID: "m", apiKey: "").accountFingerprint,
            "anonymous"
        )
    }

    @MainActor
    private func waitUntilPreviewStarts(_ player: VoicePreviewPlayer) async throws {
        for _ in 0..<50 {
            if player.isPlaying {
                return
            }
            if let errorMessage = player.errorMessage {
                XCTFail("Preview failed: \(errorMessage)")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for preview playback.")
    }

    private static func silentWAVData(duration: TimeInterval) -> Data {
        let sampleRate: UInt32 = 8_000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let bytesPerSample = UInt32(bitsPerSample / 8)
        let sampleCount = UInt32(duration * Double(sampleRate))
        let dataSize = sampleCount * UInt32(channels) * bytesPerSample
        let byteRate = sampleRate * UInt32(channels) * bytesPerSample
        let blockAlign = channels * bitsPerSample / 8

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        appendLittleEndian(UInt32(36) + dataSize, to: &data)
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        appendLittleEndian(UInt32(16), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(channels, to: &data)
        appendLittleEndian(sampleRate, to: &data)
        appendLittleEndian(byteRate, to: &data)
        appendLittleEndian(blockAlign, to: &data)
        appendLittleEndian(bitsPerSample, to: &data)
        data.append(contentsOf: "data".utf8)
        appendLittleEndian(dataSize, to: &data)
        data.append(Data(repeating: 0, count: Int(dataSize)))
        return data
    }

    private static func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}

private actor PreviewRequestRecorder {
    private(set) var requestCount = 0
    private(set) var lastRequest: SpeechRequest?
    private(set) var lastAPIKey: String?

    func record(request: SpeechRequest, apiKey: String) {
        requestCount += 1
        lastRequest = request
        lastAPIKey = apiKey
    }
}

private struct PreviewTestProvider: TTSProvider {
    let id = "preview-test"
    let displayName = "Preview Test"
    var meteredSynthesis = false
    var capabilities: TTSProviderCapabilities {
        TTSProviderCapabilities(
            outputFormats: ["wav"],
            defaultOutputFormat: "wav",
            defaultModelID: "preview-model",
            reportsQuota: false,
            providesSubtitles: false,
            providesCharacterAlignment: false,
            acceptsLanguageHint: false,
            meteredSynthesis: meteredSynthesis,
            apiKeyHint: ""
        )
    }
    let fallbackModels = [
        TTSModel(
            id: "preview-model",
            name: "Preview Model",
            canDoTextToSpeech: true,
            servesProVoices: false
        )
    ]
    let recorder: PreviewRequestRecorder
    let audioData: Data

    func fetchModels(apiKey: String) async throws -> [TTSModel] {
        fallbackModels
    }

    func fetchVoiceCatalog(apiKey: String) async throws -> TTSVoiceCatalog {
        TTSVoiceCatalog(publicVoices: [], accountVoices: [])
    }

    func fetchQuota(apiKey: String) async throws -> TTSQuota? {
        nil
    }

    func synthesize(request: SpeechRequest, apiKey: String) async throws -> GeneratedSpeech {
        await recorder.record(request: request, apiKey: apiKey)
        return GeneratedSpeech(
            audioData: audioData,
            fileExtension: "wav",
            request: request,
            alignment: nil
        )
    }
}
