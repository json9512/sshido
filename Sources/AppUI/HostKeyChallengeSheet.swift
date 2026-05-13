#if canImport(UIKit)
import SwiftUI
import UIKit
#if canImport(sshidoModels)
import sshidoModels
#endif

/// Modal presented on first-connect (unknown host) or on host-key
/// mismatch. User must explicitly tap Trust or Cancel; swipe-to-dismiss
/// is disabled because absent input would be ambiguous and the safe
/// default (reject) is one tap away anyway.
struct HostKeyChallengeSheet: View {
    let challenge: HostKeyChallenge
    let onDecision: (HostKeyDecision) -> Void

    @State private var confirmReplace = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    header
                    fingerprintBlock
                    actions
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.md)
                .padding(.bottom, DS.Spacing.xl)
            }
            .background(DS.Color.surface0)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
        }
        .alert("Replace stored fingerprint?", isPresented: $confirmReplace) {
            Button("Cancel", role: .cancel) {}
            Button("Replace and connect", role: .destructive) {
                onDecision(.trust)
            }
        } message: {
            Text("This is exactly what a man-in-the-middle attack would prompt you to do. Only replace if you have an out-of-band reason to expect the key changed — server rebuild, key rotation announced by the operator, etc.")
        }
    }

    private var title: String {
        switch challenge {
        case .unknownHost: return "Verify host key"
        case .mismatch:    return "Host key changed"
        }
    }

    @ViewBuilder
    private var header: some View {
        switch challenge {
        case .unknownHost(let host, let port, _):
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 36))
                    .foregroundStyle(DS.Color.accent)
                Text("First time connecting to")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                Text("\(host):\(port)")
                    .font(DS.Font.mono)
                    .foregroundStyle(DS.Color.textPrimary)
                Text("Verify the fingerprint below against what your server's admin shows you. The same value comes out of `ssh-keygen -l -f /etc/ssh/ssh_host_ed25519_key.pub` on the server.")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .padding(.top, DS.Spacing.xs)
            }
        case .mismatch(let host, let port, _, _):
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(DS.Color.error)
                Text("Stored fingerprint does not match")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                Text("\(host):\(port)")
                    .font(DS.Font.mono)
                    .foregroundStyle(DS.Color.textPrimary)
                Text("Someone may be intercepting your connection. The server may also have legitimately rotated its key — but treat that as the rare case.")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.error)
                    .padding(.top, DS.Spacing.xs)
            }
        }
    }

    @ViewBuilder
    private var fingerprintBlock: some View {
        switch challenge {
        case .unknownHost(_, _, let fp):
            fingerprintRow(label: "Presented", value: fp)
        case .mismatch(_, _, let expected, let presented):
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                fingerprintRow(label: "Expected (stored)", value: expected)
                fingerprintRow(label: "Presented now", value: presented)
            }
        }
    }

    private func fingerprintRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = value
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundStyle(DS.Color.accent)
                }
                .buttonStyle(.plain)
                .help("Copy fingerprint")
            }
            Text(value)
                .font(DS.Font.mono)
                .foregroundStyle(DS.Color.textPrimary)
                .textSelection(.enabled)
                .padding(DS.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.Color.surface2, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch challenge {
        case .unknownHost:
            VStack(spacing: DS.Spacing.sm) {
                Button {
                    onDecision(.trust)
                } label: {
                    Text("Trust & connect")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(DS.Color.accent)

                Button(role: .cancel) {
                    onDecision(.reject)
                } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
            }
        case .mismatch:
            VStack(spacing: DS.Spacing.sm) {
                Button {
                    onDecision(.reject)
                } label: {
                    Text("Cancel (recommended)")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(DS.Color.accent)

                Button(role: .destructive) {
                    confirmReplace = true
                } label: {
                    Text("Replace stored fingerprint")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.Color.error)
            }
        }
    }
}
#endif
