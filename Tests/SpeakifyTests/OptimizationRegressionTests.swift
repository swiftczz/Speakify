import Foundation
import SwiftData
import XCTest
@testable import Speakify

final class CredentialScopeTests: XCTestCase {
    func testFingerprintNeverContainsTheOriginalKeyAndSeparatesAccounts() {
        let first = CredentialScope.fingerprint(apiKey: "account-one-secret")
        let second = CredentialScope.fingerprint(apiKey: "account-two-secret")

        XCTAssertEqual(first.count, 64)
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(first.contains("account-one-secret"))
        XCTAssertEqual(CredentialScope.fingerprint(apiKey: "   "), "anonymous")
    }

    func testQuotaSnapshotRetainsItsProviderAndCredentialScope() {
        let snapshot = SubscriptionQuotaSnapshot(
            providerID: "elevenlabs",
            credentialFingerprint: "fingerprint",
            characterCount: 25,
            characterLimit: 100
        )

        XCTAssertEqual(snapshot.providerID, "elevenlabs")
        XCTAssertEqual(snapshot.credentialFingerprint, "fingerprint")
        XCTAssertEqual(snapshot.quota.remaining, 75)
    }
}

final class SpeechExportStoreTests: XCTestCase {
    func testExportsAudioAndSubtitleAsACompanionPair() async throws {
        let directory = try temporaryDirectory()
        let speech = GeneratedSpeech(
            audioData: Data([1, 2, 3, 4]),
            fileExtension: "mp3",
            request: SpeechRequest(
                text: "你好，世界。",
                voice: TTSVoice(
                    id: "voice",
                    name: "冰糖",
                    category: nil,
                    detail: nil,
                    previewURL: nil,
                    gender: nil,
                    accent: nil,
                    locale: "zh-CN",
                    language: "Chinese"
                ),
                modelID: "model",
                outputFormat: "mp3",
                languageCode: nil,
                voiceSettings: VoiceSettings()
            ),
            alignment: nil
        )

        let result = try await SpeechExportStore().export(
            speech: speech,
            subtitle: "1\n00:00:00,000 --> 00:00:01,000\n你好，世界。\n",
            to: directory
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.audioURL.path(percentEncoded: false)))
        let subtitleURL = try XCTUnwrap(result.subtitleURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: subtitleURL.path(percentEncoded: false)))
        XCTAssertEqual(
            result.audioURL.deletingPathExtension().lastPathComponent,
            subtitleURL.deletingPathExtension().lastPathComponent
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "speakify-export-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}

final class AppDataLocationMigrationTests: XCTestCase {
    func testMigratesHistoryAndCacheWithoutDeletingUnmovedData() throws {
        let base = FileManager.default.temporaryDirectory
            .appending(path: "speakify-migration-\(UUID().uuidString)", directoryHint: .isDirectory)
        let legacy = base.appending(path: "legacy", directoryHint: .isDirectory)
        let destination = base.appending(path: "destination", directoryHint: .isDirectory)
        let legacyCache = legacy.appending(path: "AudioCache", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: legacyCache, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }

        try Data("history".utf8).write(to: legacy.appending(path: "History.store"))
        try Data("audio".utf8).write(to: legacyCache.appending(path: "request.mp3"))

        AppDataLocation.migrateLegacyData(from: legacy, to: destination)

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: destination.appending(path: "History.store").path(percentEncoded: false)
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: destination
                    .appending(path: "AudioCache/request.mp3")
                    .path(percentEncoded: false)
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyCache.path(percentEncoded: false)))
    }
}

final class OptimizationFeatureRegressionTests: XCTestCase {
    func testQuotaProgressRepresentsWhatHasBeenUsed() {
        let quota = TTSQuota(characterCount: 75, characterLimit: 100)

        XCTAssertEqual(quota.remaining, 25)
        XCTAssertEqual(quota.usedFraction, 0.75)
    }

    func testProviderCapabilitiesOwnModelLimitsCreditPolicyAndVoiceSettings() throws {
        let capabilities = ElevenLabsProvider().capabilities
        let settings = try XCTUnwrap(capabilities.voiceSettings)

        XCTAssertEqual(capabilities.characterLimit(for: "eleven_v3"), 5_000)
        XCTAssertEqual(capabilities.characterLimit(for: "eleven_multilingual_v2"), 10_000)
        XCTAssertEqual(capabilities.characterLimit(for: "eleven_flash_v2_5"), 40_000)
        XCTAssertEqual(
            capabilities.estimatedCreditCost(characterCount: 101, modelID: "eleven_flash_v2_5"),
            51
        )
        XCTAssertFalse(settings.supportsSpeed(modelID: "eleven_v3"))
        XCTAssertTrue(settings.supportsSpeed(modelID: "eleven_multilingual_v2"))
        XCTAssertEqual(settings.speedRange, 0.7...1.2)
    }

    func testPreferredVoiceIsPersistedPerProviderAndCredential() throws {
        let suiteName = "SpeakifyOptimizationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        settings.setPreferredVoiceID("public-voice", providerID: "elevenlabs", apiKey: "")
        settings.setPreferredVoiceID("account-voice", providerID: "elevenlabs", apiKey: "secret")
        settings.setPreferredVoiceID("mimo-voice", providerID: "mimo", apiKey: "secret")

        XCTAssertEqual(
            settings.preferredVoiceID(providerID: "elevenlabs", apiKey: ""),
            "public-voice"
        )
        XCTAssertEqual(
            settings.preferredVoiceID(providerID: "elevenlabs", apiKey: "secret"),
            "account-voice"
        )
        XCTAssertEqual(
            settings.preferredVoiceID(providerID: "mimo", apiKey: "secret"),
            "mimo-voice"
        )
    }

    func testVoiceSettingsArePersistedPerProvider() throws {
        let suiteName = "SpeakifyVoiceSettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = AppSettings(defaults: defaults)
        let customized = VoiceSettings(
            stability: 0.25,
            similarityBoost: 0.9,
            style: 0.4,
            speed: 1.15,
            speakerBoost: false
        )

        first.setVoiceSettings(customized, for: "elevenlabs")
        let reloaded = AppSettings(defaults: defaults)

        XCTAssertEqual(reloaded.voiceSettings(for: "elevenlabs"), customized)
        XCTAssertEqual(reloaded.voiceSettings(for: "mimo"), VoiceSettings())
    }

    func testStoredVoiceSettingsAreNormalizedToProviderRanges() throws {
        let suiteName = "SpeakifyVoiceSettingsNormalizationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        settings.setVoiceSettings(
            VoiceSettings(
                stability: -4,
                similarityBoost: 8,
                style: 3,
                speed: 9,
                speakerBoost: true
            ),
            for: "elevenlabs"
        )

        XCTAssertEqual(
            settings.voiceSettings(for: "elevenlabs"),
            VoiceSettings(
                stability: 0,
                similarityBoost: 1,
                style: 1,
                speed: 1.2,
                speakerBoost: true
            )
        )
    }

    func testHistoryDraftRetainsTheFullSpeechConfiguration() {
        let expectedSettings = VoiceSettings(
            stability: 0.35,
            similarityBoost: 0.8,
            style: 0.2,
            speed: 1.1,
            speakerBoost: false
        )
        let record = SpeechHistoryRecord(
            title: "Restore me",
            providerID: "elevenlabs",
            voiceName: "Aria",
            voiceID: "aria",
            modelID: "eleven_multilingual_v2",
            outputFormat: "mp3_44100_128",
            languageCode: "en",
            voiceSettings: expectedSettings,
            duration: 2,
            requestKey: "request"
        )

        XCTAssertEqual(
            record.draft,
            SpeechHistoryDraft(
                text: "Restore me",
                providerID: "elevenlabs",
                voiceID: "aria",
                modelID: "eleven_multilingual_v2",
                outputFormat: "mp3_44100_128",
                languageCode: "en",
                voiceSettings: expectedSettings
            )
        )
    }

    func testVoiceCatalogCachePersistsAndSeparatesCredentials() async throws {
        let directory = try temporaryDirectory(prefix: "SpeakifyCatalogCacheTests")
        let catalog = TTSVoiceCatalog(
            publicVoices: [Self.voice(id: "public")],
            accountVoices: [Self.voice(id: "account")]
        )
        let writer = VoiceCatalogCacheStore(directoryURL: directory)
        await writer.store(catalog, providerID: "elevenlabs", apiKey: "first-key")

        let reader = VoiceCatalogCacheStore(directoryURL: directory)
        let restored = await reader.catalog(providerID: "elevenlabs", apiKey: "first-key")
        let otherAccount = await reader.catalog(providerID: "elevenlabs", apiKey: "second-key")

        XCTAssertEqual(restored?.voices.map(\.id), ["public", "account"])
        XCTAssertNil(otherAccount)
    }

    func testVoicePreviewCachePersistsAudioAcrossStoreInstances() async throws {
        let directory = try temporaryDirectory(prefix: "SpeakifyPreviewCacheTests")
        let key = VoicePreviewCacheStore.cacheKey(
            providerID: "mimo",
            modelID: "mimo-tts",
            credentialFingerprint: "account",
            voiceID: "voice"
        )
        let expected = CachedVoicePreview(data: Data([1, 2, 3]), fileExtension: "mp3")
        let writer = VoicePreviewCacheStore(directoryURL: directory)
        await writer.store(expected, for: key)

        let reader = VoicePreviewCacheStore(directoryURL: directory)
        let restored = await reader.preview(for: key)

        XCTAssertEqual(restored?.data, expected.data)
        XCTAssertEqual(restored?.fileExtension, "mp3")
    }

    @MainActor
    func testHistoryStoreReplacesDuplicateRequests() throws {
        let schema = Schema([SpeechHistoryRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let request = SpeechRequest(
            text: "Same request",
            voice: Self.voice(id: "voice"),
            modelID: "model",
            outputFormat: "mp3",
            languageCode: "en",
            voiceSettings: VoiceSettings()
        )
        let speech = GeneratedSpeech(
            audioData: Data([1]),
            fileExtension: "mp3",
            request: request,
            alignment: nil
        )
        let store = SpeechHistoryStore()

        try store.record(
            speech: speech,
            providerID: "elevenlabs",
            apiKey: "key",
            duration: 1,
            modelContext: context
        )
        try store.record(
            speech: speech,
            providerID: "elevenlabs",
            apiKey: "key",
            duration: 2,
            modelContext: context
        )

        let records = try context.fetch(FetchDescriptor<SpeechHistoryRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.duration, 2)
    }

    private static func voice(id: String) -> TTSVoice {
        TTSVoice(
            id: id,
            name: id.capitalized,
            category: nil,
            detail: nil,
            previewURL: nil,
            gender: nil,
            accent: nil,
            locale: nil,
            language: nil
        )
    }

    private func temporaryDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}
