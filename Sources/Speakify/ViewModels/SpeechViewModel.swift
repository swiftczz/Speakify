import Combine
import CryptoKit
import Foundation
import SwiftData

@MainActor
final class SpeechViewModel: ObservableObject {
    enum StatusTone: Equatable {
        case info
        case success
        case error
    }

    struct DownloadFeedback: Identifiable, Equatable {
        let id = UUID()
        let audioURL: URL
        /// `nil` when the provider does not produce alignment for subtitles.
        let subtitleURL: URL?

        var fileName: String { audioURL.lastPathComponent }
    }

    @Published var text: String {
        didSet {
            scheduleDraftSave()
            invalidateSpeechCache()
        }
    }
    @Published var models: [TTSModel] = []
    @Published var voices: [TTSVoice] = []
    @Published private(set) var publicVoiceIDs = Set<String>()
    @Published var selectedVoice: TTSVoice? {
        didSet { invalidateSpeechCache() }
    }
    @Published var voiceSettings = VoiceSettings() {
        didSet { invalidateSpeechCache() }
    }
    @Published var isLoadingVoices = false
    @Published var isGenerating = false
    @Published var isPlaying = false
    @Published var playbackCurrentTime: TimeInterval = 0
    @Published var playbackDuration: TimeInterval = 0
    @Published private(set) var statusMessage = "Configure your API key, load voices, then press play."
    @Published private(set) var statusTone: StatusTone = .info
    @Published var downloadFeedback: DownloadFeedback?
    @Published var quota: TTSQuota?
    @Published var quotaStatusMessage: String?

    let settings: AppSettings
    private let providers: [any TTSProvider]
    private let audioPlayer: AudioPlaybackService
    private var allVoices: [TTSVoice] = []
    private var lastSpeech: GeneratedSpeech?
    private var quotaRefreshTask: Task<Void, Never>?
    private var synthesisTask: Task<GeneratedSpeech, Error>?
    private var catalogTask: Task<Void, Never>?
    private var draftSaveTask: Task<Void, Never>?
    /// Bumped whenever a synthesis starts or is cancelled, so a superseded run
    /// never clears state that belongs to the run that replaced it.
    private var generationToken = 0
    /// Provider + key of the last catalog load, so the debounced API key
    /// observer skips the reload a provider switch has already performed.
    private var lastCatalogSignature: String?
    private var settingsCancellables = Set<AnyCancellable>()
    private let cacheStore: SpeechCacheStore
    private let apiKeyDebounceInterval: DispatchQueue.SchedulerTimeType.Stride = .seconds(0.8)
    /// Long enough that a burst of typing writes once, short enough that the draft
    /// survives a crash moments after the user stops.
    private let draftSaveDelay: Duration = .milliseconds(400)

    private static let audioCacheRetention: TimeInterval = 10 * 24 * 60 * 60
    /// Roughly 8 hours of mp3_44100_128 audio; past this the oldest speech is dropped.
    private static let audioCacheSizeLimit = 500 * 1_024 * 1_024

    init(
        settings: AppSettings,
        providers: [any TTSProvider] = TTSProviderRegistry.providers,
        audioPlayer: AudioPlaybackService = AudioPlaybackService(),
        cacheStore: SpeechCacheStore = SpeechCacheStore(
            retention: SpeechViewModel.audioCacheRetention,
            sizeLimit: SpeechViewModel.audioCacheSizeLimit
        )
    ) {
        self.settings = settings
        self.text = settings.draftText
        self.providers = providers
        self.audioPlayer = audioPlayer
        self.cacheStore = cacheStore
        self.audioPlayer.setPlaybackRate(settings.playbackRate)
        models = activeProvider.fallbackModels
        Task { await cacheStore.prune() }
        observeSettingsChanges()
    }

    deinit {
        catalogTask?.cancel()
        draftSaveTask?.cancel()
        quotaRefreshTask?.cancel()
        synthesisTask?.cancel()
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

    var publicVoices: [TTSVoice] {
        voices.filter { publicVoiceIDs.contains($0.id) }
    }

    var accountVoices: [TTSVoice] {
        voices.filter { publicVoiceIDs.contains($0.id) == false }
    }

    var canGenerate: Bool {
        settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && trimmedText.isEmpty == false
            && isTextOverLimit == false
            && creditLimitError == nil
            && selectedVoice != nil
            && isGenerating == false
    }

    var isTextOverLimit: Bool {
        trimmedText.count > TTSLimits.maxCharacterCount
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var visibleStatusMessage: String {
        creditLimitError?.localizedDescription ?? statusMessage
    }

    var visibleStatusTone: StatusTone {
        creditLimitError == nil ? statusTone : .error
    }

    var estimatedCreditCost: Int {
        Self.estimatedCreditCost(
            characterCount: trimmedText.count,
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

    var playbackProgress: Double {
        guard playbackDuration > 0 else { return 0 }
        return min(max(playbackCurrentTime / playbackDuration, 0), 1)
    }

    var playbackTimeText: String {
        "\(Self.formattedTime(playbackCurrentTime)) / \(Self.formattedTime(playbackDuration))"
    }

    /// Replaces any catalog load already running: switching provider or key while a
    /// slower request is in flight must never let the stale answer land afterwards.
    func loadModelsAndVoices() async {
        catalogTask?.cancel()
        let task = Task { @MainActor [weak self] () -> Void in
            await self?.performCatalogLoad()
        }
        catalogTask = task
        await task.value
    }

    private func performCatalogLoad() async {
        let provider = activeProvider
        let signature = catalogSignature
        lastCatalogSignature = signature
        isLoadingVoices = true
        defer {
            if signature == catalogSignature {
                isLoadingVoices = false
            }
        }

        do {
            updateStatus("Loading \(provider.displayName) models and voices...", tone: .info)
            let apiKey = settings.apiKey
            async let loadedModels = provider.fetchModels(apiKey: apiKey)
            async let loadedCatalog = provider.fetchVoiceCatalog(apiKey: apiKey)

            let (models, catalog) = try await (loadedModels, loadedCatalog)
            try Task.checkCancellation()
            guard signature == catalogSignature else { return }

            self.models = models.isEmpty ? provider.fallbackModels : models
            ensureSelectedModelIsAvailable()
            publicVoiceIDs = Set(catalog.publicVoices.map(\.id))
            allVoices = catalog.voices
            applyVoiceFilterForSelectedModel()
            await refreshQuota(apiKey: apiKey)
            guard signature == catalogSignature else { return }

            let status = catalogStatus(for: catalog, apiKey: apiKey)
            updateStatus(status.message, tone: status.tone)
        } catch {
            guard Self.isCancellation(error) == false, signature == catalogSignature else { return }
            quota = nil
            quotaStatusMessage = nil
            updateStatus(error.localizedDescription, tone: .error)
        }
    }

    private func catalogStatus(
        for catalog: TTSVoiceCatalog,
        apiKey: String
    ) -> (message: String, tone: StatusTone) {
        guard voices.isEmpty == false else {
            return ("No compatible voices returned by the account.", .error)
        }
        if let accountFailure = catalog.accountFailure {
            return (
                "Loaded \(voices.count) public voices. Account voices unavailable: \(accountFailure)",
                .error
            )
        }
        guard apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return (
                "Loaded \(voices.count) voices. Add an API key to generate speech.",
                .info
            )
        }
        if accountVoices.isEmpty == false {
            return (
                "Loaded \(publicVoices.count) public and \(accountVoices.count) account voices.",
                .success
            )
        }
        return ("Loaded \(voices.count) compatible voices.", .success)
    }

    func play(modelContext: ModelContext) async {
        guard canGenerate else {
            updateStatus(validationMessage(), tone: .error)
            return
        }

        do {
            let speech = try await currentSpeech(refreshQuotaOnCacheHit: true)
            let duration = try audioPlayer.play(
                data: speech.audioData,
                rate: settings.playbackRate,
                fileExtension: speech.fileExtension
            )
            playbackCurrentTime = 0
            playbackDuration = duration
            isPlaying = true
            updateStatus("Playing \(speech.request.voice.displayName).", tone: .success)
            // Written only once the audio is confirmed playable, so unplayable
            // output leaves no history entry. A failed write must not stop playback.
            try? recordHistory(for: speech, duration: duration, modelContext: modelContext)
        } catch {
            isPlaying = false
            guard Self.isCancellation(error) == false else { return }
            removeSelectedVoiceIfUnavailable(error)
            updateStatus(error.localizedDescription, tone: .error)
        }
    }

    /// Aborts an in-flight synthesis so a superseded request stops burning quota.
    func cancelGeneration() {
        guard isGenerating else { return }
        synthesisTask?.cancel()
        synthesisTask = nil
        generationToken += 1
        isGenerating = false
        updateStatus("Generation cancelled.", tone: .info)
    }

    func refreshPlaybackProgress() {
        guard isPlaying else { return }

        if audioPlayer.duration > 0 {
            playbackDuration = audioPlayer.duration
        }

        playbackCurrentTime = min(audioPlayer.currentTime, playbackDuration)

        if audioPlayer.isPlaying == false {
            finishPlayback()
        }
    }

    func stop() {
        audioPlayer.stop()
        playbackCurrentTime = 0
        isPlaying = false
        updateStatus("Playback stopped.", tone: .info)
    }

    func download(modelContext: ModelContext) async {
        guard canGenerate else {
            updateStatus(validationMessage(), tone: .error)
            return
        }

        do {
            let includesSubtitles = downloadIncludesSubtitles
            let speech = try await currentSpeech(
                refreshQuotaOnCacheHit: true,
                requireAlignment: includesSubtitles
                    && activeProvider.capabilities.providesCharacterAlignment
            )
            let subtitle: String?
            if includesSubtitles {
                if let alignment = speech.alignment, alignment.isValid {
                    subtitle = try SubtitleFormatter.srt(from: alignment)
                } else {
                    let duration = playbackDuration > 0
                        ? playbackDuration
                        : try audioPlayer.duration(data: speech.audioData)
                    subtitle = try SubtitleFormatter.estimatedSRT(
                        text: speech.request.text,
                        duration: duration
                    )
                }
            } else {
                subtitle = nil
            }
            let directory = settings.downloadDirectoryURL
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileName = FileNameFormatter.speechFileName(
                text: speech.request.text,
                voiceName: speech.request.voice.name,
                fileExtension: speech.fileExtension
            )
            let destination = FileNameFormatter.availableURL(
                in: directory,
                fileName: fileName,
                companionExtension: subtitle == nil ? nil : "srt"
            )
            let subtitleDestination = subtitle == nil
                ? nil
                : destination.deletingPathExtension().appendingPathExtension("srt")
            do {
                try speech.audioData.write(to: destination, options: .atomic)
                if let subtitle, let subtitleDestination {
                    try subtitle.write(to: subtitleDestination, atomically: true, encoding: .utf8)
                }
            } catch {
                try? FileManager.default.removeItem(at: destination)
                if let subtitleDestination {
                    try? FileManager.default.removeItem(at: subtitleDestination)
                }
                throw error
            }
            downloadFeedback = DownloadFeedback(audioURL: destination, subtitleURL: subtitleDestination)
            try recordHistory(for: speech, duration: playbackDuration > 0 ? playbackDuration : nil, modelContext: modelContext)
            if let subtitleDestination {
                updateStatus(
                    "Saved \(fileName) and \(subtitleDestination.lastPathComponent).",
                    tone: .success
                )
            } else {
                updateStatus("Saved \(fileName).", tone: .success)
            }
        } catch {
            guard Self.isCancellation(error) == false else { return }
            removeSelectedVoiceIfUnavailable(error)
            updateStatus(error.localizedDescription, tone: .error)
        }
    }

    private func currentSpeech(
        refreshQuotaOnCacheHit: Bool = false,
        requireAlignment: Bool = false
    ) async throws -> GeneratedSpeech {
        let request = try makeRequest()
        if let lastSpeech,
           lastSpeech.request == request,
           requireAlignment == false || lastSpeech.alignment?.isValid == true {
            if refreshQuotaOnCacheHit {
                await refreshQuota(apiKey: settings.apiKey)
            }
            return lastSpeech
        }

        if let cachedSpeech = await cacheStore.speech(for: request, key: Self.audioCacheKey(for: request)),
           requireAlignment == false || cachedSpeech.alignment?.isValid == true {
            if refreshQuotaOnCacheHit {
                await refreshQuota(apiKey: settings.apiKey)
            }
            playbackDuration = try audioPlayer.duration(data: cachedSpeech.audioData)
            playbackCurrentTime = 0
            lastSpeech = cachedSpeech
            updateStatus("Loaded cached speech.", tone: .success)
            return cachedSpeech
        }

        lastSpeech = nil
        resetPlaybackForNewSpeech()

        let provider = activeProvider
        let apiKey = settings.apiKey
        let task = Task { try await provider.synthesize(request: request, apiKey: apiKey) }

        generationToken += 1
        let token = generationToken
        synthesisTask = task
        isGenerating = true
        updateStatus("Generating speech...", tone: .info)
        defer {
            if generationToken == token {
                synthesisTask = nil
                isGenerating = false
            }
        }

        let generated = try await task.value
        guard generationToken == token else {
            throw CancellationError()
        }
        guard request == (try? makeRequest()) else {
            throw TTSProviderError.requestChanged
        }
        scheduleQuotaRefreshAfterGeneration(apiKey: settings.apiKey)
        playbackDuration = try audioPlayer.duration(data: generated.audioData)
        playbackCurrentTime = 0
        lastSpeech = generated
        let cacheKey = Self.audioCacheKey(for: generated.request)
        Task { [cacheStore] in await cacheStore.store(generated, key: cacheKey) }
        return generated
    }

    private func makeRequest() throws -> SpeechRequest {
        let trimmedText = self.trimmedText
        guard trimmedText.isEmpty == false else {
            throw TTSProviderError.invalidText
        }
        guard trimmedText.count <= TTSLimits.maxCharacterCount else {
            throw TTSProviderError.textTooLong(count: trimmedText.count, limit: TTSLimits.maxCharacterCount)
        }
        guard let selectedVoice else {
            throw TTSProviderError.missingVoice
        }

        return SpeechRequest(
            text: trimmedText,
            voice: selectedVoice,
            modelID: settings.modelID,
            outputFormat: settings.outputFormat,
            languageCode: settings.languageCode.isEmpty ? nil : settings.languageCode,
            voiceSettings: voiceSettings
        )
    }

    private func validationMessage() -> String {
        if settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return TTSProviderError.missingAPIKey.localizedDescription
        }
        if trimmedText.isEmpty {
            return TTSProviderError.invalidText.localizedDescription
        }
        if isTextOverLimit {
            return TTSProviderError.textTooLong(
                count: trimmedText.count,
                limit: TTSLimits.maxCharacterCount
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

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError {
            return urlError.code == .cancelled
        }
        return false
    }

    private func resetPlaybackForNewSpeech() {
        audioPlayer.stop()
        isPlaying = false
        playbackCurrentTime = 0
        playbackDuration = 0
    }

    private func invalidateSpeechCache() {
        cancelGeneration()

        guard lastSpeech != nil || playbackCurrentTime > 0 || playbackDuration > 0 || isPlaying else {
            return
        }

        lastSpeech = nil
        resetPlaybackForNewSpeech()
    }

    /// Writes a debounced draft immediately, for the moments where waiting out the
    /// delay would lose it — the window closing, or the app going away.
    func flushPendingDraft() {
        guard draftSaveTask != nil else { return }
        draftSaveTask?.cancel()
        draftSaveTask = nil
        settings.draftText = text
    }

    /// Coalesces keystrokes into one write instead of hitting user defaults per character.
    private func scheduleDraftSave() {
        draftSaveTask?.cancel()
        let draft = text
        draftSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.draftSaveDelay ?? .milliseconds(400))
            guard Task.isCancelled == false else { return }
            self?.settings.draftText = draft
        }
    }

    private func refreshQuota(apiKey: String? = nil) async {
        let provider = activeProvider
        guard provider.capabilities.reportsQuota else {
            quota = nil
            quotaStatusMessage = nil
            return
        }

        let resolvedAPIKey = (apiKey ?? settings.apiKey).trimmingCharacters(in: .whitespacesAndNewlines)

        guard resolvedAPIKey.isEmpty == false else {
            quota = nil
            quotaStatusMessage = nil
            return
        }

        do {
            quota = try await provider.fetchQuota(apiKey: resolvedAPIKey)
            quotaStatusMessage = nil
        } catch {
            quota = nil
            quotaStatusMessage = error.localizedDescription
        }
    }

    private func scheduleQuotaRefreshAfterGeneration(apiKey: String) {
        quotaRefreshTask?.cancel()
        guard activeProvider.capabilities.reportsQuota else { return }
        let resolvedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard resolvedAPIKey.isEmpty == false else { return }

        quotaRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // Usage updates can lag slightly behind synthesis completion.
            // Poll a few times so the sidebar tracks the server once the new usage lands.
            let delays: [Duration] = [.zero, .seconds(5), .seconds(10), .seconds(15), .seconds(20), .seconds(25)]

            for delay in delays {
                if delay != .zero {
                    try? await Task.sleep(for: delay)
                }
                guard Task.isCancelled == false else { return }
                await self.refreshQuota(apiKey: resolvedAPIKey)
            }
        }
    }

    /// Identifies the credentials a catalog load was made with, so provider and
    /// API key observers never trigger duplicate loads for the same state.
    private var catalogSignature: String {
        "\(settings.providerID)\u{1F}\(settings.apiKey)"
    }

    private func reloadCatalogForCredentialChange() async {
        invalidateSpeechCache()
        clearAccountScopedState()
        await loadModelsAndVoices()
    }

    /// Drops everything tied to the previous credentials before a reload, so a reload
    /// that fails can never leave the old account's voices or balance on screen.
    private func clearAccountScopedState() {
        quotaRefreshTask?.cancel()
        let accountVoiceIDs = Set(accountVoices.map(\.id))
        allVoices.removeAll { accountVoiceIDs.contains($0.id) }
        voices.removeAll { accountVoiceIDs.contains($0.id) }
        if let selectedVoice, accountVoiceIDs.contains(selectedVoice.id) {
            self.selectedVoice = voices.first
        }
        quota = nil
        quotaStatusMessage = nil
    }

    private func handleProviderSwitch() async {
        quotaRefreshTask?.cancel()
        allVoices = []
        voices = []
        publicVoiceIDs = []
        selectedVoice = nil
        quota = nil
        quotaStatusMessage = nil
        models = activeProvider.fallbackModels
        ensureSelectedModelIsAvailable()
        await reloadCatalogForCredentialChange()
    }

    private func observeSettingsChanges() {
        settings.$providerID
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in await self?.handleProviderSwitch() }
            }
            .store(in: &settingsCancellables)

        // The key field publishes on every keystroke; without debouncing, typing or
        // pasting a key fires a full model/voice/quota reload per character.
        settings.$apiKey
            .dropFirst()
            .removeDuplicates()
            .debounce(for: apiKeyDebounceInterval, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    // A provider switch already reloaded with this exact state.
                    guard self.lastCatalogSignature != self.catalogSignature else { return }
                    await self.reloadCatalogForCredentialChange()
                }
            }
            .store(in: &settingsCancellables)

        settings.$modelID
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.applyVoiceFilterForSelectedModel()
                    self?.invalidateSpeechCache()
                }
            }
            .store(in: &settingsCancellables)

        settings.$outputFormat
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.invalidateSpeechCache() }
            }
            .store(in: &settingsCancellables)

        settings.$languageCode
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.invalidateSpeechCache() }
            }
            .store(in: &settingsCancellables)

        settings.$playbackRate
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] playbackRate in
                Task { @MainActor in self?.audioPlayer.setPlaybackRate(playbackRate) }
            }
            .store(in: &settingsCancellables)
    }

    private func finishPlayback() {
        playbackCurrentTime = playbackDuration
        isPlaying = false
        updateStatus("Playback finished.", tone: .success)
    }

    private func updateStatus(_ message: String, tone: StatusTone) {
        statusMessage = message
        statusTone = tone
    }

    nonisolated static func estimatedCreditCost(characterCount: Int, modelID: String) -> Int {
        let normalizedCount = max(characterCount, 0)
        let multiplier = modelID == "eleven_flash_v2_5" ? 0.5 : 1.0
        return Int(ceil(Double(normalizedCount) * multiplier))
    }

    private func ensureSelectedModelIsAvailable() {
        if models.contains(where: { $0.id == settings.modelID }) == false {
            settings.modelID = models.first?.id ?? activeProvider.capabilities.defaultModelID
        }
    }

    private func applyVoiceFilterForSelectedModel() {
        let selectedModel = models.first(where: { $0.id == settings.modelID })
        let modelServesProVoices = selectedModel?.servesProVoices ?? false

        voices = allVoices.filter { voice in
            modelServesProVoices || voice.isProfessionalVoice == false
        }

        selectedVoice = selectedVoice.flatMap { current in
            voices.first(where: { $0.id == current.id })
        } ?? voices.first
    }

    private func removeSelectedVoiceIfUnavailable(_ error: Error) {
        guard let selectedVoice, Self.isUnavailableVoiceError(error) else { return }
        allVoices.removeAll { $0.id == selectedVoice.id }
        voices.removeAll { $0.id == selectedVoice.id }
        publicVoiceIDs.remove(selectedVoice.id)
        self.selectedVoice = voices.first
    }

    /// Deliberately narrow: only the service's explicit "this voice is gone" code
    /// removes a voice. Matching loose phrases such as "not available" also caught
    /// unrelated failures (quota, permissions) and dropped a perfectly good voice.
    nonisolated static func isUnavailableVoiceError(_ error: Error) -> Bool {
        guard case let TTSProviderError.httpStatus(_, _, code) = error else { return false }
        return code == "voice_not_found"
    }

    private static func formattedTime(_ duration: TimeInterval) -> String {
        let seconds = max(Int(duration.rounded()), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func recordHistory(for speech: GeneratedSpeech, duration: TimeInterval?, modelContext: ModelContext) throws {
        let requestKey = Self.historyRequestKey(for: speech.request)
        removeDuplicateHistoryRecords(requestKey: requestKey, modelContext: modelContext)

        let record = SpeechHistoryRecord(
            title: speech.request.text,
            voiceName: speech.request.voice.displayName,
            voiceID: speech.request.voice.id,
            modelID: speech.request.modelID,
            outputFormat: speech.request.outputFormat,
            duration: duration,
            requestKey: requestKey
        )
        modelContext.insert(record)
        try modelContext.save()
        pruneHistory(modelContext: modelContext, limit: 100)
    }

    private func removeDuplicateHistoryRecords(requestKey: String, modelContext: ModelContext) {
        let duplicateDescriptor = FetchDescriptor<SpeechHistoryRecord>(
            predicate: #Predicate { $0.requestKey == requestKey }
        )
        if let duplicateRecords = try? modelContext.fetch(duplicateDescriptor) {
            duplicateRecords.forEach { modelContext.delete($0) }
        }
    }

    private func pruneHistory(modelContext: ModelContext, limit: Int) {
        var descriptor = FetchDescriptor<SpeechHistoryRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchOffset = limit

        guard let oldRecords = try? modelContext.fetch(descriptor), oldRecords.isEmpty == false else {
            return
        }

        oldRecords.forEach { modelContext.delete($0) }
        try? modelContext.save()
    }

    private static func historyRequestKey(for request: SpeechRequest) -> String {
        [
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
    }

    private static func audioCacheKey(for request: SpeechRequest) -> String {
        let source = historyRequestKey(for: request)
        let digest = SHA256.hash(data: Data(source.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
