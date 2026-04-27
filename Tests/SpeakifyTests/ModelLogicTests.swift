import Foundation
import SwiftData
import XCTest
@testable import Speakify

final class ModelLogicTests: XCTestCase {
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
        let schema = Schema([SpeechHistoryRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let record = SpeechHistoryRecord(
            title: "Practice listening every morning.",
            voiceName: "Adam",
            voiceID: "adam-id",
            modelID: "eleven_v3",
            outputFormat: "mp3_44100_128",
            duration: 4,
            requestKey: "practice-adam"
        )
        context.insert(record)
        try context.save()

        let records = try context.fetch(FetchDescriptor<SpeechHistoryRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.voiceName, "Adam")
        XCTAssertEqual(records.first?.durationText, "0:04")
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
        let service = AudioPlaybackService()

        let duration = try service.play(data: audioData)
        try await Task.sleep(for: .milliseconds(350))
        let currentTime = service.currentTime
        service.stop()

        XCTAssertEqual(duration, 1.25, accuracy: 0.05)
        XCTAssertGreaterThan(currentTime, 0.1)
        XCTAssertLessThan(currentTime, duration)
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
        data.appendLittleEndian(36 + dataSize)
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
