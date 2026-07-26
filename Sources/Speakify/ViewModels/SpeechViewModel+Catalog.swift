import Foundation

extension SpeechViewModel {
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
        let apiKey = settings.apiKey
        lastCatalogSignature = signature
        isLoadingVoices = true
        defer {
            if signature == catalogSignature {
                isLoadingVoices = false
            }
        }

        do {
            let cachedCatalog = await catalogCacheStore.catalog(
                providerID: provider.id,
                apiKey: apiKey
            )
            if let cachedCatalog, signature == catalogSignature, voices.isEmpty {
                publishCatalog(cachedCatalog)
            }

            updateStatus(
                L10n.format(
                    "status.loading-catalog",
                    defaultValue: "Loading %@ models and voices…",
                    provider.displayName
                ),
                tone: .info
            )
            async let loadedModels = modelsOrFallback(provider: provider, apiKey: apiKey)
            async let loadedCatalog = provider.fetchVoiceCatalog(apiKey: apiKey)

            let (models, refreshedCatalog) = try await (loadedModels, loadedCatalog)
            try Task.checkCancellation()
            guard signature == catalogSignature else { return }

            self.models = models
            ensureSelectedModelIsAvailable()
            let catalog: TTSVoiceCatalog
            if let failure = refreshedCatalog.accountFailure,
               let cachedCatalog,
               cachedCatalog.accountVoices.isEmpty == false {
                catalog = TTSVoiceCatalog(
                    publicVoices: refreshedCatalog.publicVoices,
                    accountVoices: cachedCatalog.accountVoices,
                    accountFailure: failure,
                    accountVoicesAreCached: true
                )
            } else {
                catalog = refreshedCatalog
            }
            publishCatalog(catalog)
            if refreshedCatalog.accountFailure == nil {
                await catalogCacheStore.store(
                    refreshedCatalog,
                    providerID: provider.id,
                    apiKey: apiKey
                )
            }

            let status = catalogStatus(for: catalog, apiKey: apiKey)
            updateStatus(status.message, tone: status.tone)
            isLoadingVoices = false
            await refreshQuota(apiKey: apiKey)
        } catch {
            guard Self.isCancellation(error) == false, signature == catalogSignature else {
                return
            }
            quota = nil
            quotaScopeIdentifier = nil
            quotaStatusMessage = nil
            updateStatus(error.localizedDescription, tone: .error)
        }
    }

    private func modelsOrFallback(
        provider: any TTSProvider,
        apiKey: String
    ) async -> [TTSModel] {
        do {
            let loadedModels = try await provider.fetchModels(apiKey: apiKey)
            return loadedModels.isEmpty ? provider.fallbackModels : loadedModels
        } catch {
            return provider.fallbackModels
        }
    }

    private func catalogStatus(
        for catalog: TTSVoiceCatalog,
        apiKey: String
    ) -> (message: String, tone: StatusTone) {
        guard voices.isEmpty == false else {
            return (
                L10n.string(
                    "status.no-compatible-voices",
                    defaultValue: "No compatible voices returned by the account."
                ),
                .error
            )
        }
        if let accountFailure = catalog.accountFailure {
            if catalog.accountVoicesAreCached {
                return (
                    L10n.format(
                        "status.loaded-cached-account",
                        defaultValue: "Loaded %1$lld public and %2$lld cached account voices. Account refresh failed: %3$@",
                        Int64(publicVoices.count),
                        Int64(accountVoices.count),
                        accountFailure
                    ),
                    .info
                )
            }
            return (
                L10n.format(
                    "status.account-voices-unavailable",
                    defaultValue: "Loaded %1$lld public voices. Account voices unavailable: %2$@",
                    Int64(voices.count),
                    accountFailure
                ),
                .error
            )
        }
        guard apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return (
                L10n.format(
                    "status.loaded-add-key",
                    defaultValue: "Loaded %lld voices. Add an API key to generate speech.",
                    Int64(voices.count)
                ),
                .info
            )
        }
        if accountVoices.isEmpty == false {
            return (
                L10n.format(
                    "status.loaded-public-account",
                    defaultValue: "Loaded %1$lld public and %2$lld account voices.",
                    Int64(publicVoices.count),
                    Int64(accountVoices.count)
                ),
                .success
            )
        }
        return (
            L10n.format(
                "status.loaded-compatible",
                defaultValue: "Loaded %lld compatible voices.",
                Int64(voices.count)
            ),
            .success
        )
    }

    func reloadCatalogForCredentialChange() async {
        invalidateSpeechCache()
        clearAccountScopedState()
        await loadModelsAndVoices()
    }

    private func clearAccountScopedState() {
        quotaRefreshTask?.cancel()
        let accountVoiceIDs = Set(accountVoices.map(\.id))
        allVoices.removeAll { accountVoiceIDs.contains($0.id) }
        voices.removeAll { accountVoiceIDs.contains($0.id) }
        accountVoices = []
        publicVoices = voices.filter { publicVoiceIDs.contains($0.id) }
        if let selectedVoice, accountVoiceIDs.contains(selectedVoice.id) {
            self.selectedVoice = voices.first
        }
        quota = nil
        quotaScopeIdentifier = nil
        quotaStatusMessage = nil
    }

    func handleProviderSwitch() async {
        quotaRefreshTask?.cancel()
        allVoices = []
        voices = []
        publicVoiceIDs = []
        publicVoices = []
        accountVoices = []
        selectedVoice = nil
        quota = nil
        quotaScopeIdentifier = nil
        quotaStatusMessage = nil
        models = activeProvider.fallbackModels
        voiceSettings = settings.voiceSettings(for: settings.providerID)
        await reloadCatalogForCredentialChange()
    }

    private func ensureSelectedModelIsAvailable() {
        if models.contains(where: { $0.id == settings.modelID }) == false {
            settings.modelID = models.first?.id ?? activeProvider.capabilities.defaultModelID
        }
    }

    func applyVoiceFilterForSelectedModel() {
        let selectedModel = models.first(where: { $0.id == settings.modelID })
        let modelServesProVoices = selectedModel?.servesProVoices ?? false

        voices = allVoices.filter { voice in
            modelServesProVoices || voice.isProfessionalVoice == false
        }
        publicVoices = voices.filter { publicVoiceIDs.contains($0.id) }
        accountVoices = voices.filter { publicVoiceIDs.contains($0.id) == false }

        let preferredVoiceID = pendingPreferredVoiceID
            ?? settings.preferredVoiceID(
                providerID: settings.providerID,
                apiKey: settings.apiKey
            )
        selectedVoice = selectedVoice.flatMap { current in
            voices.first(where: { $0.id == current.id })
        } ?? preferredVoiceID.flatMap { preferredID in
            voices.first(where: { $0.id == preferredID })
        } ?? voices.first
        pendingPreferredVoiceID = nil
    }

    func removeSelectedVoiceIfUnavailable(_ error: any Error) {
        guard let selectedVoice, Self.isUnavailableVoiceError(error) else { return }
        allVoices.removeAll { $0.id == selectedVoice.id }
        voices.removeAll { $0.id == selectedVoice.id }
        publicVoiceIDs.remove(selectedVoice.id)
        publicVoices.removeAll { $0.id == selectedVoice.id }
        accountVoices.removeAll { $0.id == selectedVoice.id }
        self.selectedVoice = voices.first
    }

    private func publishCatalog(_ catalog: TTSVoiceCatalog) {
        publicVoiceIDs = Set(catalog.publicVoices.map(\.id))
        allVoices = catalog.voices
        applyVoiceFilterForSelectedModel()
    }
}
