import Combine
import Foundation

/// Owns the high-frequency playback state separately from the speech catalog.
///
/// Progress changes ten times per second while audio is playing. Keeping those
/// publications here prevents the editor, toolbar, voice catalog and sidebar from
/// being invalidated for every playback tick.
@MainActor
final class PlaybackStore: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    private let audioPlayer: AudioPlaybackService

    init(audioPlayer: AudioPlaybackService = AudioPlaybackService()) {
        self.audioPlayer = audioPlayer
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    var timeText: String {
        "\(Self.formattedTime(currentTime)) / \(Self.formattedTime(duration))"
    }

    @discardableResult
    func play(data: Data, rate: Double, fileExtension: String) throws -> TimeInterval {
        let measuredDuration = try audioPlayer.play(
            data: data,
            rate: rate,
            fileExtension: fileExtension
        )
        currentTime = 0
        duration = measuredDuration
        isPlaying = true
        return measuredDuration
    }

    func measureAndPrepare(data: Data) throws {
        duration = try audioPlayer.duration(data: data)
        currentTime = 0
        isPlaying = false
    }

    func measuredDuration(data: Data) throws -> TimeInterval {
        try audioPlayer.duration(data: data)
    }

    func setPlaybackRate(_ rate: Double) {
        audioPlayer.setPlaybackRate(rate)
    }

    /// Returns `true` exactly once when active playback reaches its end.
    func refresh() -> Bool {
        guard isPlaying else { return false }

        if audioPlayer.duration > 0 {
            duration = audioPlayer.duration
        }
        currentTime = min(audioPlayer.currentTime, duration)

        guard audioPlayer.isPlaying == false else { return false }
        currentTime = duration
        isPlaying = false
        return true
    }

    func stop() {
        audioPlayer.stop()
        currentTime = 0
        isPlaying = false
    }

    func reset() {
        audioPlayer.stop()
        currentTime = 0
        duration = 0
        isPlaying = false
    }

    private static func formattedTime(_ duration: TimeInterval) -> String {
        let seconds = max(Int(duration.rounded()), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
