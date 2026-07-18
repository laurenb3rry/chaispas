import AVFoundation
import Speech
import SwiftUI

/// On-device speech transcription (fr-FR) used as a *mirror*, never a grader
/// (PLAN2 §7, revised after device testing): it shows the user what they said
/// so they can self-assess against the reveal. It never grades, reveals, or
/// advances anything — the user always drives with taps.
///
/// Every failure mode — no permission, no fr-FR model, an audio-engine error,
/// a device with no usable input — resolves to "no transcript", never a crash:
/// the drill flow then behaves exactly as it did before speech existed.
@MainActor
@Observable
final class SpeechTranscriber {
    enum Availability: Equatable {
        /// Not yet asked (permission is requested on first use).
        case unknown
        case available
        /// Mic or speech permission denied.
        case denied
        /// No fr-FR recognizer / no usable audio input on this device.
        case unsupported
    }

    /// Settings default: show the live transcript. UI tests force it off so
    /// no mic or permission alert enters the picture.
    static let enabledKey = "showSpokenTranscript"

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// Sticky system state for the Settings caption — no live session needed.
    static var deniedBySystem: Bool {
        SFSpeechRecognizer.authorizationStatus() == .denied
            || SFSpeechRecognizer.authorizationStatus() == .restricted
            || AVAudioApplication.shared.recordPermission == .denied
    }

    private(set) var availability: Availability = .unknown

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var onText: ((String) -> Void)?
    /// Bumped by start/stop; a recognition callback for a stale generation is
    /// ignored (each turn is its own generation).
    private var generation = 0
    private var tapInstalled = false

    // MARK: Permission (graceful, on first use)

    /// Resolves availability, requesting mic + speech permission the first
    /// time. Safe to call every run; only the first call can prompt.
    func prepare() async {
        guard availability == .unknown else { return }
        guard let recognizer, recognizer.isAvailable || recognizer.supportsOnDeviceRecognition
        else {
            availability = .unsupported
            return
        }
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            availability = .denied
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            availability = .denied
            return
        }
        availability = .available
    }

    // MARK: Live transcription

    /// Opens the mic and streams the running transcript to `onText` (best
    /// guess so far, updated as the user speaks). Idempotent-safe: a second
    /// call stops the first. Any setup failure silently yields no transcript.
    func start(onText: @escaping (String) -> Void) {
        guard availability == .available else { return }
        stop()
        generation += 1
        let gen = generation
        self.onText = onText

        // The mic needs a record-capable, active session. `.default` mode
        // (not `.measurement`) keeps drill playback at full volume — the
        // reveal audio plays loud right after the mic closes, still under
        // this category, routed to the speaker.
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            availability = .denied
            return
        }

        // The hardware input format. A zero-channel / zero-rate format means
        // no usable input — installing a tap with it would hard-crash, so we
        // bail to no-transcript instead.
        let input = audioEngine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            availability = .unsupported
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        tapInstalled = true
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            teardownAudio()
            return
        }

        task = recognizer?.recognitionTask(with: request) { [weak self] result, _ in
            guard let transcript = result?.bestTranscription.formattedString,
                  !transcript.isEmpty
            else { return }
            Task { @MainActor [weak self] in
                guard let self, gen == self.generation else { return }
                self.onText?(transcript)
            }
        }
    }

    /// Closes the mic. The last transcript the caller received stays theirs;
    /// this object holds no transcript of its own.
    func stop() {
        generation += 1
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        onText = nil
        teardownAudio()
    }

    private func teardownAudio() {
        if audioEngine.isRunning { audioEngine.stop() }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }
}
