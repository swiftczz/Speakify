import Foundation
import Observation

extension SpeechViewModel {
    func flushPendingDraft() {
        guard draftSaveTask != nil else { return }
        draftSaveTask?.cancel()
        draftSaveTask = nil
        settings.draftText = text
    }

    func scheduleDraftSave() {
        draftSaveTask?.cancel()
        let draft = text
        draftSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.draftSaveDelay ?? .milliseconds(400))
            guard Task.isCancelled == false else { return }
            self?.settings.draftText = draft
        }
    }

    func refreshQuota(apiKey: String? = nil) async {
        let provider = activeProvider
        guard provider.capabilities.reportsQuota else {
            quota = nil
            quotaScopeIdentifier = nil
            quotaStatusMessage = nil
            return
        }

        let resolvedAPIKey = (apiKey ?? settings.apiKey)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let signature = CredentialScope.identifier(
            providerID: provider.id,
            apiKey: resolvedAPIKey
        )

        guard resolvedAPIKey.isEmpty == false else {
            quota = nil
            quotaScopeIdentifier = nil
            quotaStatusMessage = nil
            return
        }

        do {
            let refreshedQuota = try await provider.fetchQuota(apiKey: resolvedAPIKey)
            guard signature == quotaSignature else { return }
            quotaScopeIdentifier = refreshedQuota == nil ? nil : signature
            quota = refreshedQuota
            quotaStatusMessage = nil
        } catch {
            guard Self.isCancellation(error) == false, signature == quotaSignature else {
                return
            }
            quota = nil
            quotaScopeIdentifier = nil
            quotaStatusMessage = error.localizedDescription
        }
    }

    func scheduleQuotaRefreshAfterGeneration(apiKey: String) {
        quotaRefreshTask?.cancel()
        guard activeProvider.capabilities.reportsQuota else { return }
        let resolvedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard resolvedAPIKey.isEmpty == false else { return }

        let quotaBeforeGeneration = quota
        quotaRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for attempt in 0..<6 {
                if attempt > 0 {
                    try? await Task.sleep(for: .seconds(5))
                }
                guard Task.isCancelled == false else { return }
                await self.refreshQuota(apiKey: resolvedAPIKey)
                if let refreshedQuota = self.quota, refreshedQuota != quotaBeforeGeneration {
                    return
                }
            }
        }
    }

    private var quotaSignature: String {
        CredentialScope.identifier(
            providerID: activeProvider.id,
            apiKey: settings.apiKey
        )
    }

    private struct SettingsSnapshot: Equatable, Sendable {
        var appLanguage: AppLanguage
        var providerID: String
        var apiKey: String
        var modelID: String
        var outputFormat: String
        var languageCode: String
        var playbackRate: Double
    }

    private func currentSettingsSnapshot() -> SettingsSnapshot {
        SettingsSnapshot(
            appLanguage: settings.appLanguage,
            providerID: settings.providerID,
            apiKey: settings.apiKey,
            modelID: settings.modelID,
            outputFormat: settings.outputFormat,
            languageCode: settings.languageCode,
            playbackRate: settings.playbackRate
        )
    }

    func observeSettingsChanges() {
        observeSettingsChanges(previous: nil)
    }

    private func observeSettingsChanges(previous: SettingsSnapshot?) {
        let baseline = previous ?? currentSettingsSnapshot()
        withObservationTracking {
            _ = settings.appLanguage
            _ = settings.providerID
            _ = settings.apiKey
            _ = settings.modelID
            _ = settings.outputFormat
            _ = settings.languageCode
            _ = settings.playbackRate
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let current = self.currentSettingsSnapshot()
                self.reactToSettingsChange(from: baseline, to: current)
                self.observeSettingsChanges(previous: current)
            }
        }
    }

    private func reactToSettingsChange(from old: SettingsSnapshot, to new: SettingsSnapshot) {
        if old.appLanguage != new.appLanguage {
            updateStatus(
                L10n.string("status.language-updated", defaultValue: "Language updated."),
                tone: .info
            )
        }
        if old.providerID != new.providerID {
            if suppressNextProviderReload {
                suppressNextProviderReload = false
            } else {
                Task { await handleProviderSwitch() }
            }
        }
        if old.apiKey != new.apiKey {
            scheduleCredentialReload()
        }
        if old.modelID != new.modelID {
            applyVoiceFilterForSelectedModel()
            invalidateSpeechCache()
        }
        if old.outputFormat != new.outputFormat {
            invalidateSpeechCache()
        }
        if old.languageCode != new.languageCode {
            invalidateSpeechCache()
        }
        if old.playbackRate != new.playbackRate {
            playback.setPlaybackRate(new.playbackRate)
        }
    }

    private func scheduleCredentialReload() {
        credentialReloadTask?.cancel()
        credentialReloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.apiKeyDebounceInterval ?? .milliseconds(800))
            guard let self, Task.isCancelled == false else { return }
            guard self.lastCatalogSignature != self.catalogSignature else { return }
            await self.reloadCatalogForCredentialChange()
        }
    }
}
