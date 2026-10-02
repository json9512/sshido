package main

import (
	"embed"
	"fmt"
	"net/http"
	"strings"
)

//go:embed site/*.jpg
var siteFiles embed.FS

const appStoreURL = "https://apps.apple.com/app/sshido/id6762311864"

func (s *server) landing(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	page := strings.NewReplacer("{{CONTACT}}", s.cfg.privacyContact, "{{APP_STORE}}", appStoreURL).Replace(landingHTML)
	fmt.Fprint(w, page)
}

func (s *server) siteAsset() http.Handler {
	files := http.FileServerFS(siteFiles)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "public, max-age=86400")
		files.ServeHTTP(w, r)
	})
}

func (s *server) selfHost(w http.ResponseWriter, r *http.Request) {
	url := s.cfg.upstreamRepoURL
	if url == "" {
		url = "/"
	}
	http.Redirect(w, r, url, http.StatusFound)
}

const landingHTML = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>sshido: SSH terminal and agent chat for iPhone and iPad</title>
<meta name="description" content="Run coding agents on your own server and lead them from your phone. An SSH terminal with tmux, an agent chat, and push alerts when an agent needs you.">
<meta name="color-scheme" content="dark">
<style>
*{margin:0;padding:0;box-sizing:border-box}
:root{
  --bg:#111114;--surface:#1A1A1F;--line:#2A2A31;
  --text:#E8E8ED;--text2:#A1A1AB;--text3:#6E6E78;
  --accent:#5AC8D6;--accent-hover:#7AD4DF;
  --sans:-apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI",Roboto,"Helvetica Neue",sans-serif;
  --mono:ui-monospace,"SF Mono",Menlo,Consolas,monospace;
}
html{background:var(--bg);color:var(--text);font-family:var(--sans);font-size:17px;line-height:1.55;-webkit-font-smoothing:antialiased;text-size-adjust:100%}
body{overflow-x:hidden}
a{color:var(--accent);text-decoration:none}
a:hover{color:var(--accent-hover)}
a:focus-visible{outline:2px solid var(--accent);outline-offset:3px;border-radius:6px}
img{display:block;max-width:100%;height:auto}
.wrap{max-width:1080px;margin:0 auto;padding:0 24px}

.top{display:flex;justify-content:space-between;align-items:center;padding:22px 24px;max-width:1080px;margin:0 auto}
.mark{font-weight:800;font-size:1.25rem;letter-spacing:-.02em;color:var(--text)}
.mark:hover{color:var(--text)}
.top nav{display:flex;gap:22px;font-size:.92rem}
.top nav a{color:var(--text2)}
.top nav a:hover{color:var(--text)}

.hero{display:grid;grid-template-columns:1.05fr .95fr;gap:56px;align-items:center;padding-top:48px;padding-bottom:96px}
.hero h1{font-size:clamp(2.3rem,5.2vw,3.9rem);line-height:1.04;letter-spacing:-.035em;font-weight:800;max-width:13ch}
.hero .lede{margin-top:22px;font-size:1.12rem;color:var(--text2);max-width:34em}
.hero .actions{margin-top:34px;display:flex;align-items:center;gap:18px;flex-wrap:wrap}
.cta{display:inline-flex;align-items:center;gap:10px;background:var(--accent);color:#0E1A1C;font-weight:650;padding:14px 26px;border-radius:999px}
.cta:hover{background:var(--accent-hover);color:#0E1A1C}
.cta svg{width:19px;height:19px}
.req{color:var(--text3);font-size:.9rem}
.screen{border-radius:34px;border:1px solid var(--line);overflow:hidden;background:#0D0D10;box-shadow:0 30px 80px -30px rgba(90,200,214,.18)}
.hero .screen{max-width:400px;justify-self:center;-webkit-mask-image:linear-gradient(#000 78%,transparent);mask-image:linear-gradient(#000 78%,transparent);border-bottom:0;border-radius:34px 34px 0 0}

.band{border-top:1px solid var(--line);padding:96px 0}
.split{display:grid;grid-template-columns:1fr 1fr;gap:72px;align-items:center}
.split.flip .copy{order:2}
.split .screen{max-width:330px;justify-self:center}
h2{font-size:clamp(1.7rem,3.2vw,2.35rem);line-height:1.12;letter-spacing:-.025em;font-weight:750;max-width:18ch}
.copy>p{margin-top:16px;color:var(--text2);max-width:32em}
.copy ul{list-style:none;margin-top:26px;display:grid;gap:14px;max-width:32em}
.copy li{padding-left:22px;position:relative;color:var(--text2)}
.copy li::before{content:"";position:absolute;left:0;top:.62em;width:8px;height:8px;border-radius:2px;background:var(--accent)}
.copy li strong{color:var(--text);font-weight:600}

ol.steps{list-style:none;counter-reset:step;margin-top:30px;display:grid;gap:26px;max-width:32em}
ol.steps li{counter-increment:step;display:grid;grid-template-columns:44px 1fr;gap:4px 14px;padding:0}
ol.steps li::before{content:counter(step);position:static;grid-row:span 2;width:34px;height:34px;border-radius:50%;border:1.5px solid var(--accent);background:none;color:var(--accent);font-weight:700;display:grid;place-items:center;font-size:.95rem}
ol.steps strong{font-weight:650;color:var(--text)}
ol.steps span{color:var(--text2)}

.harnesses{margin-top:26px;display:flex;flex-wrap:wrap;gap:10px}
.harnesses span{border:1px solid var(--line);border-radius:999px;padding:6px 14px;font-size:.9rem;color:var(--text)}
.note{margin-top:22px;font-size:.95rem;color:var(--text2);max-width:32em}

.prompt{font-family:var(--mono);font-size:.9rem;color:var(--text2);margin-top:22px}
.prompt b{color:var(--accent);font-weight:500}

.private{display:grid;grid-template-columns:1fr 1.3fr;gap:72px}
.private dl{display:grid;gap:22px}
.private dt{font-weight:650}
.private dd{color:var(--text2);margin-top:4px}
.private .links{margin-top:26px;display:flex;gap:22px;flex-wrap:wrap;font-size:.95rem}

.closing{text-align:center;padding-top:104px;padding-bottom:112px;border-top:1px solid var(--line)}
.closing h2{margin:0 auto;max-width:22ch}
.closing .cta{margin-top:30px}

footer{border-top:1px solid var(--line);padding:28px 0 40px;color:var(--text3);font-size:.88rem}
footer .wrap{display:flex;justify-content:space-between;gap:16px;flex-wrap:wrap}
footer nav{display:flex;gap:20px}
footer a{color:var(--text2)}
footer a:hover{color:var(--text)}

@media (prefers-reduced-motion:no-preference){
  .hero .screen{animation:rise .9s cubic-bezier(.2,.7,.2,1) both}
  @keyframes rise{from{opacity:0;transform:translateY(28px)}to{opacity:1;transform:none}}
}
@media (max-width:860px){
  .hero,.split,.private{grid-template-columns:1fr;gap:44px}
  .split.flip .copy{order:0}
  .hero{padding-top:24px;padding-bottom:72px}
  .hero .screen{max-width:340px}
  .band{padding:72px 0}
  .top nav a.hide-sm{display:none}
}
</style>
</head>
<body>

<header class="top">
  <a class="mark" href="/">sshido</a>
  <nav aria-label="Site">
    <a class="hide-sm" href="#agents">Agents</a>
    <a class="hide-sm" href="#terminal">Terminal</a>
    <a href="/privacy">Privacy</a>
    <a href="https://github.com/json9512/sshido">Source</a>
  </nav>
</header>

<main>
<section class="wrap hero">
  <div>
    <h1>Run coding agents on your own server. Lead them from your phone.</h1>
    <p class="lede">sshido is an SSH terminal for iPhone and iPad with an agent chat built in. Ask once: an orchestrator plans the work, runs subagents in Podman on your host, and checks their evidence before it answers.</p>
    <div class="actions">
      <a class="cta" href="{{APP_STORE}}">
        <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.81-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/></svg>
        Download on the App Store
      </a>
      <span class="req">For iPhone and iPad, iOS 17 or later</span>
    </div>
  </div>
  <img class="screen" src="/site/chat.jpg" width="660" height="860" alt="An agent chat in sshido: the person asks whether sshido.com is up, and the orchestrator starts two subagents in parallel, one for a TLS check and one for a phone-sized screenshot.">
</section>

<section class="band" id="agents">
  <div class="wrap split">
    <div class="copy">
      <h2>One request, a team of agents, answers you can check.</h2>
      <ol class="steps">
        <li><strong>You ask.</strong><span>Type what you need into a chat, from anywhere you have signal.</span></li>
        <li><strong>The orchestrator plans.</strong><span>It writes down the goal and starts subagents for work that takes time or can run in parallel.</span></li>
        <li><strong>Every agent shows its work.</strong><span>Each one keeps a work record with its goal, evidence, and a pass or fail verdict.</span></li>
        <li><strong>The answer arrives with proof.</strong><span>Screenshots, files and results land in the chat, and a push tells you it is done.</span></li>
      </ol>
    </div>
    <img class="screen" src="/site/record.jpg" width="660" height="1434" loading="lazy" alt="An agent's work record: its task, the goal it set, its verification against sshido.com's certificate, and a pass verdict.">
  </div>
</section>

<section class="band">
  <div class="wrap split flip">
    <div class="copy">
      <h2>Bring the models you already pay for.</h2>
      <p>Agents run the same command-line tools you use at your desk, signed in with your own subscriptions, or a model you host yourself. sshido never sits between you and the model.</p>
      <div class="harnesses"><span>Claude Code</span><span>Codex</span><span>Gemini CLI</span><span>Grok</span><span>Your local model</span></div>
      <p class="note">On a Linux host, Claude agents use that host's own Claude Code setup, so its connectors, plugins and MCP servers come along. Agents can also browse the web, use a desktop you can watch, and read host folders you share.</p>
    </div>
    <img class="screen" src="/site/models.jpg" width="660" height="1434" loading="lazy" alt="Agent settings in sshido: a local model for the orchestrator, and Claude Code plus a local model turned on for subagents.">
  </div>
</section>

<section class="band" id="terminal">
  <div class="wrap split">
    <div class="copy">
      <h2>A real terminal when you want the keyboard.</h2>
      <ul>
        <li><strong>Full xterm-256color, drawn with Metal,</strong> so heavy output scrolls smoothly.</li>
        <li><strong>tmux sessions that outlive the app.</strong> Reconnects, network switches and app switches pick up where you left off.</li>
        <li><strong>A shortcut bar you can arrange,</strong> smart copy of links and output, and sign-in links that open with their port forwarded.</li>
      </ul>
      <p class="prompt"><b>$</b> works with any server you reach over SSH</p>
    </div>
    <img class="screen" src="/site/terminal.jpg" width="660" height="1310" loading="lazy" alt="A tmux session in the sshido terminal showing a git log.">
  </div>
</section>

<section class="band">
  <div class="wrap split flip">
    <div class="copy">
      <h2>Put the phone down. It will tell you when an agent needs you.</h2>
      <p>A push arrives the moment an agent finishes or waits for your input, and hosts turn amber while Claude is waiting. Alerts go through a small relay at push.sshido.com. Its source is public, so you can check that it keeps only what it needs to reach your phone and never the alert text.</p>
      <p class="note"><a href="https://github.com/json9512/sshido/tree/main/server/sshido-relay">Read the relay's source</a></p>
    </div>
    <img class="screen" src="/site/notifications.jpg" width="660" height="1434" loading="lazy" alt="Notification settings in sshido: notifications on, subscribed to the push.sshido.com relay, and a choice of haptics.">
  </div>
</section>

<section class="band">
  <div class="wrap private">
    <div class="copy">
      <h2>Your keys and your code stay between you and your server.</h2>
      <div class="links"><a href="/privacy">Privacy policy</a><a href="https://github.com/json9512/sshido">Source code</a></div>
    </div>
    <dl>
      <div><dt>Keys in the Keychain</dt><dd>Ed25519 and RSA keys are stored in the iOS Keychain and readable only while your device is unlocked. A server's host key is remembered on first connect and checked every time after.</dd></div>
      <div><dt>Agents run on your host</dt><dd>Chats, agents and their files live on your server. Prompts go from your host to the model provider you chose, never through sshido.</dd></div>
      <div><dt>What leaves your phone</dt><dd>Terminal content and keys travel only to your server. Push text passes through the relay to Apple and is not stored. Crash reports leave out terminal content and credentials, and you can turn them off.</dd></div>
    </dl>
  </div>
</section>

<section class="closing">
  <div class="wrap">
  <h2>Your server is already doing the work. Now you can follow it from anywhere.</h2>
  <a class="cta" href="{{APP_STORE}}">Download on the App Store</a>
  </div>
</section>
</main>

<footer>
  <div class="wrap">
    <span>&copy; 2026 sshido</span>
    <nav aria-label="Footer"><a href="/privacy">Privacy policy</a><a href="https://github.com/json9512/sshido">Source code</a><a href="mailto:{{CONTACT}}">Contact</a></nav>
  </div>
</footer>

</body>
</html>`
