@preconcurrency import AVFoundation
import Foundation

@MainActor
final class AudioPlaybackService {
    private var player: AVPlayer?
    private var playbackObserver: NSObjectProtocol?
    private var currentPlaybackFileURL: URL?
    private var sourceDuration: TimeInterval = 0
    private var playbackRate: Float = 1.0
    private var didFinishPlayback = false

    func play(data: Data, rate: Double, fileExtension: String) throws -> TimeInterval {
        stop()

        let playbackFileURL = try makePlaybackFile(from: data, fileExtension: fileExtension)
        currentPlaybackFileURL = playbackFileURL

        let durationPlayer = try AVAudioPlayer(data: data)
        sourceDuration = durationPlayer.duration
        didFinishPlayback = false
        setPlaybackRate(rate)

        let playerItem = AVPlayerItem(url: playbackFileURL)
        playerItem.audioTimePitchAlgorithm = .timeDomain

        let player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = false
        self.player = player

        playbackObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.finishPlayback()
            }
        }

        player.playImmediately(atRate: playbackRate)
        return sourceDuration
    }

    func duration(data: Data) throws -> TimeInterval {
        let player = try AVAudioPlayer(data: data)
        return player.duration
    }

    func setPlaybackRate(_ rate: Double) {
        playbackRate = Float(min(max(rate, 0.25), 2.0))
        if let player, player.timeControlStatus == .playing {
            player.rate = playbackRate
        }
    }

    var currentTime: TimeInterval {
        if didFinishPlayback {
            return sourceDuration
        }

        guard let player else {
            return 0
        }

        let seconds = player.currentTime().seconds
        guard seconds.isFinite else { return 0 }
        return min(sourceDuration, max(seconds, 0))
    }

    var duration: TimeInterval {
        sourceDuration
    }

    var isPlaying: Bool {
        guard let player else { return false }
        return didFinishPlayback == false && player.timeControlStatus == .playing
    }

    func stop() {
        if let playbackObserver {
            NotificationCenter.default.removeObserver(playbackObserver)
            self.playbackObserver = nil
        }

        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil

        if let currentPlaybackFileURL {
            try? FileManager.default.removeItem(at: currentPlaybackFileURL)
            self.currentPlaybackFileURL = nil
        }

        didFinishPlayback = false
        sourceDuration = 0
    }

    private func finishPlayback() {
        didFinishPlayback = true
        player?.pause()
    }

    private func makePlaybackFile(from data: Data, fileExtension: String) throws -> URL {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appending(path: "speakify-playback-\(UUID().uuidString).\(fileExtension)", directoryHint: .notDirectory)
        try data.write(to: temporaryURL, options: .atomic)
        return temporaryURL
    }
}
