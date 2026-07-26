import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class SpeechViewModel {
    enum StatusTone: Equatable {
        case info
        case success
        case error
    }

    struct DownloadFeedback: Identifiable, Equatable {
        let id = UUID()
        let audioURL: URL
        let subtitleURL: URL?

        var fileName: String { audioURL.lastPathComponent }
    }

    var text: String {
        didSet {
            trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            scheduleDraftSave()
            invalidateSpeechCache()
        }
    }
    private(set) var trimmedText: String
    var models: [TTSModel] = []
    var voices: [TTSVoice] = []
    var publicVoiceIDs = Set<String>()
    var publicVoices: [TTSVoice] = []
    var accountVoices: [TTSVoice] = []
    var selectedVoice: TTSVoice? {
        didSet {
            if let selectedVoice {
                settings.setPreferredVoiceID(
                    selectedVoice.id,
                    providerID: settings.providerID,
                    apiKey: settings.apiKey
                )
            }
            invalidateSpeechCache()
        }
    }
    var voiceSettings = VoiceSettings() {
        didSet {
            settings.setVoiceSettings(voiceSettings, for: settings.providerID)
            invalidateSpeechCache()
        }
    }
    var isLoadingVoices = false
    var isGenerating = false
    var hasCachedSpeechForCurrentRequest = false
    private(set) var statusMessage = L10n.string(
        "status.configure",
        defaultValue: "Configure your API key, load voices, then generate and play."
    )
    private(set) var statusTone: StatusTone = .info
    var downloadFeedback: DownloadFeedback?
    private(set) var editorFocusRequests = 0
    var quota: TTSQuota?
    var quotaScopeIdentifier: String?
    var quotaStatusMessage: String?

    let settings: AppSettings
    let playback: PlaybackStore

    // Coordination state stays internal so the responsibility-based extensions can share it
    // without exposing implementation details outside the Speakify module.
    @ObservationIgnored private let providers: [any TTSProvider]
    @ObservationIgnored var allVoices: [TTSVoice] = []
    @ObservationIgnored var pendingPreferredVoiceID: String?
    @ObservationIgnored var lastSpeech: GeneratedSpeech?
    @ObservationIgnored var lastSpeechScope: String?
    @ObservationIgnored var quotaRefreshTask: Task<Void, Never>?
    @ObservationIgnored var synthesisTask: Task<GeneratedSpeech, any Error>?
    @ObservationIgnored var catalogTask: Task<Void, Never>?
    @ObservationIgnored var draftSaveTask: Task<Void, Never>?
    @ObservationIgnored var generationToken = 0
    @ObservationIgnored var lastCatalogSignature: String?
    @ObservationIgnored var suppressNextProviderReload = false
    @ObservationIgnored var credentialReloadTask: Task<Void, Never>?
    @ObservationIgnored var cacheAvailabilityTask: Task<Void, Never>?
    @ObservationIgnored let cacheStore: SpeechCacheStore
    @ObservationIgnored let catalogCacheStore: VoiceCatalogCacheStore
    @ObservationIgnored let exportStore: SpeechExportStore
    @ObservationIgnored let historyStore: SpeechHistoryStore
    @ObservationIgnored let nowPlaying = NowPlayingController()
    @ObservationIgnored var nowPlayingModelContext: ModelContext?

    let apiKeyDebounceInterval: Duration = .milliseconds(800)
    let cacheAvailabilityDebounceInterval: Duration = .milliseconds(150)
    let draftSaveDelay: Duration = .milliseconds(400)

    private static let audioCacheRetention: TimeInterval = 10 * 24 * 60 * 60
    private static let audioCacheSizeLimit = 500 * 1_024 * 1_024

    init(
        settings: AppSettings,
        providers: [any TTSProvider] = TTSProviderRegistry.providers,
        playback: PlaybackStore = PlaybackStore(),
        cacheStore: SpeechCacheStore = SpeechCacheStore(
            retention: SpeechViewModel.audioCacheRetention,
            sizeLimit: SpeechViewModel.audioCacheSizeLimit
        ),
        catalogCacheStore: VoiceCatalogCacheStore = VoiceCatalogCacheStore(),
        exportStore: SpeechExportStore = SpeechExportStore(),
        historyStore: SpeechHistoryStore = SpeechHistoryStore()
    ) {
        self.settings = settings
        self.text = settings.draftText
        self.trimmedText = settings.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.providers = providers
        self.playback = playback
        self.cacheStore = cacheStore
        self.catalogCacheStore = catalogCacheStore
        self.exportStore = exportStore
        self.historyStore = historyStore
        self.voiceSettings = settings.voiceSettings(for: settings.providerID)
        self.playback.setPlaybackRate(settings.playbackRate)
        models = activeProvider.fallbackModels
        Task { await cacheStore.prune() }
        observeSettingsChanges()
    }

    isolated deinit {
        catalogTask?.cancel()
        draftSaveTask?.cancel()
        quotaRefreshTask?.cancel()
        synthesisTask?.cancel()
        credentialReloadTask?.cancel()
        cacheAvailabilityTask?.cancel()
    }

    var activeProvider: any TTSProvider {
        providers.first { $0.id == settings.providerID } ?? providers[0]
    }

    var providerOptions: [TTSProviderOption] {
        providers.map { TTSProviderOption(id: $0.id, name: $0.displayName) }
    }

    var activeProviderReportsQuota: Bool {
        activeProvider.capabilities.reportsQuota
    }

    var downloadIncludesSubtitles: Bool {
        activeProvider.capabilities.providesSubtitles
    }

    var canGenerate: Bool {
        (activeProvider.capabilities.requiresAPIKey == false
            || settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            && trimmedText.isEmpty == false
            && isTextOverLimit == false
            && creditLimitError == nil
            && selectedVoice != nil
            && isGenerating == false
    }

    var isTextOverLimit: Bool {
        characterCount > characterLimit
    }

    var characterCount: Int {
        trimmedText.count
    }

    var characterLimit: Int {
        activeProvider.capabilities.characterLimit(for: settings.modelID)
    }

    var voiceSettingsCapabilities: TTSVoiceSettingsCapabilities? {
        activeProvider.capabilities.voiceSettings
    }

    var visibleStatusMessage: String {
        creditLimitError?.localizedDescription ?? statusMessage
    }

    var visibleStatusTone: StatusTone {
        creditLimitError == nil ? statusTone : .error
    }

    var estimatedCreditCost: Int {
        activeProvider.capabilities.estimatedCreditCost(
            characterCount: characterCount,
            modelID: settings.modelID
        )
    }

    private var creditLimitError: TTSProviderError? {
        guard let quota,
              quota.canExtendCharacterLimit == false,
              estimatedCreditCost > quota.remaining else {
            return nil
        }

        return .insufficientCredits(
            required: estimatedCreditCost,
            remaining: quota.remaining
        )
    }

    func validationMessage() -> String {
        if activeProvider.capabilities.requiresAPIKey,
           settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return TTSProviderError.missingAPIKey.localizedDescription
        }
        if trimmedText.isEmpty {
            return TTSProviderError.invalidText.localizedDescription
        }
        if isTextOverLimit {
            return TTSProviderError.textTooLong(
                count: trimmedText.count,
                limit: characterLimit
            ).localizedDescription
        }
        if let creditLimitError {
            return creditLimitError.localizedDescription
        }
        if selectedVoice == nil {
            return TTSProviderError.missingVoice.localizedDescription
        }
        return "Speech generation is already running."
    }

    var catalogSignature: String {
        CredentialScope.identifier(
            providerID: settings.providerID,
            apiKey: settings.apiKey
        )
    }

    func focusEditor() {
        editorFocusRequests += 1
    }

    func updateStatus(_ message: String, tone: StatusTone) {
        statusMessage = message
        statusTone = tone
    }

    /// Shared tail for the two operations that can synthesise — play and download. Both
    /// swallow cancellation, both retire a voice the provider has stopped serving, and both
    /// report anything else to the status line.
    func reportGenerationFailure(_ error: any Error) {
        guard Self.isCancellation(error) == false else { return }
        removeSelectedVoiceIfUnavailable(error)
        updateStatus(error.localizedDescription, tone: .error)
    }

    /// Writing history is secondary to the operation that triggered it, so a failure must not
    /// masquerade as the operation failing — but it cannot stay silent either, or the row just
    /// never appears and the user has no way to know why. Callers invoke this last, after the
    /// success status, so the warning is what remains on screen.
    func recordHistory(
        speech: GeneratedSpeech,
        duration: TimeInterval?,
        modelContext: ModelContext
    ) {
        do {
            try historyStore.record(
                speech: speech,
                providerID: settings.providerID,
                apiKey: settings.apiKey,
                duration: duration,
                modelContext: modelContext
            )
        } catch {
            updateStatus(
                L10n.format(
                    "status.history-save-failed",
                    defaultValue: "Could not save this to history: %@",
                    error.localizedDescription
                ),
                tone: .error
            )
        }
    }

    nonisolated static func estimatedCreditCost(characterCount: Int, modelID: String) -> Int {
        TTSProviderRegistry.provider(withID: "elevenlabs")
            .capabilities
            .estimatedCreditCost(characterCount: characterCount, modelID: modelID)
    }

    nonisolated static func isUnavailableVoiceError(_ error: any Error) -> Bool {
        guard case let TTSProviderError.httpStatus(_, _, code) = error else { return false }
        return code == "voice_not_found"
    }

    nonisolated static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError {
            return urlError.code == .cancelled
        }
        return false
    }
}
