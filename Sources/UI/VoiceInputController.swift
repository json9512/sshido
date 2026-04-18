#if canImport(UIKit)
import Foundation
import AVFoundation
import Speech
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif

@MainActor
public final class VoiceInputController: ObservableObject {
    public enum State: Equatable { case idle, recording, finishing }

    @Published public private(set) var transcript: String = ""
    @Published public private(set) var state: State = .idle
    @Published public private(set) var error: String?
    @Published public var language: VoiceLanguage = .auto

    public var isRecording: Bool { state == .recording }

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audio = AVAudioEngine()

    public init() {}

    private func currentLocale() -> Locale {
        if let id = language.localeIdentifier { return Locale(identifier: id) }
        let primary = Locale.current.language.languageCode?.identifier ?? "en"
        return primary == "ko" ? Locale(identifier: "ko-KR") : Locale(identifier: "en-US")
    }

    public func requestAuthorization() async -> Bool {
        let mic = await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
        }
        if !mic { error = "Microphone permission denied"; return false }
        let speech = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        if speech != .authorized { error = "Speech recognition denied"; return false }
        return true
    }

    public func start() async throws {
        guard state == .idle else { return }
        error = nil
        transcript = ""

        let rec = SFSpeechRecognizer(locale: currentLocale())
        guard let rec, rec.isAvailable else {
            error = "Speech recognizer unavailable for \(currentLocale().identifier)"
            return
        }
        self.recognizer = rec

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true
        self.request = req

        let input = audio.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }

        audio.prepare()
        try audio.start()
        state = .recording

        task = rec.recognitionTask(with: req) { [weak self] result, err in
            guard let self else { return }
            if let r = result {
                Task { @MainActor in self.transcript = r.bestTranscription.formattedString }
            }
            if err != nil || (result?.isFinal ?? false) {
                Task { @MainActor in await self.stop() }
            }
        }
    }

    public func stop() async {
        guard state != .idle else { return }
        state = .finishing
        if audio.isRunning {
            audio.inputNode.removeTap(onBus: 0)
            audio.stop()
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        state = .idle
    }

    public func commit(to channel: SSHChannel) async {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        try? await channel.send(Array(text.utf8))
        transcript = ""
    }

    public func clear() { transcript = "" }
}
#endif
