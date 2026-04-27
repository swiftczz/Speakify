import Foundation

protocol TTSProvider: Sendable {
    var id: String { get }
    var displayName: String { get }

    func fetchModels(apiKey: String) async throws -> [TTSModel]
    func fetchVoices(apiKey: String) async throws -> [TTSVoice]
    func fetchSubscription(apiKey: String) async throws -> ElevenLabsSubscription
    func synthesize(request: SpeechRequest, apiKey: String) async throws -> GeneratedSpeech
}
