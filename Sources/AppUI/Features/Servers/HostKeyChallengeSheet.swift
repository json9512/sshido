#if canImport(UIKit)
import SwiftUI
import UIKit
#if canImport(sshidoModels)
import sshidoModels
#endif

struct HostKeyChallengeSheet: View {
    let challenge: HostKeyChallenge
    let onDecision: (HostKeyDecision) -> Void

    @State private var confirmReplace = false
    @State private var toast: String?

    var body: some View {
        VStack(spacing: DS.Spacing.xl) {
            Spacer(minLength: DS.Spacing.lg)
            Image(systemName: isMismatch ? "exclamationmark.shield.fill" : "lock.shield")
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(isMismatch ? DS.Color.error : DS.Color.accent)
            VStack(spacing: DS.Spacing.xs) {
                Text(isMismatch ? "Host key changed" : "New host")
                    .font(DS.Font.title)
                Text(endpoint).font(DS.Font.monoBody).foregroundStyle(DS.Color.textSecondary)
            }
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                ForEach(fingerprints, id: \.label) { item in
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        SectionLabel(item.label)
                        CopyableCode(text: item.value) { toast = "Copied" }
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            Spacer()
            HStack(spacing: DS.Spacing.xxl) {
                if isMismatch {
                    IconButton(systemName: "arrow.triangle.2.circlepath", label: "Replace stored fingerprint", kind: .destructive, size: 60) {
                        confirmReplace = true
                    }
                    IconButton(systemName: "xmark", label: "Cancel", kind: .primary, size: 60) { onDecision(.reject) }
                } else {
                    IconButton(systemName: "xmark", label: "Cancel", size: 60) { onDecision(.reject) }
                    IconButton(systemName: "checkmark.shield.fill", label: "Trust & connect", kind: .primary, size: 60) { onDecision(.trust) }
                }
            }
            .padding(.bottom, DS.Spacing.xl)
        }
        .frame(maxWidth: .infinity)
        .tideScreen()
        .interactiveDismissDisabled()
        .toast($toast)
        .alert("Replace the stored fingerprint?", isPresented: $confirmReplace) {
            Button("Replace", role: .destructive) { onDecision(.trust) }
        } message: {
            Text("Only if you know the server's key really changed. Otherwise someone may be intercepting the connection.")
        }
    }

    private var isMismatch: Bool {
        if case .mismatch = challenge { return true }
        return false
    }

    private var endpoint: String {
        switch challenge {
        case .unknownHost(let host, let port, _), .mismatch(let host, let port, _, _): return "\(host):\(port)"
        }
    }

    private var fingerprints: [(label: String, value: String)] {
        switch challenge {
        case .unknownHost(_, _, let presented):
            return [("SHA256", presented)]
        case .mismatch(_, _, let expected, let presented):
            return [("Trusted", expected), ("Presented now", presented)]
        }
    }
}
#endif
