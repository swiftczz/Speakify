import AVFoundation
import Foundation

@MainActor
final class AudioPlaybackService {
    private var player: AVAudioPlayer?
    private var playbackRate: Float = 1.0

    func play(data: Data, rate: Double, fileExtension: String) throws -> TimeInterval {
        stop()

        let player = try AVAudioPlayer(data: data, fileTypeHint: Self.fileTypeHint(for: fileExtension))
        player.enableRate = true
        player.prepareToPlay()
        self.player = player

        setPlaybackRate(rate)
        player.play()
        return player.duration
    }

    func duration(data: Data) throws -> TimeInterval {
        try AVAudioPlayer(data: data).duration
    }

    func setPlaybackRate(_ rate: Double) {
        playbackRate = Float(min(max(rate, 0.25), 2.0))
        player?.rate = playbackRate
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(time, 0), player.duration)
    }

    var currentTime: TimeInterval {
        guard let player else { return 0 }
        return min(max(player.currentTime, 0), player.duration)
    }

    var duration: TimeInterval {
        player?.duration ?? 0
    }

    var isPlaying: Bool {
        player?.isPlaying ?? false
    }

    var hasLoadedAudio: Bool {
        player != nil
    }

    func pause() {
        player?.pause()
    }

    func resume() {
        guard let player else { return }
        player.rate = playbackRate
        player.play()
    }

    func stop() {
        player?.stop()
        player = nil
    }

    private static func fileTypeHint(for fileExtension: String) -> String {
        fileExtension == "wav" ? AVFileType.wav.rawValue : AVFileType.mp3.rawValue
    }
}
