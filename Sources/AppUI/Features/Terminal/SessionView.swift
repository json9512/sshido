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
    @State private var sessionName: String
    @StateObject private var hotkeys = HotkeyState()
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var uploading = false
    @State private var showStuckRecovery = false
    @State private var stuckTimer: Task<Void, Never>?
    @State private var disconnectWatcher: Task<Void, Never>?
    @State private var isReconnecting = false
    @State private var lookupHint: String?
    @State private var lastReconnectAt: Date?
    @State private var urlPickerURLs: [DetectedURL]?
    @State private var browserTarget: BrowserSheetTarget?
    @State private var browserTunnel: OAuthTunnel?
    @State private var shellHint: DetectedShellHint?
    @State private var dismissedHints: Set<String> = []
    @State private var mascotState = MascotSpriteState()
    @State private var showMascot = true
    @State private var mascotOffset: CGSize = .zero
    @State private var mascotMirrored = false
    @State private var terminalSize: CGSize = .zero
    @State private var showBuddyHint = false
    @State private var dictator = SpeechDictator()
    @State private var voiceEnabled = true
    @State private var dictationLocaleID = ""
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.services) private var services

    private var profile: AgentProfile {
        AgentProfile.builtins.first { $0.id == host.agentProfileID } ?? .claudeCode
    }

    public init(session: Session, host: RemoteHost) {
        self.session = session
        self.host = host
        self._sessionName = State(initialValue: session.displayName(on: host))
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
                            (b as? MetalTerminalBridge)?.wheelPolicyProbe = wheelPolicyProbe
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
                .overlay(alignment: .top) {
                    if let hint = shellHint {
                        ShellHintChip(hint: hint,
                                      onCopy: { copy(hint) },
                                      onRun: { Task { await typeIntoPrompt(hint) } },
                                      onDismiss: { dismissHint(hint) })
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(DS.Motion.quick, value: shellHint)
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
                AgentBar(channel: ch, bridge: bridge, hotkeys: hotkeys,
                         dictator: dictator, voiceEnabled: voiceEnabled,
                         dictationLocaleID: dictationLocaleID,
                         onNotice: { toast = $0 }) {
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
            if let latest = await services.sessions.session(session.id) {
                sessionName = latest.displayName(on: host)
            }
        }
        .task {
            let appearance = await services.appearance.appearance
            showMascot = appearance.showMascotCompanion
            voiceEnabled = appearance.voiceDictationEnabled
            dictationLocaleID = appearance.dictationLocaleID
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
        .task(id: bridge != nil) {
            while !Task.isCancelled {
                refreshShellHint()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onChange(of: scenePhase) { _, new in
            if new == .active {
                bridge?.refit()
                startDisconnectWatcher()
            } else {
                dictator.cancel()
            }
        }
        .onAppear { WaitingSessionsStore.shared.markOpened(session.id) }
        .onDisappear {
            dictator.cancel()
            WaitingSessionsStore.shared.markOpened(session.id)
        }
        .onChange(of: photoItem) { _, new in
            guard let new else { return }
            Task { await uploadImage(new) }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .navigationTitle(sessionName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(sessionName).font(DS.Font.headline)
                        .foregroundStyle(DS.Color.textPrimary)
                        .lineLimit(1).truncationMode(.middle)
                    HStack(spacing: 5) {
                        StatusDot(color: connectPhase.color, pulsing: connectPhase == .connecting)
                        Text(connectPhase.label).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
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
        .sheet(isPresented: Binding(
            get: { urlPickerURLs != nil },
            set: { presenting in
                if !presenting { urlPickerURLs = nil }
            }
        )) {
            CopyURLPickerSheet(urls: urlPickerURLs ?? []) { picked in
                UIPasteboard.general.string = picked.raw
                toast = "Copied URL"
            } onOpen: { picked in
                Task { await openInBrowser(picked) }
            }
        }
        .sheet(item: $browserTarget, onDismiss: {
            let tunnel = browserTunnel
            browserTunnel = nil
            Task { await tunnel?.stop() }
        }) { target in
            SafariSheet(url: target.url) { browserTarget = nil }
                .ignoresSafeArea()
        }
    }

    private func openInBrowser(_ picked: DetectedURL) async {
        if let signIn = OAuthURLDetector.detect(picked.raw) {
            await openTunneled(signIn.originalURL, remoteHost: "localhost", port: signIn.port)
            return
        }
        guard let resolved = BrowserURLResolver.resolve(picked.raw) else {
            toast = "Can't open this URL"
            return
        }
        switch resolved {
        case .direct(let url):
            browserTarget = BrowserSheetTarget(url: url)
        case .tunneled(let open, let remoteHost, let port):
            await openTunneled(open, remoteHost: remoteHost, port: port)
        }
    }

    private func openTunneled(_ open: URL, remoteHost: String, port: Int) async {
        guard let ch = channel else {
            toast = "Not connected"
            return
        }
        if let old = browserTunnel {
            browserTunnel = nil
            await old.stop()
        }
        let tunnel = OAuthTunnel(port: port, sshChannel: ch, remoteHost: remoteHost)
        do {
            try await tunnel.start()
        } catch {
            NSLog("[sshido] tunnel to \(remoteHost):\(port) failed: \(error)")
            toast = "Tunnel to \(remoteHost):\(port) failed"
            return
        }
        browserTunnel = tunnel
        browserTarget = BrowserSheetTarget(url: open)
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
                let auth = try await services.credentials.auth(for: host)
                let ch = await SessionStore.shared.ensureChannel(for: session, host: host, auth: auth)
                NSLog("[sshido] SessionView.load got channel, awaiting first connect…")
                channel = ch
                let outcome = await waitForFirstConnection(ch)
                if case .connected = outcome {
                    NSLog("[sshido] SessionView.load: channel connected")
                    isReconnecting = false
                    showStuckRecovery = false
                    lookupHint = nil
                    startDisconnectWatcher()
                    return
                }
                if case .hostNotFound(let failure) = outcome, !isReconnecting {
                    NSLog("[sshido] SessionView.load: \(failure.description)")
                    await tearDown(ch)
                    self.error = failure.description
                    return
                }
                if case .hostNotFound(let failure) = outcome {
                    NSLog("[sshido] SessionView.load: \(failure.description), retrying")
                    lookupHint = failure.description
                }
                NSLog("[sshido] SessionView.load: first-connect did not finish, tearing down and retrying")
                await tearDown(ch)
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

    private enum FirstConnect {
        case connected, timedOut, hostNotFound(SSHError)
    }

    private func waitForFirstConnection(_ ch: SSHChannel, timeout: TimeInterval = 15) async -> FirstConnect {
        let start = Date()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if await ch.isConnected {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if await ch.isConnected { return .connected }
            }
            if let failure = await ch.connectFailure, case .hostNotFound = failure { return .hostNotFound(failure) }
            if Date().timeIntervalSince(start) > timeout { return .timedOut }
        }
        return .timedOut
    }

    private func tearDown(_ ch: SSHChannel) async {
        await ch.disconnect()
        BridgeStore.shared.remove(sessionID: session.id)
        bridge = nil
        channel = nil
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

    private var wheelPolicyProbe: () async -> Bool {
        let session = self.session
        let host = self.host
        let credentials = services.credentials
        return {
            guard let auth = try? await credentials.auth(for: host) else { return true }
            return await SessionStore.shared.paneForwardsWheel(for: session, host: host, auth: auth)
        }
    }

    private var loadingLabel: String {
        let name = sessionName
        if isReconnecting, let lookupHint { return "Reconnecting to \(name)… \(lookupHint)" }
        return isReconnecting ? "Reconnecting to \(name)…" : "Opening \(name)…"
    }

    private enum ConnectPhase {
        case online, connecting, offline

        var color: Color {
            switch self {
            case .online: return DS.Color.success
            case .connecting: return DS.Color.warning
            case .offline: return DS.Color.error
            }
        }

        var label: String {
            switch self {
            case .online: return "online"
            case .connecting: return "connecting"
            case .offline: return "offline"
            }
        }
    }

    private var connectPhase: ConnectPhase {
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

    private func refreshShellHint() {
        guard let bridge else { return }
        let rows = bridge.snapshotStyledLines(beforeViewport: 0, afterViewport: 0)
        let onScreen = ShellHintDetector.detect(in: rows, cols: bridge.cols)
        dismissedHints = dismissedHints.intersection(onScreen.map(\.command))
        shellHint = onScreen.last { !dismissedHints.contains($0.command) }
    }

    private func dismissHint(_ hint: DetectedShellHint) {
        dismissedHints = dismissedHints.union([hint.command])
        shellHint = nil
    }

    private func copy(_ hint: DetectedShellHint) {
        UIPasteboard.general.string = hint.command
        toast = "Copied command"
        dismissHint(hint)
    }

    private func typeIntoPrompt(_ hint: DetectedShellHint) async {
        guard let ch = channel else {
            toast = "Not connected"
            return
        }
        do {
            try await ch.send(Array(hint.promptInput.utf8))
        } catch {
            NSLog("[sshido] typing shell hint failed: \(error)")
            toast = "Couldn't type the command"
            return
        }
        dismissHint(hint)
        bridge?.focus()
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

struct BrowserSheetTarget: Identifiable, Equatable {
    let id = UUID()
    let url: URL
}
#endif
