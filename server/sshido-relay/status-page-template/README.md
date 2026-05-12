# sshido status page template

Drop these files into a new public GitHub repo (e.g. `sshido-status`) to
stand up a free uptime-monitoring page at `status.sshido.com`.

## What you get

- Probe runs every 5 minutes from GitHub's infrastructure against
  `push.sshido.com/health` and `/subscribe`.
- Auto-generated site at `https://status.sshido.com` (after DNS + Pages
  config, see below).
- Incident auto-opening: any failed probe opens a GitHub issue; any passing
  probe re-closes it. All incident history is public.
- Daily response-time graphs, monthly uptime summaries.
- Costs $0 — runs on GitHub Actions free tier.

## One-time setup

1. `gh repo create <your-github-user>/<your-status-repo> --public`
2. Clone it locally and copy everything from this folder (`.upptimerc.yml`
   and the `.github/workflows/` directory).
3. Update `.upptimerc.yml`:
   - replace `<your-github-user>` with your GitHub username,
   - replace `<your-status-repo>` with your repo name.
4. Push to `main`.
5. On GitHub: **Settings → Pages → Source: `gh-pages` branch, root**.
6. Generate a Personal Access Token with `repo` + `workflow` scopes at
   <https://github.com/settings/tokens>. Add it as repo secret `GH_PAT`.
7. Run the **Uptime CI** workflow manually once — it creates the initial
   state files.
8. DNS: add a CNAME `status.sshido.com` → `<your-github-user>.github.io` (or your
   user's pages domain). Put `status.sshido.com` in a file named `CNAME`
   at the repo root so GitHub Pages associates it.

First green probe takes ~10 minutes. First graph takes 24 hours of data.

## Once it's up

- Cite the status page in every outage tweet / blog post.
- Reference it in the Cloud Pro SLA contract (see the main plan).
- After 3+ months of >= 99.9% recorded uptime, go live with the published
  SLA (step 8 of the monetization plan).
