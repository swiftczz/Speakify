import Combine
import Foundation
import SwiftData
import XCTest
@testable import Speakify

@MainActor
final class SpeechViewModelCatalogTests: XCTestCase {
    /// A provider switch while a slow catalog request is still in flight must not let
    /// the stale answer land on top of the provider the user actually selected.
    func testStaleCatalogLoadDoesNotOverwriteTheNewerProvider() async throws {
        let slow = StubProvider(
            id: "slow",
            publicVoices: [Self.voice(id: "slow-voice")],
            loadDelay: .milliseconds(250)
        )
        let fast = StubProvider(id: "fast", publicVoices: [Self.voice(id: "fast-voice")])
        let harness = try makeHarness(providers: [slow, fast])

        let viewModel = harness.viewModel
        let staleLoad = Task { @MainActor in await viewModel.loadModelsAndVoices() }
        try await Task.sleep(for: .milliseconds(30))
        harness.settings.providerID = "fast"
        await harness.viewModel.loadModelsAndVoices()
        await staleLoad.value

        try await Task.sleep(for: .milliseconds(400))

        XCTAssertEqual(harness.viewModel.voices.map(\.id), ["fast-voice"])
        XCTAssertEqual(harness.viewModel.selectedVoice?.id, "fast-voice")
    }

    /// Losing the account half of the catalog should still fill the picker with the
    /// public half rather than leaving the user with nothing.
    func testPartialCatalogFailureStillPublishesPublicVoices() async throws {
        let provider = StubProvider(
            id: "partial",
            publicVoices: [Self.voice(id: "public-voice")],
            accountFailure: "Invalid API key."
        )
        let harness = try makeHarness(providers: [provider])
        harness.settings.apiKey = "some-key"

        await harness.viewModel.loadModelsAndVoices()

        XCTAssertEqual(harness.viewModel.voices.map(\.id), ["public-voice"])
        XCTAssertEqual(harness.viewModel.visibleStatusTone, .error)
        XCTAssertTrue(harness.viewModel.visibleStatusMessage.contains("Invalid API key."))
    }

    func testModelEndpointFailureStillPublishesPublicVoicesAndFallbackModels() async throws {
        let provider = StubProvider(
            id: "model-failure",
            publicVoices: [Self.voice(id: "public-voice")]
        )
        provider.failModelLoad = true
        let harness = try makeHarness(providers: [provider])
        harness.settings.apiKey = "expired-key"

        await harness.viewModel.loadModelsAndVoices()

        XCTAssertEqual(harness.viewModel.models.map(\.id), ["stub-model"])
        XCTAssertEqual(harness.viewModel.voices.map(\.id), ["public-voice"])
    }

    /// Switching credentials must drop the previous account's voices and balance up
    /// front, so a reload that fails cannot leave another account's data on screen.
    func testCredentialChangeDropsPreviousAccountVoicesAndQuota() async throws {
        let provider = StubProvider(
            id: "account",
            publicVoices: [Self.voice(id: "public-voice")],
            accountVoices: [Self.voice(id: "account-voice")],
            quota: TTSQuota(characterCount: 10, characterLimit: 100)
        )
        let harness = try makeHarness(providers: [provider])
        harness.settings.apiKey = "first-key"
        await harness.viewModel.loadModelsAndVoices()

        XCTAssertEqual(harness.viewModel.accountVoices.map(\.id), ["account-voice"])
        XCTAssertNotNil(harness.viewModel.quota)

        // The next load fails outright, standing in for a key that is no longer valid.
        provider.failEverything = true
        harness.settings.apiKey = "second-key"

        // The API key observer is debounced by 0.8s before it reloads.
        try await Task.sleep(for: .milliseconds(1_400))

        XCTAssertFalse(
            harness.viewModel.voices.contains { $0.id == "account-voice" },
            "The previous account's voices must not survive a failed reload."
        )
        XCTAssertNil(harness.viewModel.quota)
    }

    func testCredentialChangeRejectsAnOldSynthesisBeforeItCanPlayOrCache() async throws {
        let provider = StubProvider(
            id: "scoped-synthesis",
            publicVoices: [Self.voice(id: "voice")],
            synthesisDelay: .milliseconds(120)
        )
        let harness = try makeHarness(providers: [provider])
        harness.settings.apiKey = "first-key"
        await harness.viewModel.loadModelsAndVoices()

        let schema = Schema([SpeechHistoryRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let playTask = Task { @MainActor in
            await harness.viewModel.play(modelContext: context)
        }
        try await Task.sleep(for: .milliseconds(25))
        harness.settings.apiKey = "second-key"
        await playTask.value

        XCTAssertFalse(harness.viewModel.playback.isPlaying)
        XCTAssertEqual(
            harness.viewModel.visibleStatusMessage,
            TTSProviderError.requestChanged.localizedDescription
        )
    }

    private struct Harness {
        let settings: AppSettings
        let viewModel: SpeechViewModel
    }

    private func makeHarness(providers: [any TTSProvider]) throws -> Harness {
        let suiteName = "SpeakifyTests.ViewModel.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "speakify-vm-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        defaults.set(providers[0].id, forKey: "providerID")
        let settings = AppSettings(defaults: defaults)
        let viewModel = SpeechViewModel(
            settings: settings,
            providers: providers,
            cacheStore: SpeechCacheStore(
                retention: 3_600,
                sizeLimit: 1_024 * 1_024,
                directoryURL: directory
            )
        )
        return Harness(settings: settings, viewModel: viewModel)
    }

    private static func voice(id: String) -> TTSVoice {
        TTSVoice(
            id: id,
            name: id,
            category: "premade",
            detail: nil,
            previewURL: nil,
            gender: nil,
            accent: nil,
            locale: nil,
            language: nil
        )
    }
}

private final class StubProvider: TTSProvider, @unchecked Sendable {
    let id: String
    let displayName = "Stub"
    let capabilities: TTSProviderCapabilities
    let fallbackModels = [
        TTSModel(id: "stub-model", name: "Stub Model", canDoTextToSpeech: true, servesProVoices: false)
    ]

    private let publicVoices: [TTSVoice]
    private let accountVoices: [TTSVoice]
    private let accountFailure: String?
    private let quota: TTSQuota?
    private let loadDelay: Duration
    private let synthesisDelay: Duration
    var failEverything = false
    var failModelLoad = false

    init(
        id: String,
        publicVoices: [TTSVoice] = [],
        accountVoices: [TTSVoice] = [],
        accountFailure: String? = nil,
        quota: TTSQuota? = nil,
        loadDelay: Duration = .zero,
        synthesisDelay: Duration = .zero
    ) {
        self.id = id
        self.publicVoices = publicVoices
        self.accountVoices = accountVoices
        self.accountFailure = accountFailure
        self.quota = quota
        self.loadDelay = loadDelay
        self.synthesisDelay = synthesisDelay
        capabilities = TTSProviderCapabilities(
            outputFormats: ["mp3"],
            defaultOutputFormat: "mp3",
            defaultModelID: "stub-model",
            reportsQuota: quota != nil,
            providesSubtitles: false,
            providesCharacterAlignment: false,
            acceptsLanguageHint: false,
            meteredSynthesis: false,
            apiKeyHint: ""
        )
    }

    func fetchModels(apiKey: String) async throws -> [TTSModel] {
        if failModelLoad {
            throw TTSProviderError.httpStatus(status: 401, message: "Unauthorized.", code: "invalid_api_key")
        }
        try await waitOutDelay()
        return fallbackModels
    }

    func fetchVoiceCatalog(apiKey: String) async throws -> TTSVoiceCatalog {
        try await waitOutDelay()
        return TTSVoiceCatalog(
            publicVoices: publicVoices,
            accountVoices: apiKey.isEmpty ? [] : accountVoices,
            accountFailure: accountFailure
        )
    }

    func fetchQuota(apiKey: String) async throws -> TTSQuota? {
        try await waitOutDelay()
        return quota
    }

    func synthesize(request: SpeechRequest, apiKey: String) async throws -> GeneratedSpeech {
        if synthesisDelay != .zero {
            try await Task.sleep(for: synthesisDelay)
        }
        return GeneratedSpeech(
            audioData: Data([1, 2, 3]),
            fileExtension: "mp3",
            request: request,
            alignment: nil
        )
    }

    private func waitOutDelay() async throws {
        if failEverything {
            throw TTSProviderError.httpStatus(status: 401, message: "Unauthorized.", code: "invalid_api_key")
        }
        if loadDelay != .zero {
            try await Task.sleep(for: loadDelay)
        }
    }
}
