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

    private var englishPolicy: some View {
        VStack(alignment: .leading, spacing: 16) {
            policySection("Last updated", "October 3, 2026")

            policySection("Summary",
                "sshido is an SSH terminal and agent chat for iPhone and iPad. Your keys and terminal content stay between your device and your own servers. We do not sell data or use advertising trackers.")

            policySection("Local storage",
                "SSH credentials are encrypted at rest in the iOS Keychain and accessible only while your device is unlocked. Host configs, sessions, and preferences are stored locally in the app sandbox. None of this is uploaded.")

            policySection("Push notifications (optional)",
                "If enabled, your APNs device token is sent to push.sshido.com over HTTPS. The relay stores only a random subscriber ID, the token, a notification count, and a mute flag. When your server or an agent sends an alert, its title and text pass through the relay to Apple's push service so they can appear on your device; the relay does not store them. No credentials or personal info is stored. The relay's source is public; a relay you run yourself works only with your own build of sshido.")

            policySection("Agent mode (optional)",
                "Agent mode runs on a server you choose, reached over SSH. Chats, agents, and their files are stored on that server, not by sshido. Agents use the model providers you sign in to (such as Anthropic, OpenAI, Google, or xAI) or a model you host yourself. Prompts and files go from your server to those providers under their terms, never through sshido. On Linux servers, Claude agents use that server's own Claude Code setup, including its connectors and MCP servers.")

            policySection("Crash reporting",
                "sshido uses Sentry to collect crash reports and performance diagnostics. Sentry may receive device model, OS version, stack traces, and breadcrumb logs. Each report carries a random install identifier, not your name or email. No SSH credentials, terminal content, or personal data is included in crash reports. You can turn crash reports off in Settings › Privacy. See sentry.io/privacy for Sentry's privacy policy.")

            policySection("SSH connections",
                "Commands you type are sent to your remote server via SSH. sshido does not intercept or log this traffic.")

            policySection("Data deletion",
                "Uninstall the app to remove all local data. Push subscription data on the relay (subscription ID, device token, notify count) persists until removal is requested — email privacy@sshido.com to delete it.")

            policySection("Children",
                "Not intended for children under 13.")

            policySection("Contact",
                "privacy@sshido.com")
        }
    }

    private var koreanPolicy: some View {
        VStack(alignment: .leading, spacing: 16) {
            policySection("최종 수정일", "2026년 10월 3일")

            policySection("요약",
                "sshido는 iPhone과 iPad용 SSH 터미널이자 에이전트 채팅 앱입니다. 키와 터미널 내용은 기기와 사용자의 서버 사이에서만 오갑니다. 데이터를 판매하지 않으며 광고 추적 도구를 쓰지 않습니다.")

            policySection("로컬 저장",
                "SSH 자격 증명은 iOS 키체인에 암호화되어 저장되며, 기기 잠금이 해제된 상태에서만 접근할 수 있습니다. 호스트 설정, 세션, 환경설정은 앱 샌드박스에 로컬 저장됩니다. 서버에 업로드되지 않습니다.")

            policySection("푸시 알림 (선택 사항)",
                "활성화 시 APNs 기기 토큰이 HTTPS로 push.sshido.com에 전송됩니다. 릴레이는 무작위 구독자 ID, 토큰, 알림 횟수, 알림 끄기 여부만 저장합니다. 서버나 에이전트가 알림을 보내면 그 제목과 내용이 기기에 표시되도록 릴레이를 거쳐 Apple 푸시 서비스로 전달되며, 릴레이는 이를 저장하지 않습니다. 자격 증명과 개인정보는 저장하지 않습니다. 릴레이 소스는 공개되어 있으며, 직접 운영하는 릴레이는 직접 빌드한 sshido에서만 동작합니다.")

            policySection("에이전트 모드 (선택 사항)",
                "에이전트 모드는 사용자가 고른 서버에서 SSH로 실행됩니다. 채팅, 에이전트, 작업 파일은 sshido가 아니라 그 서버에 저장됩니다. 에이전트는 사용자가 로그인한 모델 제공자(Anthropic, OpenAI, Google, xAI 등)나 직접 운영하는 모델을 사용합니다. 프롬프트와 파일은 서버에서 해당 제공자로 직접 전송되며 각 제공자의 약관을 따르고, sshido를 거치지 않습니다. Linux 서버에서는 Claude 에이전트가 그 서버의 Claude Code 설정(커넥터와 MCP 서버 포함)을 사용합니다.")

            policySection("충돌 보고",
                "sshido는 Sentry를 사용하여 충돌 보고서 및 성능 진단을 수집합니다. Sentry는 기기 모델, OS 버전, 스택 트레이스, 브레드크럼 로그를 수신할 수 있습니다. 각 보고서에는 이름이나 이메일이 아닌 무작위 설치 식별자가 포함됩니다. SSH 자격 증명, 터미널 내용 또는 개인 데이터는 충돌 보고서에 포함되지 않습니다. Settings › Privacy에서 충돌 보고를 끌 수 있습니다. Sentry의 개인정보 처리방침은 sentry.io/privacy를 참조하세요.")

            policySection("SSH 연결",
                "입력한 명령은 SSH를 통해 원격 서버로 전송됩니다. sshido는 이 트래픽을 가로채거나 기록하지 않습니다.")

            policySection("데이터 삭제",
                "앱을 삭제하면 모든 로컬 데이터가 제거됩니다. 릴레이에 저장된 푸시 구독 데이터(구독 ID, 기기 토큰, 알림 횟수)는 삭제 요청 시까지 보관됩니다. 삭제를 원하시면 privacy@sshido.com으로 문의해 주세요.")

            policySection("아동",
                "13세 미만 아동을 대상으로 하지 않습니다.")

            policySection("문의",
                "privacy@sshido.com")
        }
    }

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
