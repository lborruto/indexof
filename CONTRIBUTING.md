# Contributing to indexof

Thanks for helping. indexof serves people's files, so the bar is: nothing weaker than today's
checks, no secrets anywhere, and every change tested on the demo data.

Contents: [Set up](#set-up) · [Run it on demo data](#run-it-on-demo-data) · [Checks](#checks) ·
[Principles](#principles) · [Commits and pull requests](#commits-and-pull-requests) ·
[Never commit secrets or real data](#never-commit-secrets-or-real-data) ·
[How it works](#how-it-works) · [Releasing](#releasing).

## Set up

You need Docker with Compose v2, ShellCheck, Node.js 24 and Python 3 (the integration test
checks the zips with it). PowerShell (`pwsh`) is optional: with it, the lint also parses the
Windows VLC Link installer.

    git clone https://github.com/lborruto/indexof.git && cd indexof

There is nothing to install in the repository itself: no build step, no package manager. The
pages are plain HTML and JavaScript, the scripts are POSIX sh, the images are built by Docker.

## Run it on demo data

`tests/make-demo.sh` generates a folder of small videos (several audio tracks, subtitles), music,
pictures and files with awkward names (spaces, accents, quotes, `#`, `?`, `%`, `&`, a symbolic
link, a line break, a name that looks like an option, a folder of 1,500 entries). Nothing in it
is real, so screenshots and bug reports can show it.

    sh tests/make-demo.sh demo
    cp .env.example .env      # set INDEXOF_PASSWORD and INDEXOF_LINK_SECRET (openssl rand -hex 32)

The script runs ffmpeg inside the helper image (`indexof-helper:test` once the integration test
has built it, else the published one is pulled), so there is nothing to install for it.

Then mount the demo folders under `/data` in `compose.yaml` (`./demo/movies:/data/movies:ro`
for a browse-only one, `./demo/pictures:/data/pictures` for a writable one, …) and start it:
`docker compose up --build`, then open
http://127.0.0.1:8099. The README's "Just looking?" section has the shortest form of this.
After a change to the pages or the configuration, `docker compose up --build` again.

## Checks

Run both before opening a pull request. CI runs the same, plus gitleaks over the whole history
and Trivy on both images and the Dockerfiles; all four jobs must be green.

    sh tests/lint.sh          # shellcheck and sh -n on every script, the pages' scripts parsed by node, the Windows installer by pwsh
    sh tests/integration.sh   # builds a throwaway stack on generated demo data and runs every check

The integration test is the project's test suite: login gating, the listing and `/_settings`,
uploads (a cancelled one leaves nothing), zips (valid archives, no symbolic link inside,
option-like names kept as names), search and its filters, folder sizes, signed links (valid,
forged, expired, another file, write methods refused), the remux output, read-only mounts, odd
names everywhere, and the attack inputs (path traversal, hidden files, line breaks, command
injection attempts). It needs Docker, Compose v2 and Python 3, and leaves nothing behind.

## Principles

- **It stays "Index of /".** The listing is nginx's own autoindex, and the pages are plain
  HTML with a little vanilla JavaScript. No framework, no build step, no redesign: a change must
  look like it was always there.
- **Never transcode.** A file is served as it is. The furthest indexof goes is a copy-only
  remux (another container, same streams) for a track the browser cannot switch to.
- **Never weaken a check.** Path confinement (every path a script receives resolves under a
  mounted folder), hidden files denied, symbolic links not followed, no line breaks in names,
  option-like names handled as names, numbers validated, `Content-Security-Policy: sandbox` on
  served files, the helper on an internal network only. A change that needs one of these
  relaxed needs a conversation first.
- **Any folder under `/data`, nothing assumed.** No folder name, host name, user name or
  address is fixed in the code: everything comes from the mounts and the `INDEXOF_*` settings.
- **Every fix comes with a test.** A bug fix adds the check to `tests/integration.sh` that
  fails before the fix and passes after it; a feature adds its checks the same way.
- **Awkward names are normal.** Spaces, accents, quotes, `#`, `?`, `%`, `&`, parentheses: every
  action must work with them or refuse cleanly. The demo data has them for that reason.

## Commits and pull requests

- A subject line that says what changed, in plain words, as in the history: `Any folders under
  /data: read-only mounts browse-only, writable ones editable`. Say why in the body when it is
  not obvious.
- One topic per pull request, with its tests. Fill in the template's checklist.
- Keep `CHANGELOG.md` current: a user-visible change adds a line under `## [Unreleased]`.

## Never commit secrets or real data

- No password, link key, host name, IP address, user name, real folder or file name in code,
  tests, docs, screenshots, logs you paste or commit messages. The demo data is generated;
  screenshots come from it.
- `.env` is gitignored. Keep it so; `.env.example` holds placeholders only.
- The only secrets in the repository are the two invented ones the integration test uses, named
  in `.gitleaks.toml`. CI runs gitleaks over the whole history.
- Found something sensitive in the history? Report it privately (see `SECURITY.md`).

## How it works

- **`web/`**, the `indexof` image: nginx (unprivileged) with the pages (`login.html`,
  `upload.html`, `play.html`) and the site configuration. At start, `50-indexof-mounts.sh`
  looks at every folder mounted under `/data` and writes one route per mount (read-only or
  writable, decided by whether the folder can be written) and a small JSON of settings the pages
  read at `/_settings`. nginx checks the login cookie, serves the "Index of /" listing, takes the
  WebDAV methods for writable folders, verifies the signed links, and proxies `/_space`,
  `/_size`, `/_search`, `/_zip`, `/_probe`, `/_sub`, `/_remux` and `/_vlc` to the helper.
- **`helper/`**, the `indexof-helper` image: Alpine with busybox httpd, `zip` and `ffmpeg`,
  running the CGI shell scripts in `helper/cgi-bin/`. `lib.sh` holds the one path check every
  script uses. It is on an internal network only and never published.
- **`vlc-link/`**: the `vlc://` helpers for Mac (AppleScript app and installer) and Windows
  (PowerShell installer), taking the allowed addresses as arguments.
- **`tests/`**: `lint.sh`, `integration.sh` with its assertions in `lib.sh`, `make-demo.sh` and
  `screenshot.mjs` (the README's screenshots, from the demo data).
- The design and the plan it was built from: `docs/superpowers/`.

## Releasing

1. In `CHANGELOG.md`, rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD` and start a new
   empty `## [Unreleased]` above it.
2. Merge to `main`, then tag: `git tag vX.Y.Z && git push origin vX.Y.Z`.
3. `release.yml` runs CI on the tagged commit, builds both images for `linux/amd64` and
   `linux/arm64`, pushes `X.Y.Z`, `X.Y` and `latest` to GHCR, scans them with Trivy and creates
   the GitHub release from the changelog section. A tag without its section fails on purpose.
