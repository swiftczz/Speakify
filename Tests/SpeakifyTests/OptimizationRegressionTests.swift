import Foundation
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
