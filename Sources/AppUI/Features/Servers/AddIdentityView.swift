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
    @Environment(\.services) private var services
    @State private var label = ""
    @State private var pem = ""
    @State private var error: String?
    @State private var installCommand: String?
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            List {
                if let installCommand {
                    Section {
                        CopyableCode(text: installCommand) { toast = "Copied" }.tideRow()
                    } header: {
                        SectionLabel("Run once on each server")
                    }
                } else {
                    Section {
                        TextField("Label", text: $label)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .frame(minHeight: DS.hitTarget)
                            .tideRow()
                    }
                    Section {
                        Button { Task { await generate() } } label: {
                            TideRow(icon: "wand.and.stars", title: "Generate Ed25519 key", subtitle: "Recommended")
                        }
                        .disabled(label.isEmpty)
                        .tideRow()
                    }
                    Section {
                        TextEditor(text: $pem)
                            .font(DS.Font.monoSmall)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 140)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .overlay(alignment: .topLeading) {
                                if pem.isEmpty {
                                    Text("-----BEGIN OPENSSH PRIVATE KEY-----")
                                        .font(DS.Font.monoSmall).foregroundStyle(DS.Color.textTertiary)
                                        .padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                                }
                            }
                            .tideRow()
                    } header: {
                        SectionLabel("Or paste an Ed25519 private key")
                    }
                }
                if let error {
                    Section { InlineErrorText(error).tideRow() }
                }
            }
            .tideList()
            .navigationTitle(installCommand == nil ? "New key" : "Install key")
            .navigationBarTitleDisplayMode(.inline)
            .sheetActions(cancel: installCommand == nil ? { dismiss() } : nil,
                          confirm: installCommand == nil ? { Task { await importPasted() } } : { dismiss() },
                          confirmEnabled: installCommand != nil || (!label.isEmpty && !pem.isEmpty))
            .keyboardDismissButton()
            .toast($toast)
        }
    }

    private func generate() async {
        let generated = PublicKeyDerivation.generateEd25519(comment: label.isEmpty ? "sshido" : label)
        do {
            let identity = try await services.identities.add(label: label, privateKeyPEM: generated.privateKeyPEM)
            onAdded(identity)
            installCommand = PublicKeyDerivation.installCommand(forPublicKey: generated.publicKeyString)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func importPasted() async {
        do {
            let identity = try await services.identities.add(label: label, privateKeyPEM: pem)
            onAdded(identity)
            guard let pub = PublicKeyDerivation.openSSHPublicKey(fromPEM: pem, comment: label.isEmpty ? "sshido" : label) else {
                dismiss()
                return
            }
            installCommand = PublicKeyDerivation.installCommand(forPublicKey: pub)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
#endif
