#if canImport(UIKit)
import SwiftUI

public struct PrivacyPolicyView: View {
    @State private var lang: Lang = Locale.current.language.languageCode?.identifier == "ko" ? .ko : .en

    enum Lang: String, CaseIterable {
        case en, ko
        var label: String { self == .en ? "English" : "한국어" }
    }

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Language", selection: $lang) {
                    ForEach(Lang.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 8)

                if lang == .en { englishPolicy } else { koreanPolicy }
            }
            .padding()
        }
        .background(DS.Color.surface0)
        .navigationTitle(lang == .en ? "Privacy Policy" : "개인정보 처리방침")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - English

    private var englishPolicy: some View {
        VStack(alignment: .leading, spacing: 16) {
            policySection("Last updated", "May 6, 2026")

            policySection("Summary",
                "sshido is an iOS SSH terminal. Your data stays on your device. We do not track usage or sell data.")

            policySection("Local storage",
                "SSH credentials are encrypted in the iOS Keychain (Face ID / Touch ID protected). Host configs, sessions, and preferences are stored locally in the app sandbox. None of this is uploaded.")

            policySection("Push notifications (optional)",
                "If enabled, your APNs device token is sent to push.sshido.com over HTTPS. The relay stores only a random subscriber ID, the token, and a notification count. No credentials, terminal content, or personal info is stored. You may self-host the relay.")

            policySection("Crash reporting",
                "sshido uses Sentry to collect crash reports and performance diagnostics. Sentry may receive device model, OS version, stack traces, and breadcrumb logs. No SSH credentials, terminal content, or personal data is included in crash reports. See sentry.io/privacy for Sentry's privacy policy.")

            policySection("SSH connections",
                "Commands you type are sent to your remote server via SSH. sshido does not intercept or log this traffic.")

            policySection("Data deletion",
                "Uninstall the app to remove all local data. Unsubscribe from push notifications to remove relay data.")

            policySection("Children",
                "Not intended for children under 13.")

            policySection("Contact",
                "privacy@sshido.com")
        }
    }

    // MARK: - Korean

    private var koreanPolicy: some View {
        VStack(alignment: .leading, spacing: 16) {
            policySection("최종 수정일", "2026년 5월 6일")

            policySection("요약",
                "sshido는 iOS SSH 터미널입니다. 데이터는 기기에 저장되며, 사용을 추적하거나 데이터를 판매하지 않습니다.")

            policySection("로컬 저장",
                "SSH 자격 증명은 iOS 키체인에 암호화됩니다 (Face ID / Touch ID 보호). 호스트 설정, 세션, 환경설정은 앱 샌드박스에 로컬 저장됩니다. 서버에 업로드되지 않습니다.")

            policySection("푸시 알림 (선택 사항)",
                "활성화 시 APNs 기기 토큰이 HTTPS로 push.sshido.com에 전송됩니다. 릴레이는 무작위 구독자 ID, 토큰, 알림 횟수만 저장합니다. 자격 증명, 터미널 내용, 개인정보는 저장하지 않습니다. 자체 릴레이 호스팅이 가능합니다.")

            policySection("충돌 보고",
                "sshido는 Sentry를 사용하여 충돌 보고서 및 성능 진단을 수집합니다. Sentry는 기기 모델, OS 버전, 스택 트레이스, 브레드크럼 로그를 수신할 수 있습니다. SSH 자격 증명, 터미널 내용 또는 개인 데이터는 충돌 보고서에 포함되지 않습니다. Sentry의 개인정보 처리방침은 sentry.io/privacy를 참조하세요.")

            policySection("SSH 연결",
                "입력한 명령은 SSH를 통해 원격 서버로 전송됩니다. sshido는 이 트래픽을 가로채거나 기록하지 않습니다.")

            policySection("데이터 삭제",
                "앱을 삭제하면 모든 로컬 데이터가 제거됩니다. 푸시 알림 구독을 취소하면 릴레이 데이터가 제거됩니다.")

            policySection("아동",
                "13세 미만 아동을 대상으로 하지 않습니다.")

            policySection("문의",
                "privacy@sshido.com")
        }
    }

    // MARK: - Helpers

    private func policySection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(DS.Font.callout).bold()
                .foregroundStyle(DS.Color.textPrimary)
            Text(body)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textSecondary)
                .lineSpacing(4)
        }
    }
}
#endif
