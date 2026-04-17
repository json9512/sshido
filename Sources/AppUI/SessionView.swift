#if canImport(UIKit)
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif
#if canImport(sshidoUI)
import sshidoUI
#endif

public struct SessionView: View {
    let session: Session
    let host: RemoteHost
    @State private var channel: SSHChannel?
    @State private var bridge: TerminalBridge?
    @State private var error: String?
    @State private var toast: String?
    @State private var liveTitle: String
    @StateObject private var voice: VoiceInputController = {
        let v = VoiceInputController()
        v.language = VoicePreferences.shared.language
        return v
    }()
    @StateObject private var hotkeys = HotkeyState()
    @State private var photoItem: PhotosPickerItem?
    @State private var uploading = false
    @State private var showStuckRecovery = false
    @State private var stuckTimer: Task<Void, Never>?
    @State private var showDisconnectAlert = false
    @State private var disconnectWatcher: Task<Void, Never>?
    @StateObject private var oauthFlow = OAuthAuthorizeFlow()
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    private var profile: AgentProfile {
        AgentProfile.builtins.first { $0.id == host.agentProfileID } ?? .claudeCode
    }

    public init(session: Session, host: RemoteHost) {
        self.session = session
        self.host = host
        self._liveTitle = State(initialValue: session.title)
    }

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var net = NetworkMonitor.shared

    public var body: some View {
        VStack(spacing: 0) {
            if let ch = channel {
                TerminalView(channel: ch, sessionID: session.id) { b in
                    Task { @MainActor in
                        self.bridge = b
                        b.onTitleChange = { newTitle in
                            self.liveTitle = newTitle
                            Task { await SessionStore.shared.renameSession(id: session.id, title: newTitle) }
                        }
                    }
                }
                    .ignoresSafeArea(.keyboard)
                if voice.state != .idle || !voice.transcript.isEmpty {
                    voiceStrip(ch)
                }
                AgentBar(channel: ch, bridge: bridge, hotkeys: hotkeys) {
                    bridge?.focus()
                }
            } else if let error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                    Text("Couldn't open the session")
                        .font(.headline)
                    Text(error.isEmpty ? "(no error message)" : error)
                        .font(.callout.monospaced())
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .textSelection(.enabled)
                    HStack(spacing: 12) {
                        Button("Retry") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                        Button("Back") { dismiss() }
                            .buttonStyle(.bordered)
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Opening \(liveTitle.isEmpty ? session.title : liveTitle)…")
                        .font(.callout).foregroundStyle(.primary)
                    if showStuckRecovery {
                        Text("Taking longer than usual…")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button("Retry") { Task { await load() } }
                                .buttonStyle(.borderedProminent)
                            Button("Back") { dismiss() }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await load() }
        .onChange(of: scenePhase) { _, new in
            if new == .active {
                bridge?.requestServerRedraw()
                startDisconnectWatcher()
            }
        }
        .onChange(of: photoItem) { _, new in
            guard let new else { return }
            Task { await uploadImage(new) }
        }
        .navigationTitle(liveTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(liveTitle).font(.headline).lineLimit(1).truncationMode(.middle)
                    ConnectStatusPill(phase: connectPhase)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button { Task { await copyFromTerminal(.selection) } } label: {
                        Label("Copy selection", systemImage: "selection.pin.in.out")
                    }
                    Button { Task { await copyFromTerminal(.viewport) } } label: {
                        Label("Copy visible screen", systemImage: "rectangle.on.rectangle")
                    }
                    Button { Task { await copyFromTerminal(.lastURL) } } label: {
                        Label("Copy last URL", systemImage: "link")
                    }
                    Divider()
                    Button { Task { await authorizeLastURL() } } label: {
                        Label("Authorize in app", systemImage: "lock.shield")
                    }
                    Button { oauthFlow.pastePromptActive = true } label: {
                        Label("Finish OAuth sign-in…", systemImage: "text.badge.checkmark")
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                Button { Task { await pasteIntoTerminal() } } label: {
                    Image(systemName: "doc.on.doc")
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    if uploading {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "photo")
                    }
                }
                .disabled(uploading)
                Button { Task { await toggleVoice() } } label: {
                    Image(systemName: voice.isRecording ? "mic.fill" : "mic")
                }
            }
        }
        .toast($toast)
        .alert("Connection Lost", isPresented: $showDisconnectAlert) {
            Button("OK") {
                BridgeStore.shared.remove(sessionID: session.id)
                disconnectWatcher?.cancel()
                if !router.path.isEmpty {
                    router.path.removeLast()
                }
            }
        } message: {
            if host.useTmux {
                Text("The network connection was closed by iOS. Tap the session again to reconnect — your tmux session is still running on the server.")
            } else {
                Text("The network connection was closed by iOS.")
            }
        }
        .onReceive(oauthFlow.$toast.compactMap { $0 }) { msg in
            toast = msg
            oauthFlow.toast = nil
        }
        .sheet(
            isPresented: Binding(
                get: { oauthFlow.presentedURL != nil },
                set: { presenting in
                    if !presenting {
                        Task { await oauthFlow.sessionDismissed() }
                    }
                }
            )
        ) {
            if let url = oauthFlow.presentedURL {
                SafariSheet(url: url) {
                    Task { await oauthFlow.sessionDismissed() }
                }
                .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $oauthFlow.pastePromptActive) {
            PasteCallbackSheet(isPresented: $oauthFlow.pastePromptActive) { pasted in
                guard let ch = channel else { return }
                Task { await oauthFlow.finishWithPastedCallback(pasted, channel: ch) }
            }
        }
    }

    @ViewBuilder
    private func voiceStrip(_ ch: SSHChannel) -> some View {
        HStack {
            Text(voiceStatus)
                .font(.system(.callout, design: .monospaced)).lineLimit(2)
            Spacer()
            Button("Send") { Task { await voice.commit(to: ch) } }
                .buttonStyle(.borderedProminent)
                .disabled(voice.transcript.isEmpty)
            Button("Discard") { voice.clear() }
        }
        .padding(8).background(.thinMaterial)
    }

    private func load() async {
        NSLog("[sshido] SessionView.load start host=\(host.name) session=\(session.id.uuidString.prefix(8))")
        error = nil
        showStuckRecovery = false
        stuckTimer?.cancel()
        stuckTimer = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if channel == nil && error == nil {
                showStuckRecovery = true
            }
        }
        do {
            let auth: SSHAuth
            switch host.authMethod {
            case .password:
                let pw = try KeychainKeyStore().loadPassword(hostID: host.id)
                auth = .password(pw)
            case .key:
                guard let identityID = host.identityID else {
                    let msg = "host authMethod=.key but no identity attached (host.id=\(host.id.uuidString.prefix(8)))"
                    NSLog("[sshido] SessionView.load error: \(msg)")
                    error = msg
                    return
                }
                let pem = try await IdentityStore.shared.loadPEM(for: identityID)
                auth = .privateKeyPEM(pem, passphrase: nil)
            }
            let ch = await SessionStore.shared.ensureChannel(for: session, host: host, auth: auth)
            NSLog("[sshido] SessionView.load got channel")
            channel = ch
            startDisconnectWatcher()
        } catch {
            let msg = String(describing: error)
            NSLog("[sshido] SessionView.load catch: \(msg)")
            self.error = msg
        }
    }

    private func startDisconnectWatcher() {
        disconnectWatcher?.cancel()
        guard let ch = channel else { return }
        disconnectWatcher = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if await !ch.isConnected {
                    await MainActor.run { showDisconnectAlert = true }
                    return
                }
            }
        }
    }

    private var connectPhase: ConnectStatusPill.Phase {
        if channel == nil { return .connecting }
        switch net.status {
        case .online:  return .online
        case .offline: return .offline
        case .unknown: return .connecting
        }
    }

    private var voiceStatus: String {
        if !voice.transcript.isEmpty { return voice.transcript }
        switch voice.state {
        case .idle:       return ""
        case .recording:  return "Listening…"
        case .finishing:  return "Finishing…"
        }
    }

    private func toggleVoice() async {
        if voice.isRecording { await voice.stop(); return }
        guard await voice.requestAuthorization() else { return }
        try? await voice.start()
    }

    private func authorizeLastURL() async {
        guard let bridge, let ch = channel else { return }
        let text = await bridge.copyFromTerminal(.lastURL)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            toast = "No URL on screen"
            return
        }
        guard let target = OAuthURLDetector.detect(trimmed) else {
            let preview = String(trimmed.prefix(80))
            let suffix = trimmed.count > 80 ? "…(\(trimmed.count) chars)" : ""
            toast = "No localhost redirect in: \(preview)\(suffix)"
            NSLog("[sshido] authorizeLastURL: detector rejected URL: %@", trimmed)
            return
        }
        await oauthFlow.startAuthorize(target: target, channel: ch)
    }

    private func copyFromTerminal(_ kind: CopyKind) async {
        guard let bridge else { return }
        let text = await bridge.copyFromTerminal(kind)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            switch kind {
            case .selection: toast = "Long-press to select first"
            case .viewport:  toast = "Nothing on screen"
            case .lastURL:   toast = "No URL found"
            }
            return
        }
        UIPasteboard.general.string = trimmed
        toast = "Copied \(trimmed.count) chars"
    }

    private func uploadImage(_ item: PhotosPickerItem) async {
        guard let ch = channel else { return }
        uploading = true
        defer {
            uploading = false
            photoItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                toast = "Couldn't read image"
                return
            }
            let ext: String
            if let type = item.supportedContentTypes.first,
               let e = type.preferredFilenameExtension {
                ext = e
            } else {
                ext = "jpg"
            }
            let name = "sshido-\(UUID().uuidString.prefix(8)).\(ext)"
            let remotePath = "~/.sshido/uploads/\(name)"
            let expanded = remotePath.replacingOccurrences(of: "~", with: "/home/\(host.username)")
            toast = "Uploading \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))…"
            do {
                try await ch.uploadFile(data: data, remotePath: expanded)
            } catch {
                let altHome = "/Users/\(host.username)/.sshido/uploads/\(name)"
                try await ch.uploadFile(data: data, remotePath: altHome)
            }
            let pasted = "~/.sshido/uploads/\(name) "
            try await ch.send(Array(pasted.utf8))
            toast = "Uploaded — path pasted"
        } catch {
            toast = "Upload failed: \(error)"
        }
    }

    private func pasteIntoTerminal() async {
        guard let ch = channel else { return }
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            toast = "Clipboard empty"; return
        }
        try? await ch.send(Array(text.utf8))
    }

}
#endif
