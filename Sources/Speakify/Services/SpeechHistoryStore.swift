import CryptoKit
import Foundation
import SwiftData

@MainActor
final class SpeechHistoryStore {
    private let recordLimit: Int

    init(recordLimit: Int = 100) {
        self.recordLimit = recordLimit
    }

    func record(
        speech: GeneratedSpeech,
        providerID: String,
        apiKey: String,
        duration: TimeInterval?,
        modelContext: ModelContext
    ) throws {
        let requestKey = Self.requestKey(
            for: speech.request,
            providerID: providerID,
            apiKey: apiKey
        )
        removeDuplicates(requestKey: requestKey, modelContext: modelContext)

        modelContext.insert(
            SpeechHistoryRecord(
                title: speech.request.text,
                providerID: providerID,
                voiceName: speech.request.voice.displayName,
                voiceID: speech.request.voice.id,
                modelID: speech.request.modelID,
                outputFormat: speech.request.outputFormat,
                languageCode: speech.request.languageCode ?? "",
                voiceSettings: speech.request.voiceSettings,
                duration: duration,
                requestKey: requestKey
            )
        )
        try modelContext.save()
        prune(modelContext: modelContext)
    }

    static func requestKey(
        for request: SpeechRequest,
        providerID: String,
        apiKey: String
    ) -> String {
        let source = [
            providerID,
            CredentialScope.fingerprint(apiKey: apiKey),
            request.text,
            request.voice.id,
            request.modelID,
            request.outputFormat,
            request.languageCode ?? "",
            String(request.voiceSettings.stability),
            String(request.voiceSettings.similarityBoost),
            String(request.voiceSettings.style),
            String(request.voiceSettings.speed),
            String(request.voiceSettings.speakerBoost)
        ].joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(source.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func removeDuplicates(requestKey: String, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<SpeechHistoryRecord>(
            predicate: #Predicate { $0.requestKey == requestKey }
        )
        if let records = try? modelContext.fetch(descriptor) {
            records.forEach(modelContext.delete)
        }
    }

    private func prune(modelContext: ModelContext) {
        var descriptor = FetchDescriptor<SpeechHistoryRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchOffset = recordLimit

        guard let oldRecords = try? modelContext.fetch(descriptor),
              oldRecords.isEmpty == false else {
            return
        }
        oldRecords.forEach(modelContext.delete)
        try? modelContext.save()
    }
}
