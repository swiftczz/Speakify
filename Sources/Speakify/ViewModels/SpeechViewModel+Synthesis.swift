import CryptoKit
import Foundation

extension SpeechViewModel {
    func currentSpeech(
        refreshQuotaOnCacheHit: Bool = false,
        requireAlignment: Bool = false
    ) async throws -> GeneratedSpeech {
        let request = try makeRequest()
        let requestScope = catalogSignature
        if let lastSpeech,
           lastSpeechScope == requestScope,
           lastSpeech.request == request,
           requireAlignment == false || lastSpeech.alignment?.isValid == true {
            hasCachedSpeechForCurrentRequest = true
            if refreshQuotaOnCacheHit {
                await refreshQuota(apiKey: settings.apiKey)
            }
            return lastSpeech
        }

        if let cachedSpeech = await cacheStore.speech(
            for: request,
            key: audioCacheKey(for: request, scopeIdentifier: requestScope)
        ),
           requireAlignment == false || cachedSpeech.alignment?.isValid == true {
            if refreshQuotaOnCacheHit {
                await refreshQuota(apiKey: settings.apiKey)
            }
            try playback.measureAndPrepare(data: cachedSpeech.audioData)
            lastSpeech = cachedSpeech
            lastSpeechScope = requestScope
            hasCachedSpeechForCurrentRequest = true
            updateStatus(
                L10n.string("status.loaded-cache", defaultValue: "Loaded cached speech."),
                tone: .success
            )
            return cachedSpeech
        }

        lastSpeech = nil
        lastSpeechScope = nil
        resetPlaybackForNewSpeech()

        let provider = activeProvider
        let apiKey = settings.apiKey
        let task = Task { try await provider.synthesize(request: request, apiKey: apiKey) }

        generationToken += 1
        let token = generationToken
        synthesisTask = task
        isGenerating = true
        updateStatus(
            L10n.string("status.generating", defaultValue: "Generating speech…"),
            tone: .info
        )
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
        guard requestScope == catalogSignature else {
            throw TTSProviderError.requestChanged
        }
        guard request == (try? makeRequest()) else {
            throw TTSProviderError.requestChanged
        }
        scheduleQuotaRefreshAfterGeneration(apiKey: apiKey)
        try playback.measureAndPrepare(data: generated.audioData)
        lastSpeech = generated
        lastSpeechScope = requestScope
        hasCachedSpeechForCurrentRequest = true
        let cacheKey = audioCacheKey(
            for: generated.request,
            scopeIdentifier: requestScope
        )
        Task { [cacheStore] in await cacheStore.store(generated, key: cacheKey) }
        return generated
    }

    private func makeRequest() throws -> SpeechRequest {
        let trimmedText = self.trimmedText
        guard trimmedText.isEmpty == false else {
            throw TTSProviderError.invalidText
        }
        guard trimmedText.count <= characterLimit else {
            throw TTSProviderError.textTooLong(count: trimmedText.count, limit: characterLimit)
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

    private func resetPlaybackForNewSpeech() {
        playback.reset()
    }

    func invalidateSpeechCache() {
        cancelGeneration()
        cacheAvailabilityTask?.cancel()
        hasCachedSpeechForCurrentRequest = false

        if lastSpeech != nil
            || playback.currentTime > 0
            || playback.duration > 0
            || playback.isPlaying {
            lastSpeech = nil
            lastSpeechScope = nil
            resetPlaybackForNewSpeech()
        }

        scheduleCacheAvailabilityCheck()
    }

    private struct CacheAvailabilityLookup: Equatable, Sendable {
        let request: SpeechRequest
        let key: String
    }

    private func currentCacheAvailabilityLookup() -> CacheAvailabilityLookup? {
        guard let request = try? makeRequest() else { return nil }
        let key = audioCacheKey(
            for: request,
            scopeIdentifier: catalogSignature
        )
        return CacheAvailabilityLookup(request: request, key: key)
    }

    private func scheduleCacheAvailabilityCheck() {
        cacheAvailabilityTask?.cancel()
        guard let lookup = currentCacheAvailabilityLookup() else { return }

        let cacheStore = self.cacheStore
        cacheAvailabilityTask = Task { @MainActor [weak self] in
            try? await Task.sleep(
                for: self?.cacheAvailabilityDebounceInterval ?? .milliseconds(150)
            )
            guard Task.isCancelled == false else { return }

            let isCached = await cacheStore.containsSpeech(
                for: lookup.request,
                key: lookup.key
            )
            guard let self,
                  Task.isCancelled == false,
                  self.currentCacheAvailabilityLookup() == lookup else {
                return
            }
            self.hasCachedSpeechForCurrentRequest = isCached
        }
    }

    private func audioCacheKey(
        for request: SpeechRequest,
        scopeIdentifier: String
    ) -> String {
        let source = [
            scopeIdentifier,
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
        let digest = SHA256.hash(data: Data(source.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
