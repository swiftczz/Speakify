import Foundation
import SwiftData

@MainActor
enum ModelLogicTestSupport {
    struct PersistedHistorySummary {
        let count: Int
        let voiceName: String?
        let durationText: String?
    }

    struct PlaybackSample {
        let duration: TimeInterval
        let currentTime: TimeInterval
    }

    static func persistHistoryRecordSummary() throws -> PersistedHistorySummary {
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
        return PersistedHistorySummary(
            count: records.count,
            voiceName: records.first?.voiceName,
            durationText: records.first?.durationText
        )
    }

    static func samplePlaybackProgress(
        for audioData: Data,
        rate: Double = 1.0,
        fileExtension: String = "wav"
    ) async throws -> PlaybackSample {
        let service = AudioPlaybackService()
        let duration = try service.play(data: audioData, rate: rate, fileExtension: fileExtension)

        var currentTime: TimeInterval = 0
        for _ in 0..<10 {
            try await Task.sleep(for: .milliseconds(100))
            currentTime = service.currentTime
            if currentTime > 0.01 {
                break
            }
        }
        service.stop()

        return PlaybackSample(duration: duration, currentTime: currentTime)
    }
}