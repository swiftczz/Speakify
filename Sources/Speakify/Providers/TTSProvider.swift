import Foundation

enum TTSCreditPolicy: Sendable {
    case none
    case characters(defaultMultiplier: Double, modelMultipliers: [String: Double])

    func estimatedCost(characterCount: Int, modelID: String) -> Int {
        let normalizedCount = max(characterCount, 0)
        switch self {
        case .none:
            return 0
        case let .characters(defaultMultiplier, modelMultipliers):
            let multiplier = modelMultipliers[modelID] ?? defaultMultiplier
            return Int(ceil(Double(normalizedCount) * multiplier))
        }
    }
}

struct TTSVoiceSettingsCapabilities: Sendable {
    let stabilityRange: ClosedRange<Double>
    let similarityRange: ClosedRange<Double>
    let styleRange: ClosedRange<Double>
    let speedRange: ClosedRange<Double>
    let modelsWithoutSpeed: Set<String>
    let supportsSpeakerBoost: Bool

    func supportsSpeed(modelID: String) -> Bool {
        modelsWithoutSpeed.contains(modelID) == false
    }

    func normalized(_ settings: VoiceSettings) -> VoiceSettings {
        VoiceSettings(
            stability: settings.stability.clamped(to: stabilityRange),
            similarityBoost: settings.similarityBoost.clamped(to: similarityRange),
            style: settings.style.clamped(to: styleRange),
            speed: settings.speed.clamped(to: speedRange),
            speakerBoost: settings.speakerBoost
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// What a speech service can do, so the UI and view model adapt to the active
/// provider without ever switching on a concrete type.
struct TTSProviderCapabilities: Sendable {
    /// Formats the service can return, in the order they should be offered.
    let outputFormats: [String]
    let defaultOutputFormat: String
    let defaultModelID: String
    /// Whether the service reports a character quota worth showing in the sidebar.
    let reportsQuota: Bool
    /// Whether downloads should include an SRT subtitle.
    let providesSubtitles: Bool
    /// Whether subtitle export can use provider-supplied character timestamps.
    /// Providers without timestamps can still export an estimated SRT.
    let providesCharacterAlignment: Bool
    /// Whether the service accepts an explicit language hint.
    let acceptsLanguageHint: Bool
    /// Whether synthesis draws down a paid balance. Voice previews that have to be
    /// synthesized are put behind an explicit click on metered services rather than
    /// firing on hover.
    let meteredSynthesis: Bool
    /// Shown under the provider's API key field in Settings.
    let apiKeyHint: String
    let requiresAPIKey: Bool
    let defaultCharacterLimit: Int
    let modelCharacterLimits: [String: Int]
    let creditPolicy: TTSCreditPolicy
    let voiceSettings: TTSVoiceSettingsCapabilities?

    init(
        outputFormats: [String],
        defaultOutputFormat: String,
        defaultModelID: String,
        reportsQuota: Bool,
        providesSubtitles: Bool,
        providesCharacterAlignment: Bool,
        acceptsLanguageHint: Bool,
        meteredSynthesis: Bool,
        apiKeyHint: String,
        requiresAPIKey: Bool = true,
        defaultCharacterLimit: Int = TTSLimits.maxCharacterCount,
        modelCharacterLimits: [String: Int] = [:],
        creditPolicy: TTSCreditPolicy = .none,
        voiceSettings: TTSVoiceSettingsCapabilities? = nil
    ) {
        self.outputFormats = outputFormats
        self.defaultOutputFormat = defaultOutputFormat
        self.defaultModelID = defaultModelID
        self.reportsQuota = reportsQuota
        self.providesSubtitles = providesSubtitles
        self.providesCharacterAlignment = providesCharacterAlignment
        self.acceptsLanguageHint = acceptsLanguageHint
        self.meteredSynthesis = meteredSynthesis
        self.apiKeyHint = apiKeyHint
        self.requiresAPIKey = requiresAPIKey
        self.defaultCharacterLimit = defaultCharacterLimit
        self.modelCharacterLimits = modelCharacterLimits
        self.creditPolicy = creditPolicy
        self.voiceSettings = voiceSettings
    }

    func characterLimit(for modelID: String) -> Int {
        modelCharacterLimits[modelID] ?? defaultCharacterLimit
    }

    func estimatedCreditCost(characterCount: Int, modelID: String) -> Int {
        creditPolicy.estimatedCost(characterCount: characterCount, modelID: modelID)
    }
}

/// Keeps provider-supplied voices grouped by their source while exposing the
/// de-duplicated order used by the picker: public voices first, account voices
/// second.
struct TTSVoiceCatalog: Equatable, Sendable {
    let publicVoices: [TTSVoice]
    let accountVoices: [TTSVoice]
    /// Set when the account-scoped half of the catalog could not be loaded while the
    /// public half succeeded, so the picker can still fill up and the UI can explain
    /// what is missing instead of failing the whole load.
    let accountFailure: String?
    let accountVoicesAreCached: Bool

    init(
        publicVoices: [TTSVoice],
        accountVoices: [TTSVoice],
        accountFailure: String? = nil,
        accountVoicesAreCached: Bool = false
    ) {
        self.publicVoices = Self.unique(publicVoices)
        let publicIDs = Set(self.publicVoices.map(\.id))
        self.accountVoices = Self.unique(accountVoices).filter { publicIDs.contains($0.id) == false }
        self.accountFailure = accountFailure
        self.accountVoicesAreCached = accountVoicesAreCached
    }

    var voices: [TTSVoice] {
        publicVoices + accountVoices
    }

    private static func unique(_ voices: [TTSVoice]) -> [TTSVoice] {
        var seenIDs = Set<String>()
        return voices.filter { seenIDs.insert($0.id).inserted }
    }
}

protocol TTSProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var capabilities: TTSProviderCapabilities { get }
    /// Offline stand-ins shown until the real catalog is fetched. Services with
    /// a fixed catalog may simply return these from `fetchModels`.
    var fallbackModels: [TTSModel] { get }

    func fetchModels(apiKey: String) async throws -> [TTSModel]
    func fetchVoiceCatalog(apiKey: String) async throws -> TTSVoiceCatalog
    /// `nil` when the service has no quota to report (see `capabilities.reportsQuota`).
    func fetchQuota(apiKey: String) async throws -> TTSQuota?
    func synthesize(request: SpeechRequest, apiKey: String) async throws -> GeneratedSpeech
}

/// A lightweight identity for pickers and switchers, so views never need the
/// full provider object just to render a name.
struct TTSProviderOption: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

/// The fixed set of speech services the app ships with. The first entry is the
/// default for fresh installs and the fallback for unknown stored IDs.
enum TTSProviderRegistry {
    static let providers: [any TTSProvider] = [ElevenLabsProvider(), MiMoProvider()]

    static var options: [TTSProviderOption] {
        providers.map { TTSProviderOption(id: $0.id, name: $0.displayName) }
    }

    static func provider(withID id: String) -> any TTSProvider {
        providers.first { $0.id == id } ?? providers[0]
    }

    static func isKnown(_ id: String) -> Bool {
        providers.contains { $0.id == id }
    }
}
