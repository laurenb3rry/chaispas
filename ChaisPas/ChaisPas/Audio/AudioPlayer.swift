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
        /// content_pack_v2/speak/audio — scenario NPC and user lines.
        case v2Speak
        /// content_pack_v2/listen/audio — episode full mixes and lines.
        case v2Listen
        /// content_pack_v2/english_prompts — hands-free prompt audio (v1 + v2).
        case englishPrompts
    }

    private var player: AVAudioPlayer?
    private var continuation: CheckedContinuation<Void, Never>?
    /// Bumped by every play/stop; a load that finishes after being superseded
    /// must not start playback.
    private var generation = 0

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
        case .v2Speak:
            ContentPackV2.audioURL(fileName: fileName, module: .speak)
        case .v2Listen:
            ContentPackV2.audioURL(fileName: fileName, module: .listen)
        case .englishPrompts:
            ContentPackV2.audioURL(fileName: fileName, module: .englishPrompts)
        }
    }

    /// Plays one bundled audio file and returns when it finishes. A missing
    /// file returns immediately — the drill flow degrades to text-only.
    func play(fileName: String, from location: Location = .v1) async {
        stop()
        generation += 1
        let gen = generation
        guard let url = Self.url(fileName: fileName, in: location) else { return }
        // The first AVAudioPlayer init after a cold CoreAudio can block for
        // tens of seconds (the phase-8 root cause) — never on the main thread.
        let loaded = await Task.detached(priority: .userInitiated) {
            try? AVAudioPlayer(contentsOf: url)
        }.value
        guard let loaded, gen == generation else { return }  // superseded
        player = loaded
        loaded.delegate = self
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            continuation = c
            if !loaded.play() { finish() }
        }
    }

    func stop() {
        generation += 1
        player?.stop()
        player = nil
        finish()
    }

    // MARK: Long-form playback (Listen episodes)
    //
    // `play(fileName:)` stays suspended across a pause and resumes its await
    // when playback actually finishes, so an episode flow can still be
    // written as one linear async sequence around user-paced pauses.

    func pause() {
        player?.pause()
    }

    func resume() {
        player?.play()
    }

    var isPlaying: Bool {
        player?.isPlaying ?? false
    }

    /// Fraction played of the current file, in [0, 1]; 0 when nothing loaded.
    var playbackProgress: Double {
        guard let player, player.duration > 0 else { return 0 }
        return min(max(player.currentTime / player.duration, 0), 1)
    }

    private func finish() {
        continuation?.resume()
        continuation = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.finish() }
    }
}
