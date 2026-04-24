#if canImport(UIKit)
import Foundation
import AVFoundation
import Speech
#if canImport(FoundationModels)
import FoundationModels
#endif
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif

@MainActor
public final class VoiceInputController: ObservableObject {

    // MARK: - State

    public enum State: Equatable {
        case idle
        case voiceActive
        case listening
        case translating
        case sending
    }

    @Published public private(set) var transcript: String = ""
    @Published public private(set) var translatedCommand: String = ""
    @Published public private(set) var state: State = .idle
    @Published public private(set) var error: String?
    @Published public var language: VoiceLanguage = .auto

    public var isVoiceModeActive: Bool { state != .idle }
    public var onSendBytes: (([UInt8]) -> Void)?

    // MARK: - Meta commands

    private enum MetaAction {
        case delete, clear, enter, escape, tab, stop
    }

    private static let metaCommands: [String: MetaAction] = [
        "delete": .delete,  "삭제": .delete,
        "clear": .clear,    "지우기": .clear,
        "enter": .enter,    "엔터": .enter,
        "escape": .escape,  "이스케이프": .escape,
        "tab": .tab,        "탭": .tab,
        "stop": .stop,      "중지": .stop,
    ]

    // MARK: - Private

    private var lastSentCount = 0
    private let audio = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var idleTimer: Task<Void, Never>?
    private var _aiSession: AnyObject?

    public init() {}

    private func currentLocale() -> Locale {
        if let id = language.localeIdentifier { return Locale(identifier: id) }
        let primary = Locale.current.language.languageCode?.identifier ?? "en"
        return primary == "ko" ? Locale(identifier: "ko-KR") : Locale(identifier: "en-US")
    }

    // MARK: - Authorization

    public func requestAuthorization() async -> Bool {
        let mic = await AVAudioApplication.requestRecordPermission()
        if !mic { error = "Microphone permission denied"; return false }
        let speech = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        if speech != .authorized { error = "Speech recognition denied"; return false }
        return true
    }

    // MARK: - Voice Mode

    public func toggleVoiceMode() async throws {
        if isVoiceModeActive {
            deactivate()
        } else {
            if #available(iOS 26, *) {
                #if canImport(FoundationModels)
                let avail = SystemLanguageModel.default.availability
                switch avail {
                case .available:
                    aiStatus = ""
                case .unavailable(let reason):
                    switch reason {
                    case .appleIntelligenceNotEnabled:
                        aiStatus = "Enable Apple Intelligence in Settings to use AI command translation"
                    case .modelNotReady:
                        aiStatus = "Apple Intelligence model is still downloading. Connect to Wi-Fi and power."
                    case .deviceNotEligible:
                        aiStatus = "This device doesn't support Apple Intelligence"
                    @unknown default:
                        aiStatus = "Apple Intelligence unavailable"
                    }
                @unknown default:
                    aiStatus = ""
                }
                if avail == .available {
                    _aiSession = LanguageModelSession {
                        """
                        You translate spoken natural language into exact shell commands for a Unix terminal.
                        Output ONLY the command. No explanation, no markdown, no backticks.
                        If the input is already a valid command, output it as-is.
                        If you cannot determine a command, output the input text unchanged.

                        Examples:
                        "list all files" → ls -la
                        "go to code folder" → cd code
                        "what's today's date" → date
                        "show disk space" → df -h
                        "make a folder called test" → mkdir test
                        "find python files" → find . -name "*.py"
                        "CD code" → cd code
                        "LS" → ls
                        "cat readme" → cat readme
                        "ping google" → ping google.com
                        """
                    }
                } else {
                    aiStatus = "AI: \(avail)"
                }
                #else
                aiStatus = "AI: not compiled"
                #endif
            } else {
                aiStatus = "AI: needs iOS 26"
            }
            state = .voiceActive
            try await beginRecognition()
        }
    }

    public func deactivate() {
        idleTimer?.cancel()
        idleTimer = nil
        teardown()
        transcript = ""
        translatedCommand = ""
        state = .idle
        _aiSession = nil
    }

    // MARK: - Recognition

    private func beginRecognition() async throws {
        error = nil
        transcript = ""

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let rec = SFSpeechRecognizer(locale: currentLocale())
        guard let rec, rec.isAvailable else {
            error = "Speech recognizer unavailable"
            return
        }
        self.recognizer = rec

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true  // ON-DEVICE: doesn't cut off mid-sentence
        self.request = req

        let input = audio.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak req] buffer, _ in
            req?.append(buffer)
        }

        audio.prepare()
        try audio.start()
        state = .listening

        recognitionTask = rec.recognitionTask(with: req) { [weak self] result, err in
            guard let self else { return }
            Task { @MainActor in
                if let r = result {
                    self.transcript = Self.normalizeText(r.bestTranscription.formattedString)
                    self.restartIdleTimer()
                }
                // NOTHING else. No isFinal handling. No error handling.
                // The 2-second idle timer is the ONLY send trigger.
            }
        }
    }

    /// 2 seconds of no new words → user stopped speaking → process.
    private func restartIdleTimer() {
        idleTimer?.cancel()
        idleTimer = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                return // Cancelled — do NOT fire
            }
            guard let self, self.state == .listening else { return }
            let text = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            await self.handleUtterance()
        }
    }

    /// Process completed utterance.
    private func handleUtterance() async {
        guard state == .listening else { return }
        idleTimer?.cancel()
        idleTimer = nil
        teardown()

        let raw = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !raw.isEmpty else {
            state = .voiceActive
            try? await beginRecognition()
            return
        }

        // Meta commands (instant)
        let cleaned = Self.stripTrailingPunctuation(raw).lowercased()
        if let action = Self.metaCommands[cleaned] {
            executeMetaCommand(action)
            if state == .idle { return }
            state = .voiceActive
            try? await Task.sleep(nanoseconds: 300_000_000)
            if state == .voiceActive { try? await beginRecognition() }
            return
        }

        // AI translate (if enabled)
        let command: String
        if VoicePreferences.shared.aiTranslate {
            command = await translateWithAI(raw)
        } else {
            command = raw
        }
        guard state != .idle else { return }

        // Show translated command, then send
        translatedCommand = command
        state = .sending
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        guard state == .sending else { return }

        sendText(command)
        translatedCommand = ""

        // Restart listening
        try? await Task.sleep(nanoseconds: 300_000_000)
        if state == .sending {
            state = .voiceActive
            try? await beginRecognition()
        }
    }

    // MARK: - AI Translation

    /// Exposed so SessionView can show why AI isn't working.
    @Published public private(set) var aiStatus: String = ""

    private func translateWithAI(_ spokenText: String) async -> String {
        state = .translating

        if #available(iOS 26, *) {
            #if canImport(FoundationModels)
            if _aiSession == nil {
                // Try to create session now if it wasn't created at toggle time
                let availability = SystemLanguageModel.default.availability
                aiStatus = "AI: \(availability)"
                if availability == .available {
                    _aiSession = LanguageModelSession {
                        """
                        You translate spoken natural language into exact shell commands for a Unix terminal.
                        Output ONLY the command. No explanation, no markdown, no backticks.
                        If the input is already a valid command, output it as-is.
                        If you cannot determine a command, output the input text unchanged.
                        """
                    }
                }
            }
            if let session = _aiSession as? LanguageModelSession {
                do {
                    let response = try await session.respond(to: spokenText)
                    let command = String(response.content)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "`"))
                    aiStatus = ""
                    if !command.isEmpty { return command }
                } catch {
                    aiStatus = "AI error: \(error.localizedDescription)"
                }
            } else {
                aiStatus = "AI unavailable"
            }
            #else
            aiStatus = "AI not compiled"
            #endif
        } else {
            aiStatus = "Needs iOS 26"
        }

        return spokenText
    }

    // MARK: - Meta Commands

    private func executeMetaCommand(_ action: MetaAction) {
        switch action {
        case .delete:
            guard lastSentCount > 0 else { return }
            onSendBytes?(Array(repeating: 0x7f, count: lastSentCount))
            lastSentCount = 0
        case .clear:
            onSendBytes?([0x03])
            lastSentCount = 0
        case .enter:
            onSendBytes?([0x0d])
        case .escape:
            onSendBytes?([0x1b])
        case .tab:
            onSendBytes?([0x09])
        case .stop:
            deactivate()
        }
    }

    // MARK: - Send

    private func sendText(_ text: String) {
        var bytes = Array(text.utf8)
        if VoicePreferences.shared.autoSend {
            bytes.append(0x0d)
        }
        lastSentCount = text.count
        onSendBytes?(bytes)
    }

    // MARK: - Text

    private static func normalizeText(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "\u{2018}", with: "'")
        s = s.replacingOccurrences(of: "\u{2019}", with: "'")
        s = s.replacingOccurrences(of: "\u{201C}", with: "\"")
        s = s.replacingOccurrences(of: "\u{201D}", with: "\"")
        s = s.replacingOccurrences(of: "\u{2013}", with: "-")
        s = s.replacingOccurrences(of: "\u{2014}", with: "-")
        s = s.replacingOccurrences(of: "\u{2026}", with: "...")
        return s
    }

    private static func stripTrailingPunctuation(_ text: String) -> String {
        var s = text
        while let last = s.last, ".!?,;:".contains(last) { s.removeLast() }
        return s
    }

    // MARK: - Teardown

    private func teardown() {
        if audio.isRunning {
            audio.inputNode.removeTap(onBus: 0)
            audio.stop()
        }
        request?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil
        recognizer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
#endif
