import Foundation
import XCTest
@testable import Speakify

final class ModelLogicTests: XCTestCase {
    func testAppSettingsPersistsSelectedAppLanguage() {
        let suiteName = "SpeakifyTests.AppLanguage.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstSettings = AppSettings(defaults: defaults)
        XCTAssertEqual(firstSettings.appLanguage, .system)

        firstSettings.appLanguage = .simplifiedChinese
        let restoredSettings = AppSettings(defaults: defaults)

        XCTAssertEqual(restoredSettings.appLanguage, .simplifiedChinese)
        XCTAssertEqual(restoredSettings.appLocale.identifier, "zh-Hans")
    }

    func testAppSettingsFallsBackToSystemForUnknownAppLanguage() {
        let suiteName = "SpeakifyTests.UnknownAppLanguage.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("unsupported-language", forKey: "appLanguage")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.appLanguage, .system)
    }

    func testAppSettingsPersistsAPIKeyUnderProviderScope() {
        let suiteName = "SpeakifyTests.APIKey.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstSettings = AppSettings(defaults: defaults)
        firstSettings.apiKey = "test-api-key"

        let restoredSettings = AppSettings(defaults: defaults)

        XCTAssertEqual(restoredSettings.apiKey, "test-api-key")
        XCTAssertEqual(defaults.string(forKey: "apiKey.elevenlabs"), "test-api-key")
    }

    func testAppSettingsMigratesLegacyFlatValuesToElevenLabsScope() {
        let suiteName = "SpeakifyTests.Migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("legacy-key", forKey: "apiKey")
        defaults.set("eleven_flash_v2_5", forKey: "modelID")
        defaults.set("wav_44100", forKey: "outputFormat")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.apiKey, "legacy-key")
        XCTAssertEqual(settings.modelID, "eleven_flash_v2_5")
        XCTAssertEqual(settings.outputFormat, "wav_44100")
        XCTAssertNil(defaults.string(forKey: "apiKey"), "The flat legacy key should be removed after migration.")
    }

    func testAppSettingsKeepsPerProviderValuesAcrossSwitches() {
        let suiteName = "SpeakifyTests.ProviderSwitch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.apiKey = "eleven-key"

        settings.providerID = "mimo"
        XCTAssertEqual(settings.apiKey, "", "MiMo starts without a key of its own.")
        XCTAssertEqual(settings.modelID, "mimo-v2.5-tts")
        XCTAssertEqual(settings.outputFormat, "mp3")
        settings.apiKey = "mimo-key"

        settings.providerID = "elevenlabs"
        XCTAssertEqual(settings.apiKey, "eleven-key")
        XCTAssertEqual(settings.modelID, "eleven_v3")
        XCTAssertEqual(settings.outputFormat, "mp3_44100_128")
        XCTAssertEqual(settings.apiKey(for: "mimo"), "mimo-key")
    }

    func testAppSettingsMigratesExistingMiMoWAVDefaultToMP3OnlyOnce() {
        let suiteName = "SpeakifyTests.MiMoFormatMigration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("mimo", forKey: "providerID")
        defaults.set("wav", forKey: "outputFormat.mimo")

        let migratedSettings = AppSettings(defaults: defaults)
        XCTAssertEqual(migratedSettings.outputFormat, "mp3")

        migratedSettings.outputFormat = "wav"
        let restoredSettings = AppSettings(defaults: defaults)
        XCTAssertEqual(restoredSettings.outputFormat, "wav", "A later explicit WAV choice must be preserved.")
    }

    func testAppSettingsRejectsUnknownStoredProvider() {
        let suiteName = "SpeakifyTests.UnknownProvider.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("discontinued-provider", forKey: "providerID")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.providerID, "elevenlabs")
    }

    func testEstimatedCreditCostUsesFlashDiscount() {
        XCTAssertEqual(
            SpeechViewModel.estimatedCreditCost(
                characterCount: 1_849,
                modelID: "eleven_flash_v2_5"
            ),
            925
        )
    }

    func testEstimatedCreditCostUsesFullRateForElevenV3() {
        XCTAssertEqual(
            SpeechViewModel.estimatedCreditCost(
                characterCount: 1_849,
                modelID: "eleven_v3"
            ),
            1_849
        )
    }

    func testAppSettingsPersistsDraftTextAcrossInstances() {
        let suiteName = "SpeakifyTests.DraftText.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstSettings = AppSettings(defaults: defaults)
        firstSettings.draftText = "My Cousin the Soup Star"

        let restoredSettings = AppSettings(defaults: defaults)

        XCTAssertEqual(restoredSettings.draftText, "My Cousin the Soup Star")
    }

    func testSubtitleFormatterBuildsAlignedSRTCues() throws {
        let characters = Array("Hello world. Next line!").map(String.init)
        let alignment = SpeechAlignment(
            characters: characters,
            characterStartTimesSeconds: characters.indices.map { Double($0) * 0.1 },
            characterEndTimesSeconds: characters.indices.map { Double($0 + 1) * 0.1 }
        )

        let subtitle = try SubtitleFormatter.srt(from: alignment)

        XCTAssertTrue(subtitle.contains("00:00:00,000 --> 00:00:01,200"))
        XCTAssertTrue(subtitle.contains("Hello world."))
        XCTAssertTrue(subtitle.contains("00:00:01,300 --> 00:00:02,300"))
        XCTAssertTrue(subtitle.contains("Next line!"))
    }

    func testSubtitleFormatterRejectsMismatchedAlignment() {
        let alignment = SpeechAlignment(
            characters: ["H", "i"],
            characterStartTimesSeconds: [0],
            characterEndTimesSeconds: [0.1, 0.2]
        )

        XCTAssertThrowsError(try SubtitleFormatter.srt(from: alignment))
    }

    func testSubtitleFormatterKeepsLongSentenceInOneCue() throws {
        let text = "The group chats turned aggressive in the other sense: classmates going after each other over the last few internships, everyone exceedingly certain the sky was falling, the anxiety plainly excessive at 3 a.m."
        let characters = Array(text).map(String.init)
        let alignment = SpeechAlignment(
            characters: characters,
            characterStartTimesSeconds: characters.indices.map { Double($0) * 0.15 },
            characterEndTimesSeconds: characters.indices.map { Double($0 + 1) * 0.15 }
        )

        let subtitle = try SubtitleFormatter.srt(from: alignment)

        XCTAssertEqual(subtitle.components(separatedBy: " --> ").count - 1, 1)
        XCTAssertTrue(subtitle.contains("The group chats turned aggressive"))
        XCTAssertTrue(subtitle.contains("excessive at 3 a.m."))
    }

    func testSubtitleFormatterEstimatesChineseSentenceTimingFromAudioDuration() throws {
        let subtitle = try SubtitleFormatter.estimatedSRT(
            text: "你好。世界！",
            duration: 6
        )

        XCTAssertEqual(subtitle.components(separatedBy: " --> ").count - 1, 2)
        XCTAssertTrue(subtitle.contains("00:00:00,000 --> 00:00:03,000\n你好。"))
        XCTAssertTrue(subtitle.contains("00:00:03,000 --> 00:00:06,000\n世界！"))
    }

    func testSpeechFileNameSanitizesTextAndVoice() {
        let date = Date(timeIntervalSince1970: 1_712_345_678)
        let fileName = FileNameFormatter.speechFileName(
            text: "Hello, world!\nThis should not be included.",
            voiceName: "Aria / English",
            fileExtension: "mp3",
            date: date
        )

        XCTAssertTrue(fileName.hasSuffix(".mp3"))
        XCTAssertFalse(fileName.contains("/"))
        XCTAssertFalse(fileName.contains(","))
        XCTAssertFalse(fileName.contains("\n"))
        XCTAssertLessThanOrEqual(fileName.count, 84)
    }

    func testSpeechFileNameUsesCompactTimestampAndPrimaryVoiceName() {
        let fileName = FileNameFormatter.speechFileName(
            text: "My Cousin the Soup Star\nThe rest is not part of the name.",
            voiceName: "Adam - Dominant, Firm",
            fileExtension: "mp3",
            date: Date(timeIntervalSince1970: 1_712_345_678)
        )

        XCTAssertNotNil(fileName.range(
            of: #"^\d{14}-Adam-My-Cousin-the-Soup-Star\.mp3$"#,
            options: .regularExpression
        ))
        XCTAssertFalse(fileName.contains("Dominant"))
        XCTAssertFalse(fileName.contains("---"))
    }

    func testSpeechFileNameFallsBackForEmptyText() {
        let date = Date(timeIntervalSince1970: 0)
        let fileName = FileNameFormatter.speechFileName(
            text: "",
            voiceName: "Adam",
            fileExtension: "wav",
            date: date
        )

        XCTAssertTrue(fileName.hasSuffix("-Adam-speech.wav"))
    }

    func testVoiceSubtitleSkipsEmptyParts() {
        let voice = TTSVoice(
            id: "voice-id",
            name: "Aria",
            category: "premade",
            detail: "",
            previewURL: nil,
            gender: "female",
            accent: "American",
            locale: "en-US",
            language: "English"
        )

        XCTAssertTrue(voice.subtitle.contains("Female"))
        XCTAssertTrue(voice.subtitle.contains("American"))
        XCTAssertTrue(voice.subtitle.contains("premade"))
        XCTAssertEqual(voice.displayName, "Aria · Female · US")
    }

    func testHistoryPreviewAndDurationFormatting() {
        let item = SpeechHistoryRecord(
            title: "The future belongs to those who listen carefully every morning.",
            voiceName: "Jessica",
            voiceID: "voice-id",
            modelID: "eleven_flash_v2_5",
            outputFormat: "mp3_44100_128",
            duration: 72,
            createdAt: Date(timeIntervalSince1970: 0),
            requestKey: "request-key"
        )

        XCTAssertEqual(item.voiceName, "Jessica")
        XCTAssertEqual(item.durationText, "1:12")
        XCTAssertTrue(item.preview.hasSuffix("..."))
        XCTAssertLessThanOrEqual(item.preview.count, 37)
    }

    @MainActor
    func testSwiftDataHistoryRecordPersistsInModelContext() throws {
        let summary = try ModelLogicTestSupport.persistHistoryRecordSummary()

        XCTAssertEqual(summary.count, 1)
        XCTAssertEqual(summary.voiceName, "Adam")
        XCTAssertEqual(summary.durationText, "0:04")
    }

    @MainActor
    func testAudioPlaybackServiceReadsGeneratedAudioDuration() throws {
        let audioData = Self.silentWAVData(duration: 1.25)
        let service = AudioPlaybackService()

        let duration = try service.duration(data: audioData)

        XCTAssertEqual(duration, 1.25, accuracy: 0.05)
    }

    @MainActor
    func testAudioPlaybackServiceCurrentTimeAdvancesWhilePlaying() async throws {
        let audioData = Self.silentWAVData(duration: 1.25)
        let sample = try await ModelLogicTestSupport.samplePlaybackProgress(for: audioData)

        XCTAssertEqual(sample.duration, 1.25, accuracy: 0.05)
        XCTAssertGreaterThan(sample.currentTime, 0.01)
        XCTAssertLessThanOrEqual(sample.currentTime, sample.duration)
    }

    /// At 2x, three seconds of audio reaches the 2s mark after ~1s of wall time.
    /// At 1x it would need 2s, so this can only pass when the rate is really applied
    /// (`enableRate` must be set before `prepareToPlay()` or rate changes are ignored).
    @MainActor
    func testAudioPlaybackServiceAppliesFasterPlaybackRate() async throws {
        let service = AudioPlaybackService()
        _ = try service.play(data: Self.silentWAVData(duration: 3.0), rate: 2.0, fileExtension: "wav")
        defer { service.stop() }

        var reachedTwoSeconds = false
        for _ in 0..<15 {
            try await Task.sleep(for: .milliseconds(100))
            if service.currentTime > 2.0 {
                reachedTwoSeconds = true
                break
            }
        }

        XCTAssertTrue(reachedTwoSeconds, "Playback did not run at 2x; reached only \(service.currentTime)s.")
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
        let riffChunkSize = UInt32(36) + dataSize

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.appendLittleEndian(riffChunkSize)
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(channels)
        data.appendLittleEndian(sampleRate)
        data.appendLittleEndian(byteRate)
        data.appendLittleEndian(blockAlign)
        data.appendLittleEndian(bitsPerSample)
        data.append(contentsOf: "data".utf8)
        data.appendLittleEndian(dataSize)
        data.append(Data(repeating: 0, count: Int(dataSize)))
        return data
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
