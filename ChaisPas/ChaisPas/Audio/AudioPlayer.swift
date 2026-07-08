import AVFoundation

/// Async wrapper around AVAudioPlayer for content-pack audio: `play(fileName:)`
/// suspends until playback finishes (or is stopped), so the session engine can
/// choreograph audio → pause → audio sequences as plain async code.
@MainActor
final class AudioPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var continuation: CheckedContinuation<Void, Never>?

    func configureSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// Plays one bundled audio file and returns when it finishes. A missing
    /// file returns immediately — the drill flow degrades to text-only.
    func play(fileName: String) async {
        stop()
        guard let url = ContentPack.audioURL(fileName: fileName),
              let player = try? AVAudioPlayer(contentsOf: url)
        else { return }
        self.player = player
        player.delegate = self
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            continuation = c
            if !player.play() { finish() }
        }
    }

    func stop() {
        player?.stop()
        player = nil
        finish()
    }

    private func finish() {
        continuation?.resume()
        continuation = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.finish() }
    }
}
