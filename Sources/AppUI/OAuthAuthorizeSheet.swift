#if canImport(UIKit)
import SwiftUI
import SafariServices
#if canImport(sshidoCore)
import sshidoCore
#endif

@MainActor
final class AuthorizeSignInController: ObservableObject {
    enum Phase: Equatable {
        case scanning
        case noURLFound
        case ready(OAuthTunnelTarget)
        case openingSafari(OAuthTunnelTarget)
        case awaitingReturn(OAuthTunnelTarget)
        case manualPaste(prefilled: String?)
        case delivering
        case success
        case failed(String)
    }

    enum ActiveSheet: Identifiable, Equatable {
        case authorize
        case safari(URL)

        var id: String {
            switch self {
            case .authorize: return "authorize"
            case .safari(let url): return "safari:\(url.absoluteString)"
            }
        }
    }

    @Published var phase: Phase = .scanning
    @Published var activeSheet: ActiveSheet?
    @Published var toast: String?

    private var tunnel: OAuthTunnel?
    private weak var channel: SSHChannel?

    func present(channel: SSHChannel, urls: [DetectedURL]) {
        self.channel = channel
        phase = .scanning
        activeSheet = .authorize
        Task { await beginScan(urls: urls) }
    }

    private func beginScan(urls: [DetectedURL]) async {
        guard let channel else {
            phase = .failed("Session not connected")
            return
        }
        for detected in urls {
            guard let target = OAuthURLDetector.detect(detected.url.absoluteString) else { continue }
            let t = OAuthTunnel(port: target.port, sshChannel: channel)
            do {
                try await t.start()
            } catch {
                phase = .failed("Couldn't open tunnel: \(error)")
                return
            }
            tunnel = t
            phase = .ready(target)
            return
        }
        phase = .noURLFound
    }

    func openInSafari() {
        if case .ready(let target) = phase {
            phase = .openingSafari(target)
            activeSheet = .safari(target.originalURL)
        }
    }

    func safariDismissed() {
        if case .openingSafari(let target) = phase {
            phase = .awaitingReturn(target)
            activeSheet = .authorize
        }
    }

    func userSaidItWorked() async {
        await tearDown()
        phase = .success
        toast = "Signed in"
    }

    func userSaidConnectionFailed() {
        phase = .manualPaste(prefilled: clipboardCallbackPrefill())
    }

    func chooseManualPaste() {
        phase = .manualPaste(prefilled: clipboardCallbackPrefill())
    }

    func submit(pastedCallback: String) async {
        guard let channel else {
            phase = .failed("Session not connected")
            return
        }
        phase = .delivering
        do {
            try await OAuthCallbackDelivery.deliver(callbackURL: pastedCallback, through: channel)
            await tearDown()
            phase = .success
            toast = "Signed in"
        } catch {
            phase = .failed("Couldn't deliver callback: \(error)")
        }
    }

    func reset() {
        phase = .scanning
        Task { [weak self] in
            await self?.tearDown()
            self?.phase = .noURLFound
        }
    }

    func cancel() async {
        await tearDown()
        activeSheet = nil
    }

    private func tearDown() async {
        if let t = tunnel { await t.stop() }
        tunnel = nil
    }

    private func clipboardCallbackPrefill() -> String? {
        guard let raw = UIPasteboard.general.string?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw),
              url.scheme?.lowercased() == "http",
              let host = url.host?.lowercased(),
              host == "localhost" || host == "127.0.0.1",
              url.port != nil
        else { return nil }
        return raw
    }
}

struct AuthorizeSignInSheet: View {
    @ObservedObject var controller: AuthorizeSignInController

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.Color.surface0.ignoresSafeArea())
                .navigationTitle("Authorize sign-in")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            Task { await controller.cancel() }
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch controller.phase {
        case .scanning:
            centered {
                ProgressView()
                Text("Looking for an OAuth URL on screen…")
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.textSecondary)
            }
        case .noURLFound:
            noURLFoundView
        case .ready(let target):
            readyView(target: target)
        case .openingSafari, .awaitingReturn:
            awaitingReturnView
        case .manualPaste(let prefilled):
            ManualPasteForm(prefilled: prefilled) { pasted in
                Task { await controller.submit(pastedCallback: pasted) }
            }
        case .delivering:
            centered {
                ProgressView()
                Text("Sending callback through SSH…")
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.textSecondary)
            }
        case .success:
            successView
        case .failed(let msg):
            failureView(message: msg)
        }
    }

    @ViewBuilder
    private var noURLFoundView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(DS.Color.textTertiary)
            Text("No OAuth URL on screen")
                .font(DS.Font.rowTitle)
                .foregroundStyle(DS.Color.textPrimary)
            Text("Trigger the sign-in command in your shell first, or paste a callback URL you already opened in another browser.")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                controller.chooseManualPaste()
            } label: {
                Label("Paste callback URL instead", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func readyView(target: OAuthTunnelTarget) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Step 1 — URL found")
            VStack(alignment: .leading, spacing: 4) {
                Text(target.originalURL.host ?? target.originalURL.absoluteString)
                    .font(DS.Font.rowTitle)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(target.originalURL.absoluteString)
                    .font(DS.Font.monoSmall)
                    .foregroundStyle(DS.Color.textTertiary)
                    .lineLimit(3)
                    .truncationMode(.middle)
            }
            Text("Tap below to authorize. We'll forward the callback over your SSH connection so localhost works on the agent host, not your phone.")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)
            Button {
                controller.openInSafari()
            } label: {
                Label("Open sign-in", systemImage: "safari")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var awaitingReturnView: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Step 2 — Did sign-in finish?")
            Text("If Safari showed a success page, you're done. If it stalled on a “can't connect to localhost” error, paste the URL from Safari's address bar.")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)
            Button {
                Task { await controller.userSaidItWorked() }
            } label: {
                Label("It worked", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button {
                controller.userSaidConnectionFailed()
            } label: {
                Label("I saw “can't connect”", systemImage: "exclamationmark.triangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var successView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(DS.Color.success)
            Text("Sign-in delivered")
                .font(DS.Font.rowTitle)
                .foregroundStyle(DS.Color.textPrimary)
            Text("The callback was forwarded over SSH. Check your terminal to confirm the agent picked it up.")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Done") {
                Task { await controller.cancel() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func failureView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(DS.Color.error)
            Text("Couldn't finish sign-in")
                .font(DS.Font.rowTitle)
                .foregroundStyle(DS.Color.textPrimary)
            Text(message)
                .font(DS.Font.monoSmall)
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            HStack(spacing: 12) {
                Button {
                    controller.reset()
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                Button {
                    controller.chooseManualPaste()
                } label: {
                    Label("Paste callback URL", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(DS.Font.captionMedium)
            .foregroundStyle(DS.Color.textSecondary)
            .textCase(.uppercase)
    }

    @ViewBuilder
    private func centered<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 12) { content() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ManualPasteForm: View {
    let prefilled: String?
    let onSubmit: (String) -> Void

    @State private var text: String
    @FocusState private var focused: Bool

    init(prefilled: String?, onSubmit: @escaping (String) -> Void) {
        self.prefilled = prefilled
        self.onSubmit = onSubmit
        _text = State(initialValue: prefilled ?? "")
    }

    var body: some View {
        Form {
            Section {
                TextField("http://localhost:…/callback?code=…", text: $text, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .lineLimit(3, reservesSpace: true)
                    .focused($focused)
            } header: {
                Text("Paste callback URL")
            } footer: {
                Text("Copy the URL from Safari's address bar (it usually starts with http://localhost) and paste it here. We'll forward it over SSH.")
            }
            Section {
                Button {
                    if let s = UIPasteboard.general.string?
                        .trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                        text = s
                    }
                } label: {
                    Label("Paste from clipboard", systemImage: "doc.on.clipboard")
                }
                Button {
                    onSubmit(text)
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            if !text.isEmpty { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { focused = true }
        }
    }
}

struct SafariSheet: UIViewControllerRepresentable {
    let url: URL
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.barCollapsingEnabled = true
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.delegate = context.coordinator
        vc.dismissButtonStyle = .done
        return vc
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) { onDismiss() }
    }
}
#endif
