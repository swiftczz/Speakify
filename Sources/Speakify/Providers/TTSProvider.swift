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

struct TTSProviderCapabilities: Sendable {
    let outputFormats: [String]
    let defaultOutputFormat: String
    let defaultModelID: String
    let reportsQuota: Bool
    let providesSubtitles: Bool
    let providesCharacterAlignment: Bool
    let acceptsLanguageHint: Bool
    let meteredSynthesis: Bool
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

struct TTSVoiceCatalog: Equatable, Sendable {
    let publicVoices: [TTSVoice]
    let accountVoices: [TTSVoice]
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
    var fallbackModels: [TTSModel] { get }

    func fetchModels(apiKey: String) async throws -> [TTSModel]
    func fetchVoiceCatalog(apiKey: String) async throws -> TTSVoiceCatalog
    func fetchQuota(apiKey: String) async throws -> TTSQuota?
    func synthesize(request: SpeechRequest, apiKey: String) async throws -> GeneratedSpeech
}

struct TTSProviderOption: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

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
