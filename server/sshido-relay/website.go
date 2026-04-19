package main

import (
	"fmt"
	"net/http"
)

func (s *server) landing(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	fmt.Fprint(w, landingHTML)
}

const landingHTML = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>sshido — SSH terminal for iOS</title>
<meta name="description" content="A fast, private SSH terminal for iPhone and iPad. Voice commands, push notifications, on-device AI.">
<style>
*{margin:0;padding:0;box-sizing:border-box}
:root{
  --bg:#111114;--surface:#1A1A1F;--surface2:#242429;--surface3:#2E2E35;
  --text:#E8E8ED;--text2:#8E8E99;--text3:#5C5C66;
  --accent:#5AC8D6;--accent-hover:#7AD4DF;--accent-muted:rgba(90,200,214,.12);
  --titanium:#7C8290;--spark:#D4A054;
  --radius:12px;--max:720px;
}
html{background:var(--bg);color:var(--text);font-family:-apple-system,BlinkMacSystemFont,'SF Pro','Segoe UI',Roboto,sans-serif;-webkit-font-smoothing:antialiased}
body{overflow-x:hidden}
a{color:var(--accent);text-decoration:none}
a:hover{color:var(--accent-hover)}

/* Hero */
.hero{min-height:85vh;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;padding:60px 24px 40px;position:relative}
.hero::after{content:'';position:absolute;top:0;left:50%;transform:translateX(-50%);width:600px;height:600px;background:radial-gradient(circle,rgba(90,200,214,.06) 0%,transparent 70%);pointer-events:none}
.logo{font-size:3.2em;font-weight:800;letter-spacing:-.03em;margin-bottom:8px}
.logo span{color:var(--accent)}
.tagline{font-size:1.3em;color:var(--text2);max-width:440px;line-height:1.5;margin-bottom:40px}
.cta{display:inline-flex;align-items:center;gap:8px;background:var(--accent);color:#111;font-size:1em;font-weight:600;padding:14px 32px;border-radius:50px;transition:background .2s}
.cta:hover{background:var(--accent-hover);color:#111}
.cta svg{width:20px;height:20px}
.badge{margin-top:16px;color:var(--text3);font-size:.85em}

/* Features */
.features{max-width:var(--max);margin:0 auto;padding:40px 24px 80px;display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:24px}
.feat{background:var(--surface);border:1px solid var(--surface2);border-radius:var(--radius);padding:28px 24px}
.feat-icon{font-size:1.6em;margin-bottom:12px}
.feat h3{font-size:1em;font-weight:600;margin-bottom:6px}
.feat p{color:var(--text2);font-size:.9em;line-height:1.5}

/* Details */
.details{max-width:var(--max);margin:0 auto;padding:0 24px 80px}
.details h2{font-size:1.4em;font-weight:700;margin-bottom:24px;text-align:center;color:var(--text)}
.detail-grid{display:grid;grid-template-columns:1fr 1fr;gap:16px}
.detail{background:var(--surface);border:1px solid var(--surface2);border-radius:var(--radius);padding:20px}
.detail h4{font-size:.85em;color:var(--accent);text-transform:uppercase;letter-spacing:.06em;margin-bottom:6px}
.detail p{color:var(--text2);font-size:.88em;line-height:1.5}
@media(max-width:520px){.detail-grid{grid-template-columns:1fr}}

/* Footer */
footer{border-top:1px solid var(--surface2);max-width:var(--max);margin:0 auto;padding:32px 24px;display:flex;justify-content:space-between;align-items:center;color:var(--text3);font-size:.85em;flex-wrap:wrap;gap:12px}
footer a{color:var(--titanium)}
footer a:hover{color:var(--text)}
</style>
</head>
<body>

<section class="hero">
  <div class="logo"><span>ssh</span>ido</div>
  <p class="tagline">A fast, private SSH terminal for iPhone and iPad.</p>
  <a class="cta" href="https://apps.apple.com/app/sshido/id6746527541">
    <svg viewBox="0 0 24 24" fill="currentColor"><path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.81-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/></svg>
    Download on the App Store
  </a>
  <p class="badge">Requires iOS 17 or later</p>
</section>

<section class="features">
  <div class="feat">
    <div class="feat-icon">&#x1F5A5;</div>
    <h3>SSH &amp; tmux</h3>
    <p>Full terminal with session persistence. Reconnect to running sessions from anywhere.</p>
  </div>
  <div class="feat">
    <div class="feat-icon">&#x1F3A4;</div>
    <h3>Voice mode</h3>
    <p>Hands-free continuous voice input with on-device AI command translation.</p>
  </div>
  <div class="feat">
    <div class="feat-icon">&#x1F514;</div>
    <h3>Push notifications</h3>
    <p>Get notified when long-running tasks finish. Self-hostable relay.</p>
  </div>
  <div class="feat">
    <div class="feat-icon">&#x1F512;</div>
    <h3>Private by design</h3>
    <p>All data on-device. No analytics. No tracking. Keychain-encrypted credentials.</p>
  </div>
</section>

<section class="details">
  <h2>Built for developers</h2>
  <div class="detail-grid">
    <div class="detail">
      <h4>Terminal</h4>
      <p>Metal-rendered terminal with custom font sizing, configurable return key, and full keyboard shortcut bar.</p>
    </div>
    <div class="detail">
      <h4>Auth</h4>
      <p>Ed25519 and RSA keys stored in the iOS Keychain, protected by Face ID. Password auth for quick setups.</p>
    </div>
    <div class="detail">
      <h4>Voice</h4>
      <p>On-device speech recognition (Korean + English). Apple Intelligence translates "go to code folder" into <code>cd code</code>.</p>
    </div>
    <div class="detail">
      <h4>Notifications</h4>
      <p>Claude Code integration sends push alerts when tasks complete. Works over any network with Tailscale.</p>
    </div>
  </div>
</section>

<footer>
  <span>&copy; 2026 sshido</span>
  <span><a href="/privacy">Privacy Policy</a> &middot; <a href="mailto:json9512@gmail.com">Contact</a></span>
</footer>

</body>
</html>`
