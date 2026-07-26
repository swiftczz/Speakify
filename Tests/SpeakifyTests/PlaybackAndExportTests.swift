import Foundation
import SwiftData
import XCTest
@testable import Speakify

/// Covers the two view-model extensions that drive the transport bar. Both were unexercised:
/// the play/pause/resume routing and the export path had no tests at all, which is how the
/// download guard drifted out of step with the play guard without anything catching it.
@MainActor
final class PlaybackAndExportTests: XCTestCase {

    // MARK: - Export gating

    /// The regression that motivated this file. Exporting audio the app already holds sends no
    /// request and spends no credits, so an exhausted quota must not block it — play has always
    /// permitted this and download used to refuse.
    func testDownloadIsAllowedWhenCreditsAreExhaustedButSpeechIsCached() async throws {
        let harness = try makeHarness(quota: TTSQuota(characterCount: 100, characterLimit: 100))
        try await harness.primeCache()

        XCTAssertFalse(harness.viewModel.canGenerate, "credits are exhausted")
        XCTAssertTrue(harness.viewModel.hasCachedSpeechForCurrentRequest)

        await harness.viewModel.download(modelContext: harness.modelContext)

        XCTAssertEqual(harness.viewModel.visibleStatusTone, .success)
        XCTAssertNotNil(harness.viewModel.downloadFeedback)
        XCTAssertEqual(try harness.exportedFileCount(), 1)
    }

    /// The complement: with nothing cached there is nothing to export without synthesising, so
    /// the guard must still refuse and say why.
    func testDownloadIsRefusedWhenCreditsAreExhaustedAndNothingIsCached() async throws {
        let harness = try makeHarness(quota: TTSQuota(characterCount: 100, characterLimit: 100))

        XCTAssertFalse(harness.viewModel.canGenerate)
        XCTAssertFalse(harness.viewModel.hasCachedSpeechForCurrentRequest)

        await harness.viewModel.download(modelContext: harness.modelContext)

        XCTAssertEqual(harness.viewModel.visibleStatusTone, .error)
        XCTAssertNil(harness.viewModel.downloadFeedback)
        XCTAssertEqual(try harness.exportedFileCount(), 0)
    }

    func testDownloadWritesAudioAndRecordsHistory() async throws {
        let harness = try makeHarness()

        await harness.viewModel.download(modelContext: harness.modelContext)

        XCTAssertEqual(harness.viewModel.visibleStatusTone, .success)
        XCTAssertEqual(try harness.exportedFileCount(), 1)
        XCTAssertEqual(try harness.historyCount(), 1)
    }

    // MARK: - Transport

    func testPlayStartsPlaybackAndRecordsHistory() async throws {
        let harness = try makeHarness()

        await harness.viewModel.play(modelContext: harness.modelContext)

        XCTAssertTrue(harness.viewModel.playback.isPlaying)
        XCTAssertEqual(harness.viewModel.visibleStatusTone, .success)
        XCTAssertEqual(try harness.historyCount(), 1)
    }

    func testPauseThenResumeReturnsToPlaying() async throws {
        let harness = try makeHarness()
        await harness.viewModel.play(modelContext: harness.modelContext)
        XCTAssertTrue(harness.viewModel.playback.isPlaying)

        harness.viewModel.pause()
        XCTAssertFalse(harness.viewModel.playback.isPlaying)
        XCTAssertTrue(harness.viewModel.playback.isPaused)

        harness.viewModel.resume()
        XCTAssertTrue(harness.viewModel.playback.isPlaying)
        XCTAssertFalse(harness.viewModel.playback.isPaused)
    }

    /// play() and resume() emit the same "Playing …" sentence, so they must carry the same tone.
    /// They did not, which showed a checkmark on one route and an info glyph on the other.
    func testPlayAndResumeReportTheSameTone() async throws {
        let harness = try makeHarness()
        await harness.viewModel.play(modelContext: harness.modelContext)
        let playTone = harness.viewModel.visibleStatusTone
        let playMessage = harness.viewModel.visibleStatusMessage

        harness.viewModel.pause()
        harness.viewModel.resume()

        XCTAssertEqual(harness.viewModel.visibleStatusMessage, playMessage)
        XCTAssertEqual(harness.viewModel.visibleStatusTone, playTone)
    }

    func testTogglePlayPauseWalksIdleToPlayingToPausedAndBack() async throws {
        let harness = try makeHarness()
        let viewModel = harness.viewModel

        await viewModel.togglePlayPause(modelContext: harness.modelContext)
        XCTAssertTrue(viewModel.playback.isPlaying)

        await viewModel.togglePlayPause(modelContext: harness.modelContext)
        XCTAssertTrue(viewModel.playback.isPaused)

        await viewModel.togglePlayPause(modelContext: harness.modelContext)
        XCTAssertTrue(viewModel.playback.isPlaying)
    }

    func testStopClearsPlaybackAndReportsIt() async throws {
        let harness = try makeHarness()
        await harness.viewModel.play(modelContext: harness.modelContext)

        harness.viewModel.stop()

        XCTAssertFalse(harness.viewModel.playback.isPlaying)
        XCTAssertFalse(harness.viewModel.playback.isPaused)
        XCTAssertEqual(harness.viewModel.visibleStatusTone, .info)
    }

    func testPauseOnIdlePlayerIsIgnored() throws {
        let harness = try makeHarness()

        harness.viewModel.pause()

        XCTAssertFalse(harness.viewModel.playback.isPlaying)
        XCTAssertFalse(harness.viewModel.playback.isPaused)
    }

    func testPlayWithoutAVoiceReportsValidationFailure() async throws {
        let harness = try makeHarness()
        harness.viewModel.selectedVoice = nil

        await harness.viewModel.play(modelContext: harness.modelContext)

        XCTAssertFalse(harness.viewModel.playback.isPlaying)
        XCTAssertEqual(harness.viewModel.visibleStatusTone, .error)
    }

    // MARK: - Harness

    @MainActor
    private struct Harness {
        let settings: AppSettings
        let viewModel: SpeechViewModel
        let modelContext: ModelContext
        let exportDirectory: URL

        func exportedFileCount() throws -> Int {
            let contents = try FileManager.default.contentsOfDirectory(
                at: exportDirectory,
                includingPropertiesForKeys: nil
            )
            return contents.filter { $0.pathExtension == "wav" }.count
        }

        func historyCount() throws -> Int {
            try modelContext.fetch(FetchDescriptor<SpeechHistoryRecord>()).count
        }

        /// Runs one synthesis so the result lands in `lastSpeech`, then clears the status so a
        /// later assertion cannot pass on a stale success.
        func primeCache() async throws {
            _ = try await viewModel.currentSpeech()
            viewModel.updateStatus("", tone: .info)
        }
    }

    private func makeHarness(quota: TTSQuota? = nil) throws -> Harness {
        let suiteName = "SpeakifyTests.Transport.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }

        let root = FileManager.default.temporaryDirectory
            .appending(path: "speakify-transport-\(UUID().uuidString)", directoryHint: .isDirectory)
        let cacheDirectory = root.appending(path: "cache", directoryHint: .isDirectory)
        let exportDirectory = root.appending(path: "exports", directoryHint: .isDirectory)
        for directory in [cacheDirectory, exportDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let provider = AudioStubProvider(quota: quota)
        defaults.set(provider.id, forKey: "providerID")
        let settings = AppSettings(defaults: defaults)
        settings.downloadDirectoryPath = exportDirectory.path(percentEncoded: false)

        let viewModel = SpeechViewModel(
            settings: settings,
            providers: [provider],
            cacheStore: SpeechCacheStore(
                retention: 3_600,
                sizeLimit: 1_024 * 1_024,
                directoryURL: cacheDirectory
            )
        )
        viewModel.text = "Practice listening every morning."
        viewModel.selectedVoice = AudioStubProvider.voice
        if let quota {
            viewModel.quota = quota
        }

        let schema = Schema([SpeechHistoryRecord.self, SubscriptionQuotaSnapshot.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )

        return Harness(
            settings: settings,
            viewModel: viewModel,
            modelContext: ModelContext(container),
            exportDirectory: exportDirectory
        )
    }
}

/// Returns real WAV bytes, unlike the catalog stub — the playback path measures the audio before
/// it will report a duration, so three placeholder bytes are not enough to exercise it.
private final class AudioStubProvider: TTSProvider, @unchecked Sendable {
    let id = "audio-stub"
    let displayName = "Audio Stub"
    let capabilities: TTSProviderCapabilities
    let fallbackModels = [
        TTSModel(id: "stub-model", name: "Stub Model", canDoTextToSpeech: true, servesProVoices: false)
    ]

    private let quota: TTSQuota?

    static let voice = TTSVoice(
        id: "stub-voice",
        name: "Stub Voice",
        category: "premade",
        detail: nil,
        previewURL: nil,
        gender: nil,
        accent: nil,
        locale: nil,
        language: nil
    )

    init(quota: TTSQuota?) {
        self.quota = quota
        capabilities = TTSProviderCapabilities(
            outputFormats: ["wav"],
            defaultOutputFormat: "wav",
            defaultModelID: "stub-model",
            reportsQuota: quota != nil,
            providesSubtitles: false,
            providesCharacterAlignment: false,
            acceptsLanguageHint: false,
            meteredSynthesis: quota != nil,
            apiKeyHint: "",
            requiresAPIKey: false,
            // One credit per character, so a quota with nothing left refuses any non-empty text.
            creditPolicy: .characters(defaultMultiplier: 1, modelMultipliers: [:])
        )
    }

    func fetchModels(apiKey: String) async throws -> [TTSModel] { fallbackModels }

    func fetchVoiceCatalog(apiKey: String) async throws -> TTSVoiceCatalog {
        TTSVoiceCatalog(publicVoices: [Self.voice], accountVoices: [])
    }

    func fetchQuota(apiKey: String) async throws -> TTSQuota? { quota }

    func synthesize(request: SpeechRequest, apiKey: String) async throws -> GeneratedSpeech {
        GeneratedSpeech(
            audioData: Self.silentWAVData(duration: 1),
            fileExtension: "wav",
            request: request,
            alignment: nil
        )
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
        data.appendLittleEndianValue(UInt32(36) + dataSize)
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.appendLittleEndianValue(UInt32(16))
        data.appendLittleEndianValue(UInt16(1))
        data.appendLittleEndianValue(channels)
        data.appendLittleEndianValue(sampleRate)
        data.appendLittleEndianValue(byteRate)
        data.appendLittleEndianValue(blockAlign)
        data.appendLittleEndianValue(bitsPerSample)
        data.append(contentsOf: "data".utf8)
        data.appendLittleEndianValue(dataSize)
        data.append(Data(repeating: 0, count: Int(dataSize)))
        return data
    }
}

private extension Data {
    mutating func appendLittleEndianValue(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendLittleEndianValue(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}

/// The draft moved out of the preferences plist into the local data directory. These pin the
/// move down: new drafts land in the file, and a draft written by an older build is carried
/// over instead of being dropped.
@MainActor
final class DraftStorageTests: XCTestCase {
    func testDraftIsWrittenToItsFileRatherThanPreferences() throws {
        let (defaults, url) = try makeEnvironment()
        let settings = AppSettings(defaults: defaults, draftTextURL: url)

        settings.draftText = "Rewritten draft."

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Rewritten draft.")
        XCTAssertNil(defaults.string(forKey: "draftText"))
    }

    func testDraftStoredByAnOlderBuildIsMigratedOutOfPreferences() throws {
        let (defaults, url) = try makeEnvironment()
        defaults.set("Draft from the previous version.", forKey: "draftText")

        let settings = AppSettings(defaults: defaults, draftTextURL: url)

        XCTAssertEqual(settings.draftText, "Draft from the previous version.")
        XCTAssertEqual(
            try String(contentsOf: url, encoding: .utf8),
            "Draft from the previous version."
        )
        XCTAssertNil(defaults.string(forKey: "draftText"), "the stale copy is cleared")
    }

    func testDraftSurvivesReload() throws {
        let (defaults, url) = try makeEnvironment()
        let first = AppSettings(defaults: defaults, draftTextURL: url)
        first.draftText = "Persisted across launches."

        let second = AppSettings(defaults: defaults, draftTextURL: url)

        XCTAssertEqual(second.draftText, "Persisted across launches.")
    }

    private func makeEnvironment() throws -> (UserDefaults, URL) {
        let suiteName = "SpeakifyTests.Draft.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "speakify-draft-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        return (defaults, directory.appending(path: "Draft.txt"))
    }
}
