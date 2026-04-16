#if canImport(UIKit)
import SwiftUI
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Label") {
                    TextField("e.g. MacBook id_ed25519", text: $label)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Private key (OpenSSH)") {
                    TextEditor(text: $pem)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 180)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Add key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(label.isEmpty || pem.isEmpty)
                }
            }
        }
    }

    private func save() async {
        do {
            let id = try await IdentityStore.shared.add(label: label, privateKeyPEM: pem)
            onAdded(id)
            dismiss()
        } catch {
            self.error = String(describing: error)
        }
    }
}
#endif
