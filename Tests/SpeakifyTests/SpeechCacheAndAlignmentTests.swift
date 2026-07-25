import Foundation
import XCTest
@testable import Speakify

final class SpeechAlignmentValidationTests: XCTestCase {
    func testAcceptsForwardMovingTimestamps() {
        XCTAssertTrue(Self.alignment(starts: [0, 0.2, 0.4], ends: [0.2, 0.4, 0.6]).isValid)
    }

    func testRejectsNonFiniteTimestamps() {
        XCTAssertFalse(Self.alignment(starts: [0, .nan, 0.4], ends: [0.2, 0.4, 0.6]).isValid)
        XCTAssertFalse(Self.alignment(starts: [0, 0.2, 0.4], ends: [0.2, .infinity, 0.6]).isValid)
    }

    func testRejectsNegativeTimestamps() {
        XCTAssertFalse(Self.alignment(starts: [-0.1, 0.2, 0.4], ends: [0.2, 0.4, 0.6]).isValid)
    }

    func testRejectsCuesThatEndBeforeTheyStart() {
        XCTAssertFalse(Self.alignment(starts: [0, 0.5, 0.6], ends: [0.2, 0.3, 0.8]).isValid)
    }

    func testRejectsTimestampsThatGoBackwards() {
        XCTAssertFalse(Self.alignment(starts: [0, 0.4, 0.2], ends: [0.4, 0.6, 0.8]).isValid)
    }

    func testSubtitleFormatterRefusesInvalidTimestamps() {
        XCTAssertThrowsError(
            try SubtitleFormatter.srt(from: Self.alignment(starts: [0, .nan, 0.4], ends: [0.2, 0.4, 0.6]))
        )
    }

    private static func alignment(starts: [TimeInterval], ends: [TimeInterval]) -> SpeechAlignment {
        SpeechAlignment(
            characters: ["a", "b", "c"],
            characterStartTimesSeconds: starts,
            characterEndTimesSeconds: ends
        )
    }
}

final class SpeechFileNameUnicodeTests: XCTestCase {
    func testKeepsChineseCharactersInTheFileName() {
        let fileName = FileNameFormatter.speechFileName(
            text: "今天天气很好，我们去散步吧。",
            voiceName: "冰糖",
            fileExtension: "mp3",
            date: Date(timeIntervalSince1970: 1_712_345_678)
        )

        XCTAssertTrue(fileName.contains("冰糖"))
        XCTAssertTrue(fileName.contains("今天天气很好"))
        XCTAssertFalse(fileName.contains("，"))
        XCTAssertTrue(fileName.hasSuffix(".mp3"))
    }

    func testStaysInsideTheFileSystemByteLimit() {
        let fileName = FileNameFormatter.speechFileName(
            text: String(repeating: "语音合成", count: 60),
            voiceName: "茉莉",
            fileExtension: "mp3"
        )

        XCTAssertLessThanOrEqual(fileName.utf8.count, 255)
    }
}

final class SpeechCacheStoreTests: XCTestCase {
    func testStoresAndReadsBackGeneratedSpeech() async throws {
        let directory = try makeTemporaryDirectory()
        let store = SpeechCacheStore(retention: 3_600, sizeLimit: 10 * 1_024 * 1_024, directoryURL: directory)
        let request = Self.request()
        let speech = GeneratedSpeech(
            audioData: Data([0x01, 0x02, 0x03]),
            fileExtension: "mp3",
            request: request,
            alignment: SpeechAlignment(
                characters: ["a"],
                characterStartTimesSeconds: [0],
                characterEndTimesSeconds: [1]
            )
        )

        await store.store(speech, key: "key-1")
        let cached = await store.speech(for: request, key: "key-1")

        XCTAssertEqual(cached?.audioData, speech.audioData)
        XCTAssertEqual(cached?.alignment?.characters, ["a"])
    }

    func testDropsEntriesPastRetention() async throws {
        let directory = try makeTemporaryDirectory()
        let store = SpeechCacheStore(retention: 60, sizeLimit: 10 * 1_024 * 1_024, directoryURL: directory)
        let request = Self.request()
        await store.store(
            GeneratedSpeech(audioData: Data([0x01]), fileExtension: "mp3", request: request, alignment: nil),
            key: "key-1"
        )

        let audioURL = directory.appending(path: "key-1.mp3")
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3_600)],
            ofItemAtPath: audioURL.path(percentEncoded: false)
        )

        let cached = await store.speech(for: request, key: "key-1")

        XCTAssertNil(cached)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path(percentEncoded: false)))
    }

    private static func request() -> SpeechRequest {
        SpeechRequest(
            text: "Hello",
            voice: TTSVoice(
                id: "voice",
                name: "Voice",
                category: nil,
                detail: nil,
                previewURL: nil,
                gender: nil,
                accent: nil,
                locale: nil,
                language: nil
            ),
            modelID: "model",
            outputFormat: "mp3_44100_128",
            languageCode: nil,
            voiceSettings: VoiceSettings()
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "speakify-cache-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}
