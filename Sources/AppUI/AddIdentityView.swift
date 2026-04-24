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
                    Section(header: DSSectionHeader("Label")) {
                        TextField("e.g. MacBook id_ed25519", text: $label)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .dsRow()
                    }
                    Section {
                        Button {
                            Task { await generateAndSave() }
                        } label: {
                            Label("Generate new Ed25519 key on this device", systemImage: "key.fill")
                                .foregroundStyle(DS.Color.accent)
                        }
                        .disabled(label.isEmpty)
                        .dsRow()
                    } footer: {
                        Text("Recommended. We create a modern SSH key here and you only need to paste a one-line command onto your server.")
                            .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                    }
                    Section {
                        TextEditor(text: $pem)
                            .font(DS.Font.monoSmall)
                            .foregroundStyle(DS.Color.textPrimary)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 120)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .dsRow()
                    } header: {
                        DSSectionHeader("Or paste an existing private key")
                    } footer: {
                        Text("Ed25519 OpenSSH format (starts with -----BEGIN OPENSSH PRIVATE KEY-----).")
                            .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                    }
                }
                if let installCommand {
                    Section {
                        Button {
                            UIPasteboard.general.string = installCommand
                            toast = "Install command copied"
                        } label: {
                            Label("Copy install command", systemImage: "doc.on.doc")
                                .foregroundStyle(DS.Color.accent)
                        }
                        .dsRow()
                        Text(installCommand)
                            .font(DS.Font.monoSmall)
                            .foregroundStyle(DS.Color.textSecondary)
                            .textSelection(.enabled)
                            .dsRow()
                    } header: {
                        DSSectionHeader("Register public key on your server")
                    } footer: {
                        Text("Paste this command into a shell on your Mac to authorize this device. You only need to do this once per server.")
                            .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                    }
                }
                if let error {
                    Section { InlineErrorText(error).dsRow() }
                }
            }
            .dsFormStyle()
            .navigationTitle(installCommand == nil ? "Add key" : "Install on server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if installCommand == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import") { Task { await save() } }
                            .disabled(label.isEmpty || pem.isEmpty)
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .dsKeyboardDismissToolbar()
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
