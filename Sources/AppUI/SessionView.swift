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
                TerminalView(channel: ch) { b in
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
                AgentBar(channel: ch, hotkeys: hotkeys)
            } else if let error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40)).foregroundStyle(.orange)
                    Text(error).font(.callout.monospaced())
                        .multilineTextAlignment(.center).padding(.horizontal)
                    Button("Retry") { Task { await load() } }.buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("Opening \(liveTitle)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await load() }
        .onChange(of: scenePhase) { _, new in
            if new == .active {
                Task { await reconnectIfDropped() }
                bridge?.requestServerRedraw()
            }
        }
        .onChange(of: net.status) { _, new in
            if new == .online { Task { await reconnectIfDropped() } }
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
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.callout)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: toast)
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
        error = nil
        do {
            let auth: SSHAuth
            switch host.authMethod {
            case .password:
                let pw = try KeychainKeyStore().loadPassword(hostID: host.id)
                auth = .password(pw)
            case .key:
                guard let identityID = host.identityID else {
                    error = "host authMethod=.key but no identity attached (host.id=\(host.id.uuidString.prefix(8)))"
                    return
                }
                let pem = try await IdentityStore.shared.loadPEM(for: identityID)
                auth = .privateKeyPEM(pem, passphrase: nil)
            }
            let ch = await SessionStore.shared.ensureChannel(for: session, host: host, auth: auth)
            channel = ch
        } catch {
            self.error = String(describing: error)
        }
    }

    private func reconnectIfDropped() async {
        guard let ch = channel, await !ch.isConnected else { return }
        await MainActor.run { channel = nil }
        await load()
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

    private func copyFromTerminal(_ kind: CopyKind) async {
        guard let bridge else { return }
        let text = await bridge.copyFromTerminal(kind)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            switch kind {
            case .selection: flashToast("Long-press to select first")
            case .viewport:  flashToast("Nothing on screen")
            case .lastURL:   flashToast("No URL found")
            }
            return
        }
        UIPasteboard.general.string = trimmed
        flashToast("Copied \(trimmed.count) chars")
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
                flashToast("Couldn't read image")
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
            flashToast("Uploading \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))…")
            do {
                try await ch.uploadFile(data: data, remotePath: expanded)
            } catch {
                let altHome = "/Users/\(host.username)/.sshido/uploads/\(name)"
                try await ch.uploadFile(data: data, remotePath: altHome)
            }
            let pasted = "~/.sshido/uploads/\(name) "
            try await ch.send(Array(pasted.utf8))
            flashToast("Uploaded — path pasted")
        } catch {
            flashToast("Upload failed: \(error)")
        }
    }

    private func pasteIntoTerminal() async {
        guard let ch = channel else { return }
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            flashToast("Clipboard empty"); return
        }
        try? await ch.send(Array(text.utf8))
    }

    private func flashToast(_ s: String) {
        toast = s
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if toast == s { toast = nil }
        }
    }
}
#endif
