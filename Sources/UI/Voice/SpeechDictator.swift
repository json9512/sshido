#if canImport(UIKit)
import Foundation
import AVFoundation
import Speech
#if canImport(sshidoCore)
import sshidoCore
#endif

@MainActor
@Observable
public final class SpeechDictator {
    public enum State: Equatable {
        case idle
        case listening
        case unavailable(String)
    }

    public private(set) var state: State = .idle
    public private(set) var partialTranscript: String = ""

    private var recognizer: SFSpeechRecognizer?
    private var currentLocaleID: String?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Task<Void, Never>?
    private var onFinal: ((String) -> Void)?
    private var interruptionObserver: NSObjectProtocol?

    public init() {}

    public var isListening: Bool { state == .listening }

    public func requestAuthorization() async -> Bool {
        let speech: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard speech == .authorized else {
            Log.ui.error("dictation: speech recognition not authorized (\(speech.rawValue))")
            state = .unavailable("Speech recognition is off. Enable it in Settings → sshido.")
            return false
        }
        let mic: Bool = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
        guard mic else {
            Log.ui.error("dictation: microphone permission denied")
            state = .unavailable("Microphone access is off. Enable it in Settings → sshido.")
            return false
        }
        if state != .listening { state = .idle }
        return true
    }

    public func start(localeID: String, onFinal: @escaping (String) -> Void) {
        guard state != .listening else { return }
        ensureRecognizer(localeID: localeID)
        guard let recognizer, recognizer.isAvailable else {
            state = .unavailable("Dictation isn't available right now.")
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            Log.ui.error("dictation: no on-device model for locale \(recognizer.locale.identifier)")
            state = .unavailable("On-device dictation isn't available for this language.")
            return
        }
        self.onFinal = onFinal
        partialTranscript = ""
        do {
            try beginRecognition(recognizer: recognizer)
            observeInterruptions()
            state = .listening
        } catch {
            Log.ui.error("dictation: failed to start — \(error)")
            teardown()
            state = .unavailable("Couldn't start dictation.")
        }
    }

    public func stop() {
        guard state == .listening else { return }
        let text = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let callback = onFinal
        teardown()
        onFinal = nil
        partialTranscript = ""
        state = .idle
        if !text.isEmpty { callback?(text) }
    }

    public func cancel() {
        guard state == .listening else { return }
        teardown()
        onFinal = nil
        partialTranscript = ""
        state = .idle
    }

    private func ensureRecognizer(localeID: String) {
        if recognizer != nil, currentLocaleID == localeID { return }
        let locale = localeID.isEmpty ? Locale.current : Locale(identifier: localeID)
        recognizer = SFSpeechRecognizer(locale: locale)
        currentLocaleID = localeID
    }

    private func beginRecognition(recognizer: SFSpeechRecognizer) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement,
                                options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in self?.handleResult(result, error: error) }
        }
    }

    private func handleResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
        guard state == .listening else { return }
        if let result {
            partialTranscript = result.bestTranscription.formattedString
            armSilenceTimer()
            if result.isFinal { stop() }
        }
        if error != nil { stop() }
    }

    private func armSilenceTimer() {
        silenceTimer?.cancel()
        silenceTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    private func observeInterruptions() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in self?.cancel() }
        }
    }

    private func teardown() {
        silenceTimer?.cancel(); silenceTimer = nil
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
    }
}
#endif
