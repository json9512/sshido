package main

import (
	"fmt"
	"net/http"
	"strings"
)

func (s *server) privacy(w http.ResponseWriter, r *http.Request) {
	lang := r.URL.Query().Get("lang")
	if lang == "" {
		accept := r.Header.Get("Accept-Language")
		if strings.Contains(accept, "ko") {
			lang = "ko"
		} else {
			lang = "en"
		}
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	page := privacyEn
	if lang == "ko" {
		page = privacyKo
	}
	fmt.Fprint(w, strings.ReplaceAll(page, "{{CONTACT}}", s.cfg.privacyContact))
}

const privacyEn = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>sshido - Privacy Policy</title>
<style>
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;max-width:680px;margin:0 auto;padding:24px;background:#0d0d0d;color:#e0e0e0;line-height:1.6}
h1{color:#4fd1c5;font-size:1.6em}
h2{color:#a0aec0;font-size:1.1em;margin-top:1.6em}
a{color:#4fd1c5}
.lang{text-align:right;margin-bottom:1em}
.lang a{margin-left:12px}
.updated{color:#718096;font-size:.9em}
</style>
</head>
<body>
<div class="lang"><a href="?lang=en">English</a> <a href="?lang=ko">한국어</a></div>
<h1>sshido Privacy Policy</h1>
<p class="updated">Last updated: May 6, 2026</p>

<h2>Summary</h2>
<p>sshido is an iOS SSH terminal. Your data stays on your device. We do not track usage or sell data.</p>

<h2>Local storage</h2>
<p>SSH credentials are encrypted at rest in the iOS Keychain and accessible only while your device is unlocked. Host configs, sessions, and preferences are stored locally in the app sandbox. None of this is uploaded.</p>

<h2>Push notifications (optional)</h2>
<p>If enabled, your APNs device token is sent to push.sshido.com over HTTPS. The relay stores only a random subscriber ID, the token, and a notification count. No credentials, terminal content, or personal info is stored. You may self-host the relay.</p>

<h2>Crash reporting</h2>
<p>sshido uses <a href="https://sentry.io">Sentry</a> to collect crash reports and performance diagnostics. Sentry may receive device model, OS version, stack traces, and breadcrumb logs. No SSH credentials, terminal content, or personal data is included in crash reports. See <a href="https://sentry.io/privacy/">Sentry's privacy policy</a>.</p>

<h2>SSH connections</h2>
<p>Commands you type are sent to your remote server via SSH. sshido does not intercept or log this traffic.</p>

<h2>Data deletion</h2>
<p>Uninstall the app to remove all local data. Unsubscribe from push notifications to remove relay data.</p>

<h2>Children</h2>
<p>Not intended for children under 13.</p>

<h2>Contact</h2>
<p><a href="mailto:{{CONTACT}}">{{CONTACT}}</a></p>
</body>
</html>`

const privacyKo = `<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>sshido - 개인정보 처리방침</title>
<style>
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;max-width:680px;margin:0 auto;padding:24px;background:#0d0d0d;color:#e0e0e0;line-height:1.8}
h1{color:#4fd1c5;font-size:1.6em}
h2{color:#a0aec0;font-size:1.1em;margin-top:1.6em}
a{color:#4fd1c5}
.lang{text-align:right;margin-bottom:1em}
.lang a{margin-left:12px}
.updated{color:#718096;font-size:.9em}
</style>
</head>
<body>
<div class="lang"><a href="?lang=en">English</a> <a href="?lang=ko">한국어</a></div>
<h1>sshido 개인정보 처리방침</h1>
<p class="updated">최종 수정일: 2026년 5월 6일</p>

<h2>요약</h2>
<p>sshido는 iOS SSH 터미널입니다. 데이터는 기기에 저장되며, 사용을 추적하거나 데이터를 판매하지 않습니다.</p>

<h2>로컬 저장</h2>
<p>SSH 자격 증명은 iOS 키체인에 암호화되어 저장되며, 기기 잠금이 해제된 상태에서만 접근할 수 있습니다. 호스트 설정, 세션, 환경설정은 앱 샌드박스에 로컬 저장됩니다. 서버에 업로드되지 않습니다.</p>

<h2>푸시 알림 (선택 사항)</h2>
<p>활성화 시 APNs 기기 토큰이 HTTPS로 push.sshido.com에 전송됩니다. 릴레이는 무작위 구독자 ID, 토큰, 알림 횟수만 저장합니다. 자격 증명, 터미널 내용, 개인정보는 저장하지 않습니다. 자체 릴레이 호스팅이 가능합니다.</p>

<h2>충돌 보고</h2>
<p>sshido는 <a href="https://sentry.io">Sentry</a>를 사용하여 충돌 보고서 및 성능 진단을 수집합니다. Sentry는 기기 모델, OS 버전, 스택 트레이스, 브레드크럼 로그를 수신할 수 있습니다. SSH 자격 증명, 터미널 내용 또는 개인 데이터는 충돌 보고서에 포함되지 않습니다. <a href="https://sentry.io/privacy/">Sentry 개인정보 처리방침</a>을 참조하세요.</p>

<h2>SSH 연결</h2>
<p>입력한 명령은 SSH를 통해 원격 서버로 전송됩니다. sshido는 이 트래픽을 가로채거나 기록하지 않습니다.</p>

<h2>데이터 삭제</h2>
<p>앱을 삭제하면 모든 로컬 데이터가 제거됩니다. 푸시 알림 구독을 취소하면 릴레이 데이터가 제거됩니다.</p>

<h2>아동</h2>
<p>13세 미만 아동을 대상으로 하지 않습니다.</p>

<h2>문의</h2>
<p><a href="mailto:{{CONTACT}}">{{CONTACT}}</a></p>
</body>
</html>`
