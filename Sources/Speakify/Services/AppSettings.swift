import Foundation

package enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    package var id: String { rawValue }

    package var locale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        case .simplifiedChinese, .english:
            return Locale(identifier: rawValue)
        }
    }

    var localizationIdentifier: String? {
        self == .system ? nil : rawValue
    }

    var titleKey: String {
        switch self {
        case .system:
            return "System Default"
        case .simplifiedChinese:
            return "简体中文"
        case .english:
            return "English"
        }
    }
}

@Observable
package final class AppSettings {
    static let defaultDraftText = "The best way to improve listening is to hear natural English every day."

    package var appLanguage: AppLanguage {
        didSet {
            defaults.set(appLanguage.rawValue, forKey: Keys.appLanguage)
            L10n.configure(language: appLanguage)
        }
    }

    /// The active speech service. The provider-scoped values below (API key,
    /// model, output format) swap alongside it, so each service keeps its own
    /// setup and switching back restores exactly what was configured before.
    var providerID: String {
        didSet {
            defaults.set(providerID, forKey: Keys.providerID)
            guard oldValue != providerID else { return }
            loadProviderScopedValues()
        }
    }

    var apiKey: String {
        didSet { defaults.set(apiKey, forKey: Keys.scoped(Keys.apiKey, providerID)) }
    }

    var modelID: String {
        didSet { defaults.set(modelID, forKey: Keys.scoped(Keys.modelID, providerID)) }
    }

    var outputFormat: String {
        didSet { defaults.set(outputFormat, forKey: Keys.scoped(Keys.outputFormat, providerID)) }
    }

    var downloadDirectoryPath: String {
        didSet { defaults.set(downloadDirectoryPath, forKey: Keys.downloadDirectoryPath) }
    }

    var languageCode: String {
        didSet { defaults.set(languageCode, forKey: Keys.languageCode) }
    }

    var playbackRate: Double {
        didSet {
            let normalizedRate = Self.normalizedPlaybackRate(playbackRate)
            guard playbackRate == normalizedRate else {
                playbackRate = normalizedRate
                return
            }
            defaults.set(playbackRate, forKey: Keys.playbackRate)
        }
    }

    var draftText: String {
        didSet { defaults.set(draftText, forKey: Keys.draftText) }
    }

    private let defaults: UserDefaults

    package init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.migrateLegacyProviderValues(in: defaults)
        Self.migrateMiMoDefaultOutputFormat(in: defaults)

        let resolvedAppLanguage = AppLanguage(
            rawValue: defaults.string(forKey: Keys.appLanguage) ?? ""
        ) ?? .system
        appLanguage = resolvedAppLanguage

        let storedProviderID = defaults.string(forKey: Keys.providerID) ?? ""
        let providerID = TTSProviderRegistry.isKnown(storedProviderID)
            ? storedProviderID
            : TTSProviderRegistry.providers[0].id
        self.providerID = providerID

        let capabilities = TTSProviderRegistry.provider(withID: providerID).capabilities
        apiKey = defaults.string(forKey: Keys.scoped(Keys.apiKey, providerID)) ?? ""
        modelID = defaults.string(forKey: Keys.scoped(Keys.modelID, providerID))
            ?? capabilities.defaultModelID
        outputFormat = Self.validatedOutputFormat(
            defaults.string(forKey: Keys.scoped(Keys.outputFormat, providerID)),
            for: capabilities
        )

        downloadDirectoryPath = defaults.string(forKey: Keys.downloadDirectoryPath)
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path()
            ?? NSHomeDirectory()
        languageCode = defaults.string(forKey: Keys.languageCode) ?? SpeechLanguage.autoDetect
        playbackRate = Self.normalizedPlaybackRate(defaults.object(forKey: Keys.playbackRate) as? Double ?? 1.0)
        draftText = defaults.string(forKey: Keys.draftText) ?? Self.defaultDraftText
        L10n.configure(language: resolvedAppLanguage)
    }

    var downloadDirectoryURL: URL {
        URL(filePath: downloadDirectoryPath, directoryHint: .isDirectory)
    }

    package var appLocale: Locale {
        appLanguage.locale
    }

    /// Reads any provider's stored key, active or not, so Settings can edit all
    /// of them side by side.
    func apiKey(for providerID: String) -> String {
        guard providerID != self.providerID else { return apiKey }
        return defaults.string(forKey: Keys.scoped(Keys.apiKey, providerID)) ?? ""
    }

    func preferredVoiceID(providerID: String, apiKey: String) -> String? {
        defaults.string(
            forKey: Keys.preferredVoice(
                providerID: providerID,
                credentialFingerprint: CredentialScope.fingerprint(apiKey: apiKey)
            )
        )
    }

    func setPreferredVoiceID(_ voiceID: String, providerID: String, apiKey: String) {
        defaults.set(
            voiceID,
            forKey: Keys.preferredVoice(
                providerID: providerID,
                credentialFingerprint: CredentialScope.fingerprint(apiKey: apiKey)
            )
        )
    }

    func voiceSettings(for providerID: String) -> VoiceSettings {
        guard let data = defaults.data(forKey: Keys.scoped(Keys.voiceSettings, providerID)),
              let settings = try? JSONDecoder().decode(VoiceSettings.self, from: data) else {
            return VoiceSettings()
        }
        let capabilities = TTSProviderRegistry.provider(withID: providerID).capabilities
        return capabilities.voiceSettings?.normalized(settings) ?? settings
    }

    func setVoiceSettings(_ settings: VoiceSettings, for providerID: String) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Keys.scoped(Keys.voiceSettings, providerID))
    }

    private func loadProviderScopedValues() {
        let capabilities = TTSProviderRegistry.provider(withID: providerID).capabilities
        apiKey = defaults.string(forKey: Keys.scoped(Keys.apiKey, providerID)) ?? ""
        modelID = defaults.string(forKey: Keys.scoped(Keys.modelID, providerID))
            ?? capabilities.defaultModelID
        outputFormat = Self.validatedOutputFormat(
            defaults.string(forKey: Keys.scoped(Keys.outputFormat, providerID)),
            for: capabilities
        )
    }

    /// Early versions stored a single flat API key/model/format for the only
    /// provider (ElevenLabs); move those into the provider-scoped slots once.
    private static func migrateLegacyProviderValues(in defaults: UserDefaults) {
        for key in [Keys.apiKey, Keys.modelID, Keys.outputFormat] {
            let scopedKey = Keys.scoped(key, "elevenlabs")
            if let legacyValue = defaults.string(forKey: key),
               defaults.string(forKey: scopedKey) == nil {
                defaults.set(legacyValue, forKey: scopedKey)
            }
            defaults.removeObject(forKey: key)
        }
    }

    /// MiMo originally shipped as WAV-only, so early versions persisted WAV
    /// even when the user never made an explicit choice. Apply the new MP3
    /// default once; choosing WAV after this migration remains respected.
    private static func migrateMiMoDefaultOutputFormat(in defaults: UserDefaults) {
        guard defaults.bool(forKey: Keys.migratedMiMoMP3Default) == false else { return }

        let formatKey = Keys.scoped(Keys.outputFormat, "mimo")
        if defaults.string(forKey: formatKey) == nil
            || defaults.string(forKey: formatKey) == "wav" {
            defaults.set("mp3", forKey: formatKey)
        }
        defaults.set(true, forKey: Keys.migratedMiMoMP3Default)
    }

    private static func validatedOutputFormat(
        _ stored: String?,
        for capabilities: TTSProviderCapabilities
    ) -> String {
        guard let stored, capabilities.outputFormats.contains(stored) else {
            return capabilities.defaultOutputFormat
        }
        return stored
    }

    private enum Keys {
        static let appLanguage = "appLanguage"
        static let apiKey = "apiKey"
        static let downloadDirectoryPath = "downloadDirectoryPath"
        static let modelID = "modelID"
        static let outputFormat = "outputFormat"
        static let providerID = "providerID"
        static let languageCode = "languageCode"
        static let playbackRate = "playbackRate"
        static let draftText = "draftText"
        static let migratedMiMoMP3Default = "migration.mimoDefaultOutputFormat.mp3"
        static let voiceSettings = "voiceSettings"

        static func scoped(_ base: String, _ providerID: String) -> String {
            "\(base).\(providerID)"
        }

        static func preferredVoice(
            providerID: String,
            credentialFingerprint: String
        ) -> String {
            "preferredVoiceID.\(providerID).\(credentialFingerprint)"
        }
    }

    private static func normalizedPlaybackRate(_ value: Double) -> Double {
        let clampedValue = min(max(value, 0.25), 2.0)
        return (clampedValue * 4).rounded() / 4
    }
}
