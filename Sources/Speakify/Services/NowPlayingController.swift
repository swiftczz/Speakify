import Foundation
import MediaPlayer

/// Publishes what is playing to the system, so the media keys, Control Center and
/// the Now Playing widget can drive Speakify like any other audio app.
///
/// Speakify has no true pause — stopping releases the player and rewinds — so the
/// remote pause/stop commands are wired to the same stop the transport bar performs,
/// and play re-synthesizes or replays from the cache exactly as the play button does.
@MainActor
final class NowPlayingController {
    private var isConfigured = false
    private var onPlay: (() -> Void)?
    private var onStop: (() -> Void)?

    /// Registered once, on first playback: claiming the remote commands at launch
    /// would put a silent app in the Now Playing slot.
    func configure(onPlay: @escaping () -> Void, onStop: @escaping () -> Void) {
        self.onPlay = onPlay
        self.onStop = onStop
        guard isConfigured == false else { return }
        isConfigured = true

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self, let onPlay = self.onPlay else { return .commandFailed }
            onPlay()
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self, let onStop = self.onStop else { return .commandFailed }
            onStop()
            return .success
        }
        commandCenter.stopCommand.addTarget { [weak self] _ in
            guard let self, let onStop = self.onStop else { return .commandFailed }
            onStop()
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if MPNowPlayingInfoCenter.default().playbackState == .playing {
                self.onStop?()
            } else {
                self.onPlay?()
            }
            return .success
        }
    }

    func update(
        title: String,
        voiceName: String,
        duration: TimeInterval,
        elapsed: TimeInterval,
        rate: Double
    ) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: voiceName,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: rate,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        MPNowPlayingInfoCenter.default().playbackState = .playing
    }

    func updateElapsed(_ elapsed: TimeInterval) {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    /// A readable one-line title for a block of prose.
    static func title(for text: String) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.isEmpty == false else { return "Speakify" }
        return String(collapsed.prefix(60)) + (collapsed.count > 60 ? "…" : "")
    }
}
