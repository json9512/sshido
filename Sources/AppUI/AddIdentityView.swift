#if canImport(UIKit)
import SwiftUI
import UIKit
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif

struct AddIdentityView: View {
    var onAdded: (Identity) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var pem = ""
    @State private var error: String?
    @State private var savedIdentity: Identity?
    @State private var installCommand: String?
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            Form {
                if installCommand == nil {
                    Section("Label") {
                        TextField("e.g. MacBook id_ed25519", text: $label)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Section {
                        Button {
                            Task { await generateAndSave() }
                        } label: {
                            Label("Generate new Ed25519 key on this device", systemImage: "key.fill")
                        }
                        .disabled(label.isEmpty)
                    } footer: {
                        Text("Recommended. We create a modern SSH key here and you only need to paste a one-line command onto your server.")
                    }
                    Section {
                        TextEditor(text: $pem)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(minHeight: 120)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } header: {
                        Text("Or paste an existing private key")
                    } footer: {
                        Text("Ed25519 OpenSSH format (starts with -----BEGIN OPENSSH PRIVATE KEY-----).")
                    }
                }
                if let installCommand {
                    Section {
                        Button {
                            UIPasteboard.general.string = installCommand
                            toast = "Install command copied"
                        } label: {
                            Label("Copy install command", systemImage: "doc.on.doc")
                        }
                        Text(installCommand)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    } header: {
                        Text("Register public key on your server")
                    } footer: {
                        Text("Paste this command into a shell on your Mac to authorize this device. You only need to do this once per server.")
                    }
                }
                if let error {
                    Section { InlineErrorText(error) }
                }
            }
            .navigationTitle(installCommand == nil ? "Add key" : "Install on server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(installCommand == nil ? "Cancel" : "Done") { dismiss() }
                }
                if installCommand == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import") { Task { await save() } }
                            .disabled(label.isEmpty || pem.isEmpty)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil)
                    }
                }
            }
            .toast($toast)
        }
    }

    private func generateAndSave() async {
        let gen = PublicKeyDerivation.generateEd25519(comment: label.isEmpty ? "sshido" : label)
        do {
            let id = try await IdentityStore.shared.add(label: label, privateKeyPEM: gen.privateKeyPEM)
            savedIdentity = id
            onAdded(id)
            installCommand = PublicKeyDerivation.installCommand(forPublicKey: gen.publicKeyString)
        } catch {
            self.error = String(describing: error)
        }
    }

    private func save() async {
        do {
            let id = try await IdentityStore.shared.add(label: label, privateKeyPEM: pem)
            savedIdentity = id
            onAdded(id)
            if let pub = PublicKeyDerivation.openSSHPublicKey(fromPEM: pem, comment: label.isEmpty ? "sshido" : label) {
                installCommand = PublicKeyDerivation.installCommand(forPublicKey: pub)
            } else {
                dismiss()
            }
        } catch {
            self.error = String(describing: error)
        }
    }

}
#endif
