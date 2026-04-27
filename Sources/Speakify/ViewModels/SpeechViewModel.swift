import Combine
import CryptoKit
import Foundation
import SwiftData

@MainActor
final class SpeechViewModel: ObservableObject {
    struct DownloadFeedback: Identifiable, Equatable {
        let id = UUID()
        let fileURL: URL

        var fileName: String { fileURL.lastPathComponent }
    }

    @Published var text: String = "The best way to improve listening is to hear natural English every day." {
        didSet { invalidateSpeechCache() }
    }
    @Published var models: [TTSModel] = TTSModel.fallbackModels
    @Published var voices: [TTSVoice] = []
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
    @Published var statusMessage = "Configure your API key, load voices, then press play."
    @Published var lastSavedFile: URL?
    @Published var downloadFeedback: DownloadFeedback?
    @Published var subscription: ElevenLabsSubscription?
    @Published var subscriptionStatusMessage: String?

    let settings: AppSettings
    private let provider: any TTSProvider
    private let audioPlayer: AudioPlaybackService
    private var allVoices: [TTSVoice] = []
    private var lastSpeech: GeneratedSpeech?
    private var playbackTask: Task<Void, Never>?
    private var subscriptionRefreshTask: Task<Void, Never>?
    private var settingsCancellables = Set<AnyCancellable>()
    private let audioCacheRetention: TimeInterval = 10 * 24 * 60 * 60

    init(
        settings: AppSettings,
        provider: TTSProvider = ElevenLabsProvider(),
        audioPlayer: AudioPlaybackService = AudioPlaybackService()
    ) {
        self.settings = settings
        self.provider = provider
        self.audioPlayer = audioPlayer
        self.audioPlayer.setPlaybackRate(settings.playbackRate)
        pruneExpiredAudioCache()
        observeSettingsChanges()
    }

    var canGenerate: Bool {
        settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && selectedVoice != nil
            && isGenerating == false
    }

    var playbackProgress: Double {
        guard playbackDuration > 0 else { return 0 }
        return min(max(playbackCurrentTime / playbackDuration, 0), 1)
    }

    var playbackTimeText: String {
        "\(Self.formattedTime(playbackCurrentTime)) / \(Self.formattedTime(playbackDuration))"
    }

    func loadModelsAndVoices() async {
        isLoadingVoices = true
        defer { isLoadingVoices = false }

        do {
            statusMessage = "Loading ElevenLabs models and voices..."
            let apiKey = settings.apiKey
            async let loadedModels = provider.fetchModels(apiKey: apiKey)
            async let loadedVoices = provider.fetchVoices(apiKey: apiKey)

            let (models, voices) = try await (loadedModels, loadedVoices)
            self.models = models.isEmpty ? TTSModel.fallbackModels : models
            ensureSelectedModelIsAvailable()
            allVoices = voices
            applyVoiceFilterForSelectedModel()
            await refreshSubscription(apiKey: apiKey)
            statusMessage = self.voices.isEmpty ? "No compatible voices returned by the account." : "Loaded \(self.voices.count) compatible voices."
        } catch {
            subscription = nil
            subscriptionStatusMessage = nil
            statusMessage = error.localizedDescription
        }
    }

    func play(modelContext: ModelContext) async {
        guard canGenerate else {
            statusMessage = validationMessage()
            return
        }

        do {
            let speech = try await currentSpeech(refreshSubscriptionOnCacheHit: true)
            let expectedDuration = playbackDuration > 0 ? playbackDuration : try audioPlayer.duration(data: speech.audioData)
            try recordHistory(for: speech, duration: expectedDuration, modelContext: modelContext)
            let duration = try audioPlayer.play(
                data: speech.audioData,
                rate: settings.playbackRate,
                fileExtension: speech.fileExtension
            )
            playbackCurrentTime = 0
            playbackDuration = duration
            isPlaying = true
            statusMessage = "Playing \(speech.request.voice.displayName)."
            schedulePlaybackCompletion(after: duration / max(settings.playbackRate, 0.25))
        } catch {
            isPlaying = false
            removeSelectedVoiceIfUnavailable(error)
            statusMessage = error.localizedDescription
        }
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
        playbackTask?.cancel()
        playbackTask = nil
        audioPlayer.stop()
        playbackCurrentTime = 0
        isPlaying = false
        statusMessage = "Playback stopped."
    }

    func download(modelContext: ModelContext) async {
        guard canGenerate else {
            statusMessage = validationMessage()
            return
        }

        do {
            let speech = try await currentSpeech(refreshSubscriptionOnCacheHit: true)
            let directory = settings.downloadDirectoryURL
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileName = FileNameFormatter.speechFileName(
                text: speech.request.text,
                voiceName: speech.request.voice.name,
                fileExtension: speech.fileExtension
            )
            let destination = directory.appending(path: fileName)
            try speech.audioData.write(to: destination, options: .atomic)
            lastSavedFile = destination
            downloadFeedback = DownloadFeedback(fileURL: destination)
            try recordHistory(for: speech, duration: playbackDuration > 0 ? playbackDuration : nil, modelContext: modelContext)
            statusMessage = "Saved \(fileName)."
        } catch {
            removeSelectedVoiceIfUnavailable(error)
            statusMessage = error.localizedDescription
        }
    }

    private func currentSpeech(refreshSubscriptionOnCacheHit: Bool = false) async throws -> GeneratedSpeech {
        let request = try makeRequest()
        if let lastSpeech, lastSpeech.request == request {
            if refreshSubscriptionOnCacheHit {
                await refreshSubscription(apiKey: settings.apiKey)
            }
            return lastSpeech
        }

        if let cachedSpeech = loadCachedSpeech(for: request) {
            if refreshSubscriptionOnCacheHit {
                await refreshSubscription(apiKey: settings.apiKey)
            }
            playbackDuration = try audioPlayer.duration(data: cachedSpeech.audioData)
            playbackCurrentTime = 0
            lastSpeech = cachedSpeech
            statusMessage = "Loaded cached speech."
            return cachedSpeech
        }

        lastSpeech = nil
        resetPlaybackForNewSpeech()
        isGenerating = true
        defer { isGenerating = false }
        statusMessage = "Generating speech..."

        let generated = try await provider.synthesize(request: request, apiKey: settings.apiKey)
        guard request == (try? makeRequest()) else {
            throw TTSProviderError.requestChanged
        }
        scheduleSubscriptionRefreshAfterGeneration(apiKey: settings.apiKey)
        playbackDuration = try audioPlayer.duration(data: generated.audioData)
        playbackCurrentTime = 0
        lastSpeech = generated
        saveCachedSpeech(generated)
        return generated
    }

    private func makeRequest() throws -> SpeechRequest {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.isEmpty == false else {
            throw TTSProviderError.invalidText
        }
        guard let selectedVoice else {
            throw TTSProviderError.missingVoice
        }

        return SpeechRequest(
            text: trimmedText,
            voice: selectedVoice,
            modelID: settings.modelID,
            outputFormat: settings.outputFormat,
            voiceSettings: voiceSettings
        )
    }

    private func validationMessage() -> String {
        if settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return TTSProviderError.missingAPIKey.localizedDescription
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return TTSProviderError.invalidText.localizedDescription
        }
        if selectedVoice == nil {
            return TTSProviderError.missingVoice.localizedDescription
        }
        return "Speech generation is already running."
    }

    private func schedulePlaybackCompletion(after duration: TimeInterval) {
        playbackTask?.cancel()
        playbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(duration, 0)))
            guard Task.isCancelled == false else { return }
            self?.finishPlayback()
        }
    }

    private func resetPlaybackForNewSpeech() {
        playbackTask?.cancel()
        playbackTask = nil
        audioPlayer.stop()
        isPlaying = false
        playbackCurrentTime = 0
        playbackDuration = 0
    }

    private func invalidateSpeechCache() {
        guard lastSpeech != nil || playbackCurrentTime > 0 || playbackDuration > 0 || isPlaying else {
            return
        }

        lastSpeech = nil
        resetPlaybackForNewSpeech()
    }

    private func loadCachedSpeech(for request: SpeechRequest) -> GeneratedSpeech? {
        guard let cacheURL = cachedSpeechFileURL(for: request) else { return nil }
        guard FileManager.default.fileExists(atPath: cacheURL.path()) else { return nil }

        if isExpiredCacheFile(at: cacheURL) {
            try? FileManager.default.removeItem(at: cacheURL)
            return nil
        }

        guard let audioData = try? Data(contentsOf: cacheURL), audioData.isEmpty == false else {
            return nil
        }

        return GeneratedSpeech(
            audioData: audioData,
            fileExtension: Self.fileExtension(for: request.outputFormat),
            request: request
        )
    }

    private func saveCachedSpeech(_ speech: GeneratedSpeech) {
        guard let cacheURL = cachedSpeechFileURL(for: speech.request) else { return }
        do {
            try speech.audioData.write(to: cacheURL, options: .atomic)
            pruneExpiredAudioCache()
        } catch {
            // Ignore cache write failures; generation itself already succeeded.
        }
    }

    private func cachedSpeechFileURL(for request: SpeechRequest) -> URL? {
        guard let directoryURL = audioCacheDirectoryURL() else { return nil }
        let cacheKey = Self.audioCacheKey(for: request)
        return directoryURL.appending(path: "\(cacheKey).\(Self.fileExtension(for: request.outputFormat))")
    }

    private func audioCacheDirectoryURL() -> URL? {
        AppDataLocation.audioCacheDirectoryURL()
    }

    private func pruneExpiredAudioCache() {
        guard let directoryURL = audioCacheDirectoryURL() else { return }
        guard let cachedFiles = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for fileURL in cachedFiles where isExpiredCacheFile(at: fileURL) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func isExpiredCacheFile(at fileURL: URL) -> Bool {
        guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
              let modifiedAt = values.contentModificationDate else {
            return false
        }

        return Date().timeIntervalSince(modifiedAt) > audioCacheRetention
    }

    private func refreshSubscription(apiKey: String? = nil) async {
        let resolvedAPIKey = (apiKey ?? settings.apiKey).trimmingCharacters(in: .whitespacesAndNewlines)

        guard resolvedAPIKey.isEmpty == false else {
            subscription = nil
            subscriptionStatusMessage = nil
            return
        }

        do {
            subscription = try await provider.fetchSubscription(apiKey: resolvedAPIKey)
            subscriptionStatusMessage = nil
        } catch {
            subscription = nil
            subscriptionStatusMessage = error.localizedDescription
        }
    }

    private func scheduleSubscriptionRefreshAfterGeneration(apiKey: String) {
        subscriptionRefreshTask?.cancel()
        let resolvedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard resolvedAPIKey.isEmpty == false else { return }

        subscriptionRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // ElevenLabs usage updates can lag slightly behind synthesis completion.
            // Poll a few times so the sidebar tracks the server once the new usage lands.
            let delays: [Duration] = [.zero, .seconds(5), .seconds(10), .seconds(15), .seconds(20), .seconds(25)]

            for delay in delays {
                if delay != .zero {
                    try? await Task.sleep(for: delay)
                }
                guard Task.isCancelled == false else { return }
                await self.refreshSubscription(apiKey: resolvedAPIKey)
            }
        }
    }

    private func observeSettingsChanges() {
        settings.$apiKey
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] apiKey in
                Task { @MainActor in
                    guard let self else { return }
                    self.invalidateSpeechCache()

                    if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.subscriptionRefreshTask?.cancel()
                        self.allVoices = []
                        self.voices = []
                        self.selectedVoice = nil
                        self.subscription = nil
                        self.subscriptionStatusMessage = nil
                        self.statusMessage = TTSProviderError.missingAPIKey.localizedDescription
                        return
                    }

                    await self.loadModelsAndVoices()
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

        settings.$providerID
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.invalidateSpeechCache() }
            }
            .store(in: &settingsCancellables)

        settings.$playbackRate
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] playbackRate in
                Task { @MainActor in
                    guard let self else { return }
                    self.audioPlayer.setPlaybackRate(playbackRate)

                    if self.isPlaying {
                        let remainingDuration = max(self.playbackDuration - self.audioPlayer.currentTime, 0)
                        self.schedulePlaybackCompletion(after: remainingDuration / max(playbackRate, 0.25))
                    }
                }
            }
            .store(in: &settingsCancellables)
    }

    private func finishPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        playbackCurrentTime = playbackDuration
        isPlaying = false
        statusMessage = "Playback finished."
    }

    private func ensureSelectedModelIsAvailable() {
        if models.contains(where: { $0.id == settings.modelID }) == false {
            settings.modelID = models.first?.id ?? "eleven_v3"
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
        self.selectedVoice = voices.first
    }

    private static func isUnavailableVoiceError(_ error: Error) -> Bool {
        guard case let TTSProviderError.httpStatus(_, message) = error else { return false }
        let lowercasedMessage = message.lowercased()
        return lowercasedMessage.contains("voice_not_found")
            || lowercasedMessage.contains("voice not found")
            || lowercasedMessage.contains("voice_id")
            || lowercasedMessage.contains("not available")
            || lowercasedMessage.contains("does not exist")
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
        let duplicateDescriptor = FetchDescriptor<SpeechHistoryRecord>()
        if let duplicateRecords = try? modelContext.fetch(duplicateDescriptor).filter({
            $0.requestKey == requestKey
        }) {
            duplicateRecords.forEach { modelContext.delete($0) }
        }
    }

    private func pruneHistory(modelContext: ModelContext, limit: Int) {
        var descriptor = FetchDescriptor<SpeechHistoryRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchOffset = limit

        if let oldRecords = try? modelContext.fetch(descriptor) {
            oldRecords.forEach { modelContext.delete($0) }
        }

        try? modelContext.save()
    }

    private static func historyRequestKey(for request: SpeechRequest) -> String {
        [
            request.text,
            request.voice.id,
            request.modelID,
            request.outputFormat,
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

    private static func fileExtension(for outputFormat: String) -> String {
        outputFormat.hasPrefix("wav") ? "wav" : "mp3"
    }
}
