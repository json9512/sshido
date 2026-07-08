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
    @StateObject private var hotkeys = HotkeyState()
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var uploading = false
    @State private var showStuckRecovery = false
    @State private var stuckTimer: Task<Void, Never>?
    @State private var disconnectWatcher: Task<Void, Never>?
    @State private var isReconnecting = false
    @State private var lastReconnectAt: Date?
    @StateObject private var authorize = AuthorizeSignInController()
    @State private var urlPickerURLs: [DetectedURL]?
    @State private var mascotState = MascotSpriteState()
    @State private var showMascot = true
    @State private var mascotOffset: CGSize = .zero
    @State private var mascotMirrored = false
    @State private var terminalSize: CGSize = .zero
    @State private var showBuddyHint = false
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
                ZStack(alignment: .bottomTrailing) {
                    TerminalView(channel: ch, sessionID: session.id) { b in
                        Task { @MainActor in
                            self.bridge = b
                            b.onTitleChange = { newTitle in
                                self.liveTitle = newTitle
                                Task { await SessionStore.shared.renameSession(id: session.id, title: newTitle) }
                            }
                        }
                    }
                    if showMascot, let pack = SpritePackManager.shared.activePack {
                        MascotSpriteView(
                            state: mascotState,
                            sheets: pack.sheets,
                            displaySize: pack.displaySize,
                            containerSize: terminalSize,
                            offset: $mascotOffset,
                            mirrored: $mascotMirrored,
                            onHide: {
                                showMascot = false
                                showBuddyHint = true
                                Task {
                                    try? await Task.sleep(for: .seconds(3))
                                    withAnimation { showBuddyHint = false }
                                }
                            },
                            onMirror: {
                                mascotMirrored.toggle()
                            }
                        )
                    }
                }
                .ignoresSafeArea(.keyboard)
                .background(
                    GeometryReader { geo in
                        Color.clear.onAppear { terminalSize = geo.size }
                            .onChange(of: geo.size) { _, s in terminalSize = s }
                    }
                )
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        guard !showMascot, SpritePackManager.shared.activePack != nil else { return }
                        showMascot = true
                    }
                )
                .overlay(alignment: .bottom) {
                    if showBuddyHint {
                        Text("Double-tap to call your buddy")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 8)
                            .allowsHitTesting(false)
                    }
                }
                AgentBar(channel: ch, bridge: bridge, hotkeys: hotkeys) {
                    bridge?.focus()
                }
            } else if let error {
                SessionErrorScreen(
                    error: error,
                    onRetry: { Task { await load() } },
                    onBack: { dismiss() }
                )
            } else {
                loadingScreen
            }
        }
        .overlay {
            if isReconnecting && channel != nil {
                loadingScreen
                    .transition(.opacity)
            }
        }
        .task { await load() }
        .task {
            let appearance = await AppearanceStore.shared.appearance
            showMascot = appearance.showMascotCompanion
            if let pack = SpritePackManager.shared.activePack {
                mascotState.loadPack(pack)
            }
        }
        .task(id: bridge != nil) {
            guard let b = bridge as? MetalTerminalBridge else { return }
            let tracker = b.activityTracker
            while !Task.isCancelled {
                let mood = tracker.suggestedMood
                if mood != mascotState.currentMood {
                    mascotState.transition(to: mood)
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
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
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .navigationTitle(liveTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(liveTitle).font(DS.Font.headline)
                        .foregroundStyle(DS.Color.textPrimary)
                        .lineLimit(1).truncationMode(.middle)
                    DSStatusIndicator(style: .pill(phase: connectPillPhase))
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { Task { await smartCopy() } } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .accessibilityLabel("Copy")

                Button { Task { await pasteIntoTerminal() } } label: {
                    Image(systemName: "arrow.down.doc")
                }
                .accessibilityLabel("Paste")

                Menu {
                    Button { Task { await copyEntireScreen() } } label: {
                        Label("Copy whole screen", systemImage: "rectangle.on.rectangle")
                    }
                    Button { Task { await openURLPicker() } } label: {
                        Label("Find link…", systemImage: "link")
                    }
                    Divider()
                    Button { showPhotoPicker = true } label: {
                        Label("Upload image…", systemImage: "photo")
                    }
                    Button { Task { await openAuthorizeSheet() } } label: {
                        Label("Sign in / authorize…", systemImage: "lock.shield")
                    }
                } label: {
                    if uploading {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                .accessibilityLabel("More actions")
            }
        }
        .toast($toast)
        .onReceive(authorize.$toast.compactMap { $0 }) { msg in
            toast = msg
            authorize.toast = nil
        }
        .sheet(item: Binding(
            get: { authorize.activeSheet },
            set: { new in
                authorize.activeSheet = new
                if new == nil {
                    if case .openingSafari = authorize.phase {
                        authorize.safariDismissed()
                    } else {
                        Task { await authorize.cancel() }
                    }
                }
            }
        )) { sheet in
            switch sheet {
            case .authorize:
                AuthorizeSignInSheet(controller: authorize)
            case .safari(let url):
                SafariSheet(url: url) { authorize.safariDismissed() }
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: Binding(
            get: { urlPickerURLs != nil },
            set: { presenting in
                if !presenting { urlPickerURLs = nil }
            }
        )) {
            CopyURLPickerSheet(urls: urlPickerURLs ?? []) { picked in
                UIPasteboard.general.string = picked.raw
                toast = "Copied URL"
            }
        }
    }

    private func load() async {
        NSLog("[sshido] SessionView.load start host=\(host.name) session=\(session.id.uuidString.prefix(8)) reconnecting=\(isReconnecting)")
        error = nil
        showStuckRecovery = false
        stuckTimer?.cancel()
        stuckTimer = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if (channel == nil || isReconnecting) && error == nil {
                showStuckRecovery = true
            }
        }
        while !Task.isCancelled {
            await waitForProtectedDataAvailable()
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
                        if !isReconnecting { error = msg }
                        return
                    }
                    let pem = try await IdentityStore.shared.loadPEM(for: identityID)
                    auth = .privateKeyPEM(pem, passphrase: nil)
                }
                let ch = await SessionStore.shared.ensureChannel(for: session, host: host, auth: auth)
                NSLog("[sshido] SessionView.load got channel, awaiting first connect…")
                channel = ch
                if await waitForFirstConnection(ch) {
                    NSLog("[sshido] SessionView.load: channel connected")
                    isReconnecting = false
                    showStuckRecovery = false
                    startDisconnectWatcher()
                    return
                }
                NSLog("[sshido] SessionView.load: first-connect timed out, tearing down and retrying")
                BridgeStore.shared.remove(sessionID: session.id)
                bridge = nil
                channel = nil
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                continue
            } catch {
                let msg = String(describing: error)
                NSLog("[sshido] SessionView.load catch: \(msg)")
                if isReconnecting {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    continue
                }
                self.error = msg
                return
            }
        }
    }

    @MainActor
    private func waitForProtectedDataAvailable() async {
        guard !UIApplication.shared.isProtectedDataAvailable else { return }
        NSLog("[sshido] SessionView.load: protected data unavailable, waiting for unlock…")
        while !Task.isCancelled && !UIApplication.shared.isProtectedDataAvailable {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    private func waitForFirstConnection(_ ch: SSHChannel, timeout: TimeInterval = 15) async -> Bool {
        let start = Date()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if await ch.isConnected {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if await ch.isConnected { return true }
            }
            if Date().timeIntervalSince(start) > timeout { return false }
        }
        return false
    }

    @ViewBuilder
    private var loadingScreen: some View {
        SessionLoadingScreen(
            label: loadingLabel,
            showStuckRecovery: showStuckRecovery,
            onRetry: { Task { await load() } },
            onBack: { dismiss() }
        )
    }

    private func startDisconnectWatcher() {
        disconnectWatcher?.cancel()
        guard let ch = channel else { return }
        disconnectWatcher = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if await !ch.isConnected {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if await ch.isConnected { continue }
                    await MainActor.run { triggerReconnect() }
                    return
                }
            }
        }
    }

    private func triggerReconnect() {
        guard !isReconnecting else { return }
        if let last = lastReconnectAt, Date().timeIntervalSince(last) < 5 {
            NSLog("[sshido] SessionView: skipping reconnect, cooldown active")
            return
        }
        NSLog("[sshido] SessionView: channel disconnected, auto-reconnecting session=\(session.id.uuidString.prefix(8))")
        lastReconnectAt = Date()
        isReconnecting = true
        BridgeStore.shared.remove(sessionID: session.id)
        bridge = nil
        channel = nil
        Task { await load() }
    }

    private var loadingLabel: String {
        let name = liveTitle.isEmpty ? session.title : liveTitle
        return isReconnecting ? "Reconnecting to \(name)…" : "Opening \(name)…"
    }

    private var connectPillPhase: DSStatusIndicator.Phase {
        if channel == nil { return .connecting }
        switch net.status {
        case .online:  return .online
        case .offline: return .offline
        case .unknown: return .connecting
        }
    }

    private func smartCopy() async {
        guard let bridge else { return }

        if bridge.hasSelection {
            let text = await bridge.copyFromTerminal(.selection)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { toast = "Nothing selected"; return }
            UIPasteboard.general.string = text
            toast = "Copied selection (\(text.count) chars)"
            return
        }

        let rows = bridge.snapshotBufferLines(beforeViewport: 0, afterViewport: 0)
        let urls = TerminalURLExtractor.extract(from: rows, cols: bridge.cols)
        if urls.count == 1 {
            UIPasteboard.general.string = urls[0].raw
            toast = "Copied URL"
            return
        }
        if urls.count > 1 {
            urlPickerURLs = urls
            return
        }

        let text = await bridge.copyFromTerminal(.viewport)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { toast = "Nothing to copy"; return }
        UIPasteboard.general.string = text
        toast = "Copied screen (\(text.count) chars)"
    }

    private func copyEntireScreen() async {
        guard let bridge else { return }
        let text = await bridge.copyFromTerminal(.viewport)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            toast = "Nothing on screen"
            return
        }
        UIPasteboard.general.string = trimmed
        toast = "Copied screen (\(trimmed.count) chars)"
    }

    private func openURLPicker() async {
        guard let bridge else { return }
        let rows = bridge.snapshotBufferLines(beforeViewport: 200, afterViewport: 50)
        let urls = TerminalURLExtractor.extract(from: rows, cols: bridge.cols)
        urlPickerURLs = urls
    }

    private func openAuthorizeSheet() async {
        guard let bridge, let ch = channel else { return }
        let rows = bridge.snapshotBufferLines(beforeViewport: 200, afterViewport: 50)
        let urls = TerminalURLExtractor.extract(from: rows, cols: bridge.cols)
        authorize.present(channel: ch, urls: urls)
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
