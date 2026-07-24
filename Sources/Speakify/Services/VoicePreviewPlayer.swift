import AVFoundation
import Combine
import Foundation

struct VoicePreviewConfiguration: Sendable {
    let provider: any TTSProvider
    let modelID: String
    let apiKey: String

    /// Previewing a voice without a provider-supplied sample means synthesizing one,
    /// which costs credits on a metered service. Those previews wait for a click.
    func requiresExplicitStart(for voice: TTSVoice) -> Bool {
        voice.previewURL == nil && provider.capabilities.meteredSynthesis
    }

    func canPreview(_ voice: TTSVoice) -> Bool {
        voice.previewURL != nil
            || provider.capabilities.requiresAPIKey == false
            || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    /// Identifies the credentials a preview was produced under without ever holding
    /// the key itself, so two accounts never share a cache entry for the same voice ID.
    var accountFingerprint: String {
        CredentialScope.fingerprint(apiKey: apiKey)
    }
}

/// Owned by one visible voice row. Updating a preview now invalidates only the
/// previous/current row instead of every row in a large account catalog.
@MainActor
final class VoicePreviewRowState: ObservableObject {
    @Published fileprivate(set) var isActive = false
    @Published fileprivate(set) var isPlaying = false
    @Published fileprivate(set) var errorMessage: String?
}

/// Plays a provider-supplied sample when one exists; otherwise it asks the
/// active provider to synthesize a short, provider-neutral preview phrase.
/// Preview playback stays isolated from generated speech playback.
@MainActor
final class VoicePreviewPlayer {
    private(set) var activeVoiceID: String?
    private(set) var isPlaying = false
    private(set) var errorVoiceID: String?
    private(set) var errorMessage: String?

    private let session: URLSession
    private let audioPlayer: AudioPlaybackService
    private let hoverDelay: Duration
    private let persistentCache: VoicePreviewCacheStore
    private let cache = NSCache<NSString, CachedPreview>()
    private var loadTask: Task<Void, Never>?
    private var playbackMonitorTask: Task<Void, Never>?
    private var activeRowState: VoicePreviewRowState?
    private var errorRowState: VoicePreviewRowState?

    init(
        session: URLSession = .shared,
        audioPlayer: AudioPlaybackService = AudioPlaybackService(),
        hoverDelay: Duration = .milliseconds(180),
        persistentCache: VoicePreviewCacheStore = VoicePreviewCacheStore()
    ) {
        self.session = session
        self.audioPlayer = audioPlayer
        self.hoverDelay = hoverDelay
        self.persistentCache = persistentCache
        cache.countLimit = 40
        cache.totalCostLimit = 20 * 1_024 * 1_024
        Task { await persistentCache.prune() }
    }

    /// Hover entry point: starts only when the preview is free to produce.
    func beginPreview(
        for voice: TTSVoice,
        configuration: VoicePreviewConfiguration,
        state: VoicePreviewRowState? = nil
    ) {
        guard configuration.canPreview(voice) else { return }
        guard configuration.requiresExplicitStart(for: voice) == false else { return }
        start(for: voice, configuration: configuration, state: state)
    }

    private func start(
        for voice: TTSVoice,
        configuration: VoicePreviewConfiguration,
        state: VoicePreviewRowState?
    ) {
        guard configuration.canPreview(voice) else { return }
        guard activeVoiceID != voice.id else { return }

        stop()
        let rowState = state ?? VoicePreviewRowState()
        activeRowState = rowState
        activeVoiceID = voice.id
        rowState.isActive = true
        rowState.errorMessage = nil

        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(for: hoverDelay)
                try Task.checkCancellation()

                let preview = try await loadPreview(
                    for: voice,
                    configuration: configuration
                )
                try Task.checkCancellation()
                guard activeVoiceID == voice.id else { return }

                _ = try audioPlayer.play(
                    data: preview.data,
                    rate: 1,
                    fileExtension: preview.fileExtension
                )
                isPlaying = true
                rowState.isPlaying = true
                monitorPlayback(for: voice.id)
            } catch is CancellationError {
                return
            } catch {
                if activeVoiceID == voice.id {
                    loadTask = nil
                    playbackMonitorTask?.cancel()
                    playbackMonitorTask = nil
                    audioPlayer.stop()
                    activeVoiceID = nil
                    isPlaying = false
                    errorVoiceID = voice.id
                    errorMessage = error.localizedDescription
                    rowState.isActive = false
                    rowState.isPlaying = false
                    rowState.errorMessage = error.localizedDescription
                    errorRowState = rowState
                    activeRowState = nil
                }
            }
        }
    }

    func endPreview(for voiceID: String) {
        guard activeVoiceID == voiceID else { return }
        stop()
    }

    func togglePreview(
        for voice: TTSVoice,
        configuration: VoicePreviewConfiguration,
        state: VoicePreviewRowState? = nil
    ) {
        if activeVoiceID == voice.id {
            stop()
        } else {
            // An explicit click is the consent a metered preview needs.
            start(for: voice, configuration: configuration, state: state)
        }
    }

    func stop() {
        loadTask?.cancel()
        playbackMonitorTask?.cancel()
        loadTask = nil
        playbackMonitorTask = nil
        audioPlayer.stop()
        activeRowState?.isActive = false
        activeRowState?.isPlaying = false
        activeVoiceID = nil
        isPlaying = false
        errorVoiceID = nil
        errorMessage = nil
        errorRowState?.errorMessage = nil
        errorRowState = nil
        activeRowState = nil
    }

    func clearError(for voiceID: String, state: VoicePreviewRowState? = nil) {
        guard errorVoiceID == voiceID else { return }
        errorVoiceID = nil
        errorMessage = nil
        (state ?? errorRowState)?.errorMessage = nil
        errorRowState = nil
    }

    private func monitorPlayback(for voiceID: String) {
        playbackMonitorTask?.cancel()
        playbackMonitorTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while Task.isCancelled == false, activeVoiceID == voiceID {
                try? await Task.sleep(for: .milliseconds(100))
                guard Task.isCancelled == false else { return }
                if audioPlayer.isPlaying == false {
                    activeRowState?.isActive = false
                    activeRowState?.isPlaying = false
                    activeVoiceID = nil
                    isPlaying = false
                    activeRowState = nil
                    return
                }
            }
        }
    }

    private func loadPreview(
        for voice: TTSVoice,
        configuration: VoicePreviewConfiguration
    ) async throws -> CachedPreview {
        let cacheKeyValue = VoicePreviewCacheStore.cacheKey(
            providerID: configuration.provider.id,
            modelID: configuration.modelID,
            credentialFingerprint: configuration.accountFingerprint,
            voiceID: voice.id
        )
        let cacheKey = cacheKeyValue as NSString
        if let cachedPreview = cache.object(forKey: cacheKey) {
            return cachedPreview
        }
        if let persisted = await persistentCache.preview(for: cacheKeyValue) {
            let preview = CachedPreview(
                data: persisted.data,
                fileExtension: persisted.fileExtension
            )
            cache.setObject(preview, forKey: cacheKey, cost: preview.data.count)
            return preview
        }

        let preview: CachedPreview
        if let previewURL = voice.previewURL {
            preview = try await downloadPreview(from: previewURL)
        } else {
            let provider = configuration.provider
            let request = SpeechRequest(
                text: Self.previewText(for: voice),
                voice: voice,
                modelID: configuration.modelID.isEmpty
                    ? provider.capabilities.defaultModelID
                    : configuration.modelID,
                outputFormat: provider.capabilities.defaultOutputFormat,
                languageCode: nil,
                voiceSettings: VoiceSettings()
            )
            let generated = try await provider.synthesize(
                request: request,
                apiKey: configuration.apiKey
            )
            preview = CachedPreview(
                data: generated.audioData,
                fileExtension: generated.fileExtension
            )
        }

        cache.setObject(preview, forKey: cacheKey, cost: preview.data.count)
        await persistentCache.store(
            CachedVoicePreview(data: preview.data, fileExtension: preview.fileExtension),
            for: cacheKeyValue
        )
        return preview
    }

    private func downloadPreview(from url: URL) async throws -> CachedPreview {
        var request = URLRequest(
            url: url,
            cachePolicy: .returnCacheDataElseLoad,
            timeoutInterval: 30
        )
        request.setValue("audio/*", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              data.isEmpty == false else {
            throw URLError(.badServerResponse)
        }

        let fileExtension = response.mimeType?.localizedCaseInsensitiveContains("wav") == true
            ? "wav"
            : "mp3"
        return CachedPreview(data: data, fileExtension: fileExtension)
    }

    private static func previewText(for voice: TTSVoice) -> String {
        let language = voice.language?.lowercased() ?? ""
        let locale = voice.locale?.lowercased() ?? ""

        if language.contains("chinese") || locale.hasPrefix("zh") {
            return "你好，很高兴认识你。"
        }
        if language.contains("japanese") || locale.hasPrefix("ja") {
            return "こんにちは。よろしくお願いします。"
        }
        if language.contains("korean") || locale.hasPrefix("ko") {
            return "안녕하세요. 만나서 반가워요."
        }
        return "Hello, it is nice to meet you."
    }
}

private final class CachedPreview {
    let data: Data
    let fileExtension: String

    init(data: Data, fileExtension: String) {
        self.data = data
        self.fileExtension = fileExtension
    }
}
