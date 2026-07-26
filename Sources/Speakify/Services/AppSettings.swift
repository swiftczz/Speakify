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

package enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    package var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .system:
            return "System Default"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
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

    package var appAppearance: AppAppearance {
        didSet { defaults.set(appAppearance.rawValue, forKey: Keys.appAppearance) }
    }

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
        didSet { writeDraftText(draftText) }
    }

    private let defaults: UserDefaults
    private let draftTextURL: URL?

    package init(defaults: UserDefaults = .standard, draftTextURL: URL? = nil) {
        self.defaults = defaults
        // Tests pass their own location; nil means the shared one. Resolving it eagerly here
        // keeps the didSet off the filesystem-discovery path on every keystroke.
        self.draftTextURL = draftTextURL ?? (defaults == .standard ? AppDataLocation.draftTextURL() : nil)
        Self.migrateLegacyProviderValues(in: defaults)
        Self.migrateMiMoDefaultOutputFormat(in: defaults)

        let resolvedAppLanguage = AppLanguage(
            rawValue: defaults.string(forKey: Keys.appLanguage) ?? ""
        ) ?? .system
        appLanguage = resolvedAppLanguage

        appAppearance = AppAppearance(
            rawValue: defaults.string(forKey: Keys.appAppearance) ?? ""
        ) ?? .system

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
        draftText = Self.loadDraftText(
            url: self.draftTextURL,
            defaults: defaults
        )
        L10n.configure(language: resolvedAppLanguage)
    }

    /// Reads the draft file, falling back to the preferences key it used to live under so an
    /// existing draft survives the move, then clears that key so the plist does not keep a
    /// stale copy.
    private static func loadDraftText(url: URL?, defaults: UserDefaults) -> String {
        let migrated = defaults.string(forKey: Keys.draftText)
        if migrated != nil {
            defaults.removeObject(forKey: Keys.draftText)
        }

        if let url, let stored = try? String(contentsOf: url, encoding: .utf8) {
            return stored
        }
        if let migrated {
            if let url {
                try? migrated.write(to: url, atomically: true, encoding: .utf8)
            }
            return migrated
        }
        return defaultDraftText
    }

    private func writeDraftText(_ text: String) {
        guard let draftTextURL else {
            defaults.set(text, forKey: Keys.draftText)
            return
        }
        try? text.write(to: draftTextURL, atomically: true, encoding: .utf8)
    }

    var downloadDirectoryURL: URL {
        URL(filePath: downloadDirectoryPath, directoryHint: .isDirectory)
    }

    package var appLocale: Locale {
        appLanguage.locale
    }

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
        static let appAppearance = "appAppearance"
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
