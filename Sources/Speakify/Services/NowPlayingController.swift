import Foundation
import MediaPlayer

@MainActor
final class NowPlayingController {
    private var isConfigured = false
    private var onPlay: (() -> Void)?
    private var onStop: (() -> Void)?

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

    static func title(for text: String) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.isEmpty == false else { return "Speakify" }
        return String(collapsed.prefix(60)) + (collapsed.count > 60 ? "…" : "")
    }
}
