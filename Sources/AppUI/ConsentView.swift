#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoCore)
import sshidoCore
#endif

public struct ConsentView: View {
    let onAccept: () -> Void
    @State private var showFullPolicy = false

    private var isKorean: Bool {
        Locale.current.language.languageCode?.identifier == "ko"
    }

    public init(onAccept: @escaping () -> Void) {
        self.onAccept = onAccept
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: DS.Spacing.lg) {
                Spacer()

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(DS.Color.accent)

                Text(isKorean ? "개인정보 보호" : "Your Privacy")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(DS.Color.textPrimary)

                VStack(alignment: .leading, spacing: 12) {
                    bulletPoint(
                        icon: "iphone",
                        text: isKorean
                            ? "모든 데이터는 기기에 로컬로 저장됩니다"
                            : "All data is stored locally on your device"
                    )
                    bulletPoint(
                        icon: "xmark.shield",
                        text: isKorean
                            ? "분석, 추적 또는 광고가 없습니다"
                            : "No analytics, tracking, or ads"
                    )
                    bulletPoint(
                        icon: "key.fill",
                        text: isKorean
                            ? "SSH 자격 증명은 iOS 키체인에 암호화됩니다"
                            : "SSH credentials are encrypted in the iOS Keychain"
                    )
                    bulletPoint(
                        icon: "bell.badge",
                        text: isKorean
                            ? "푸시 알림은 선택 사항이며 자체 호스팅 가능합니다"
                            : "Push notifications are optional and self-hostable"
                    )
                    bulletPoint(
                        icon: "ladybug",
                        text: isKorean
                            ? "익명 충돌 보고 (Sentry, 자격 증명·터미널 내용 제외) — 설정에서 끌 수 있습니다"
                            : "Anonymous crash reports via Sentry (no credentials, no terminal content) — can be disabled in Settings"
                    )
                }
                .padding()
                .background(DS.Color.surface1, in: RoundedRectangle(cornerRadius: 12))

                Button {
                    showFullPolicy = true
                } label: {
                    Text(isKorean ? "전체 개인정보 처리방침 보기" : "Read full privacy policy")
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.accent)
                }

                Spacer()

                Button {
                    UserDefaults.standard.set(true, forKey: "sshido.privacyAccepted")
                    onAccept()
                } label: {
                    Text(isKorean ? "동의하고 계속하기" : "Agree & Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(DS.Color.accent)
                .padding(.bottom, DS.Spacing.lg)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .background(DS.Color.surface0)
            .interactiveDismissDisabled()
            .navigationDestination(isPresented: $showFullPolicy) {
                PrivacyPolicyView()
            }
        }
    }

    private func bulletPoint(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(DS.Color.accent)
                .frame(width: 24)
            Text(text)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textPrimary)
        }
    }
}
#endif
