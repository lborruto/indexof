# indexof — notes for Claude

A plain file server for a home network: nginx's own "Index of /" listing for the folders mounted
under `/data`, plus login, uploads, rename/move/delete, search, zips, folder sizes, a player with
subtitle and audio tracks, and signed VLC links. Two small containers: `indexof` (`web/`, nginx
unprivileged, the pages and the site config) and `indexof-helper` (`helper/`, busybox httpd
running POSIX sh CGI scripts with `zip` and `ffmpeg`), on an internal Docker network.

No framework, no build step, no package manager: plain HTML with a little vanilla JavaScript,
POSIX sh, two Dockerfiles. `README.md` is for users, `CONTRIBUTING.md` holds the principles and
how it works, `SECURITY.md` the security model. The repository is public.

## Permanent rules

- Commit as `luca.borruto@gmail.com` (the local git config), never the work address.
- Never push `main` without the owner's go-ahead: branch, pull request, "CI result" green, the
  owner merges. Ask before tagging a release.
- No password, link key, host name, IP address, user name, real folder or file name in code,
  tests, docs, screenshots or commit messages. Screenshots come from the generated demo data
  (`tests/make-demo.sh`), never a real install. `.env` stays ignored; `.env.example` holds
  placeholders only.
- It stays "Index of /": the listing is nginx's autoindex, the pages plain HTML and vanilla
  JavaScript. No framework, no build step, no redesign. A new feature is small and fits that.
- Never transcode. The furthest it goes is a copy-only remux (`/_remux`).
- Never weaken a check: path confinement (`allowed_path` in `helper/cgi-bin/lib.sh`, the one
  path check every CGI script uses), dotfiles denied, symbolic links not followed (and left out
  of zips), no line breaks in names, option-like names handled as names, numbers validated,
  `Content-Security-Policy: sandbox` and `nosniff` on served files, the helper on the internal
  network only and never published. Relaxing one needs a conversation (an issue) first.
- Nothing fixed in the code: no folder name, host or user. Everything comes from the mounts and
  the `INDEXOF_*` settings (`tests/lint.sh` greps `web/`, `helper/`, `vlc-link/` for it).
  The owner's own values (host, addresses, tailnet, user) are never written in a tracked file,
  the lint included: they live in the git-ignored `.private-values` (format in
  `.private-values.example`) or `INDEXOF_PRIVATE_VALUES`; without either (CI) the lint skips
  that part and keeps its generic patterns (`*.ts.net`, `/Users/…`, `/home/…`).
- Every fix comes with a check in `tests/integration.sh` that fails before it; a feature adds its
  checks the same way.
- `compose.yaml` and `.env.example` agree: every variable the one uses is in the other (lint
  checks it).
- A user-visible change adds a line under `## [Unreleased]` in `CHANGELOG.md`. A pull request that
  changes what README.md or CLAUDE.md says updates them in the same pull request.

## Layout

| Path | Role |
| --- | --- |
| `web/Dockerfile` | `indexof` image: nginx-unprivileged (pinned digest), `INDEXOF_VERSION` build arg shown in the pages' corner. |
| `web/50-indexof-mounts.sh` | At start: refuses to run without the two secrets, turns each folder under `/data` into a route (writable or browse-only, decided by whether it can be written), writes `/tmp/settings.json` (`/_settings`). |
| `web/site.conf.template`, `web/nginx.conf` | Login cookie check, autoindex, WebDAV methods on writable folders, signed-link verification, proxy of `/_space`, `/_size`, `/_search`, `/_zip`, `/_probe`, `/_sub`, `/_remux`, `/_vlc` to the helper. |
| `web/pages/` | `login.html`, `upload.html` (the listing's additions), `play.html` (the player). |
| `helper/Dockerfile`, `helper/start.sh` | `indexof-helper` image: Alpine, busybox httpd, `zip`, `ffmpeg`. |
| `helper/cgi-bin/` | One POSIX sh script per route; `lib.sh` is sourced, not executable. Indented with two spaces. |
| `vlc-link/` | `vlc://` handlers: Mac (AppleScript app and installer), Windows (PowerShell installer). They take the allowed `host:port` origins as arguments and refuse anything else. |
| `tests/lint.sh` | ShellCheck and `sh -n` on every script, each page's `<script>` parsed by node, the Windows installer parsed by pwsh, the installers' refusals, no fixed hosts in the code, compose ↔ `.env.example`. |
| `tests/integration.sh`, `tests/lib.sh` | The test suite: a throwaway compose stack (`indexof-test`, `127.0.0.1:18099`) on demo data, every route and attack input. Invented secrets `Test123pw` and a hex link key, allow-listed in `.gitleaks.toml`. |
| `tests/make-demo.sh` | Generated demo data (media with tracks, awkward names, 1,500-entry folder). |
| `tests/screenshot.mjs` | README screenshots over CDP from a running demo install; PNGs are ignored, commit the `.webp`. |
| `compose.yaml`, `.env.example` | The example deployment: published on `127.0.0.1` unless `INDEXOF_BIND` says otherwise. |

## Build and test

```bash
sh tests/lint.sh          # ShellCheck, Node 24; pwsh optional
sh tests/integration.sh   # Docker with Compose v2, Python 3
actionlint                # after any workflow change
```

CI (`.github/workflows/ci.yml`): Changed files, Lint, Secrets (gitleaks over the whole history),
Integration, Scan (Trivy on both images and the config files), then **CI result**, the one check
the ruleset requires. Docs-only pull requests skip Integration and Scan. `codeql.yml` scans the
JavaScript and the workflows. `release.yml`: a push to `main` publishes the `main` image tags; a
tag `vX.Y.Z` on main runs CI, builds both images for amd64 and arm64 (provenance, SBOM), scans the
pushed digests with Trivy and creates the GitHub release from the CHANGELOG section.

## Known traps

- The CGI scripts run under busybox `sh`, not bash: ShellCheck runs with `-s sh`.
- A folder mounted `:ro` is browse-only because nginx refuses the write methods on it, and the
  kernel refuses writes anyway; the mount script decides by trying to create `.uploads`.
- Folder names starting with `.` or `_` are refused at start (`_` is the page's own routes), as
  are names nginx's config could not carry (double quote, backslash, dollar, control characters).
- The two secrets go into the nginx config as they are: only `A-Za-z0-9._~+/=-` are accepted.
- The login cookie holds the password itself and is not `HttpOnly` (the pages read it): an
  injected script in the pages would expose it. Served files are sandboxed for that reason.
- Every action is pinned to a full commit SHA of a release at least 14 days old, with a
  `# vX.Y.Z (date)` comment; Dependabot (14-day cooldown) moves them.

## Tasks

✅ done · 🔄 in progress · ⏳ to do

| # | Task | Status |
| --- | --- | --- |
| 1 | Template gaps: CLAUDE.md, CodeQL, single "CI result" check, release only from main | 🔄 |
| 2 | Switch the "Protect main" ruleset to require "CI result" once it has run | ⏳ |
