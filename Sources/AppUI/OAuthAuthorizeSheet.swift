#if canImport(UIKit)
import SwiftUI
import SafariServices
#if canImport(sshidoCore)
import sshidoCore
#endif

@MainActor
final class OAuthAuthorizeFlow: ObservableObject {
    @Published var presentedURL: URL?
    @Published var pastePromptActive = false
    @Published var toast: String?

    private var tunnel: OAuthTunnel?

    func startAuthorize(target: OAuthTunnelTarget, channel: SSHChannel) async {
        await tearDown()
        let t = OAuthTunnel(port: target.port, sshChannel: channel)
        do {
            try await t.start()
        } catch {
            toast = "Couldn't open tunnel: \(error)"
            return
        }
        tunnel = t
        presentedURL = target.originalURL
    }

    func sessionDismissed() async {
        await tearDown()
    }

    func finishWithPastedCallback(_ raw: String, channel: SSHChannel) async {
        do {
            try await OAuthCallbackDelivery.deliver(callbackURL: raw, through: channel)
            toast = "Callback delivered"
        } catch {
            toast = "Callback failed: \(error)"
        }
    }

    private func tearDown() async {
        presentedURL = nil
        if let t = tunnel { await t.stop() }
        tunnel = nil
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

struct PasteCallbackSheet: View {
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://localhost:…/callback?code=…", text: $text, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(3, reservesSpace: true)
                } header: {
                    Text("Paste callback URL")
                } footer: {
                    Text("If your OAuth flow ended on a \"can't connect to localhost\" page, copy the URL from Safari's address bar and paste it here.")
                }
                Section {
                    Button("Paste from clipboard") {
                        if let s = UIPasteboard.general.string { text = s }
                    }
                }
            }
            .navigationTitle("Finish sign-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        onSubmit(text)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .dsKeyboardDismissToolbar()
        }
    }
}
#endif
