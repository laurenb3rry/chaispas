import AVFoundation

/// Async wrapper around AVAudioPlayer for content-pack audio: `play(fileName:)`
/// suspends until playback finishes (or is stopped), so the session engine can
/// choreograph audio → pause → audio sequences as plain async code.
@MainActor
final class AudioPlayer: NSObject, AVAudioPlayerDelegate {
    /// Which bundled pack directory a file name resolves against.
    enum Location {
        /// content_pack_v1/audio — Construction sentences.
        case v1
        /// content_pack_v2/learn/audio — Learn drills, tables, words, examples.
        case v2Learn
        /// content_pack_v2/english_prompts — hands-free prompt audio (v1 + v2).
        case englishPrompts
    }

    private var player: AVAudioPlayer?
    private var continuation: CheckedContinuation<Void, Never>?

    func configureSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    nonisolated static func url(fileName: String, in location: Location) -> URL? {
        switch location {
        case .v1:
            ContentPack.audioURL(fileName: fileName)
        case .v2Learn:
            ContentPackV2.audioURL(fileName: fileName, module: .learn)
        case .englishPrompts:
            ContentPackV2.audioURL(fileName: fileName, module: .englishPrompts)
        }
    }

    /// Plays one bundled audio file and returns when it finishes. A missing
    /// file returns immediately — the drill flow degrades to text-only.
    func play(fileName: String, from location: Location = .v1) async {
        stop()
        guard let url = Self.url(fileName: fileName, in: location),
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
