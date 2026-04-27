import Combine
import Foundation

final class AppSettings: ObservableObject {
    @Published var apiKey: String {
        didSet { KeychainStore.saveAPIKey(apiKey) }
    }

    @Published var downloadDirectoryPath: String {
        didSet { defaults.set(downloadDirectoryPath, forKey: Keys.downloadDirectoryPath) }
    }

    @Published var modelID: String {
        didSet { defaults.set(modelID, forKey: Keys.modelID) }
    }

    @Published var outputFormat: String {
        didSet { defaults.set(outputFormat, forKey: Keys.outputFormat) }
    }

    @Published var providerID: String {
        didSet { defaults.set(providerID, forKey: Keys.providerID) }
    }

    @Published var playbackRate: Double {
        didSet {
            let normalizedRate = Self.normalizedPlaybackRate(playbackRate)
            guard playbackRate == normalizedRate else {
                playbackRate = normalizedRate
                return
            }
            defaults.set(playbackRate, forKey: Keys.playbackRate)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        apiKey = KeychainStore.readAPIKey()
        downloadDirectoryPath = defaults.string(forKey: Keys.downloadDirectoryPath)
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path()
            ?? NSHomeDirectory()
        modelID = defaults.string(forKey: Keys.modelID) ?? "eleven_v3"
        outputFormat = defaults.string(forKey: Keys.outputFormat) ?? "mp3_44100_128"
        providerID = defaults.string(forKey: Keys.providerID) ?? "elevenlabs"
        playbackRate = Self.normalizedPlaybackRate(defaults.object(forKey: Keys.playbackRate) as? Double ?? 1.0)
    }

    var downloadDirectoryURL: URL {
        URL(filePath: downloadDirectoryPath, directoryHint: .isDirectory)
    }

    private enum Keys {
        static let downloadDirectoryPath = "downloadDirectoryPath"
        static let modelID = "modelID"
        static let outputFormat = "outputFormat"
        static let providerID = "providerID"
        static let playbackRate = "playbackRate"
    }

    private static func normalizedPlaybackRate(_ value: Double) -> Double {
        let clampedValue = min(max(value, 0.25), 2.0)
        return (clampedValue * 4).rounded() / 4
    }
}
