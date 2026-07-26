extension SpeechViewModel {
    func applyHistoryDraft(_ draft: SpeechHistoryDraft) async {
        text = draft.text

        guard draft.providerID.isEmpty == false,
              TTSProviderRegistry.isKnown(draft.providerID) else {
            updateStatus(
                L10n.string(
                    "status.history-text-restored",
                    defaultValue: "History text restored to the editor."
                ),
                tone: .info
            )
            return
        }

        pendingPreferredVoiceID = draft.voiceID
        let providerChanged = settings.providerID != draft.providerID
        if providerChanged {
            suppressNextProviderReload = true
            settings.providerID = draft.providerID
        }
        let capabilities = activeProvider.capabilities
        settings.modelID = draft.modelID.isEmpty ? capabilities.defaultModelID : draft.modelID
        settings.outputFormat = capabilities.outputFormats.contains(draft.outputFormat)
            ? draft.outputFormat
            : capabilities.defaultOutputFormat
        settings.languageCode = capabilities.acceptsLanguageHint ? draft.languageCode : ""
        voiceSettings = capabilities.voiceSettings?.normalized(draft.voiceSettings)
            ?? VoiceSettings()

        if providerChanged {
            await handleProviderSwitch()
        } else {
            await loadModelsAndVoices()
        }
        updateStatus(
            L10n.string(
                "status.history-restored",
                defaultValue: "History settings restored to the editor."
            ),
            tone: .info
        )
    }
}
