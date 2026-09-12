# holler — PUBLIC site repo

This repo is public (`t0mj/holler`). Only public-safe content belongs here: the Hugo site
(`hugo.toml`, `layouts/`, `static/`, `archetypes/`, `content/`, the deploy workflow).

- No working docs, no IDEAS/sources/writer-test material, no drafts, no fleet details beyond
  what the published posts already say, no internal IPs, no client/proprietary names, no
  personal info, no session UUIDs.
- Content arrives one way only: the working repo (`~/dev/holler`, private `t0mj/holler-work`)
  → `scripts/publish-site.sh` (sanitizes per its rules + filters to live posts, `draft: false`)
  → this repo.
- `scripts/leak-check.sh` is the pre-push tripwire; its string list is local-only
  (`.git/info/leak-strings.txt`, untracked — a list of strings you must never publish must
  never itself be published). Run it before any commit: `scripts/leak-check.sh`.
- Commit identity in this repo is the public handle + GitHub noreply email — never a personal
  address (metadata is a public surface).
- Site: https://t0mj.github.io/holler/
