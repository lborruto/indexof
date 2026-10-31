# Changelog

What changes from one release to the next, in plain words. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/). A tag `vX.Y.Z` publishes the images `X.Y.Z`, `X.Y`
and `latest`; the GitHub release takes its notes from that version's section below.

## [Unreleased]

## [1.4.1] - 2026-10-31

indexof stays straight and simple: nginx's listing plus the few things you reach for every week.

### Removed

- Recent (the link in the bar and `/_recent`, which now answers 404 like any other unknown
  path).
- "inside text files" on the search page: the search finds names, as before 1.3.0 (`text=1` is
  ignored).
- The line under a picture in the viewer (its size, when it was taken, the camera).
- `[link]` on each line: `[scp]` takes its place (below).

### Changed

- The scp line left the upload line: it is now a small grey reminder at the very bottom of a
  writable folder, `scp: scp <your files> user@host:/srv/share/sub/ [copy]`, for the folder you
  are in. None on the home page, the search, a read-only folder or a folder whose path has
  spaces or symbols.
- `[scp]` on every file (with `INDEXOF_SCP` set), read-only folders too: copies the command that
  downloads it into the terminal's folder, `scp 'user@host:/srv/share/Holiday clip.mkv' .`, and
  says it on the page. OpenSSH 9 or later (its scp needs no remote shell); left out for a name
  holding a quote, a backslash, `$`, a backtick, `!`, `*`, `?`, `[` or a control character.

### Added

- The version in the corner of the listings and the viewer, small and grey: "indexof 1.4.1",
  linking to its release ("indexof main" or "indexof dev" for other builds, linking to the
  project). The image takes it as `INDEXOF_VERSION` (a build argument; the release sets it).

### Fixed

- The search's results line up like a folder's listing: a path longer than 50 characters is
  cut as nginx cuts names ("..>", the whole path in the link and its tooltip), accents count as
  one character, and the dates, sizes and links stay in their columns.

## [1.4.0] - 2026-10-31

### Added

- `[link]` on every line of a listing (and of the search and the recent files): copies the
  file's or the folder's whole address, to paste in a message. Whoever opens it logs in first:
  it is not a share link.

### Changed

- A zip over 20 GiB is asked first ("Zip 512G? It downloads as it is made: nothing is stored on
  the server."), a folder's `[zip]` as `[zip selected]`; a folder whose size is still being
  measured after 3 seconds is asked about too. Smaller zips start at once, as before.

## [1.3.0] - 2026-10-31

### Added

- On a phone, the same pages fit the screen: each file in about two lines (the name with a short
  date and the size, then its links, big enough to tap), about 15 files a screen; the search,
  the upload line, the viewer and the login page fit too. On a computer nothing changes.
- Paste to upload: in a writable folder, pasting files (a screenshot, say) uploads them; a
  nameless picture is named for when it was pasted, "Pasted 2026-10-31 18.42.05.png".
- Whole folders upload with their structure, dropped on the page or picked with the new
  "Upload folder" button: folders are created (empty ones too), hidden files left out and
  counted, and you are asked first above 1,000 files.
- Recent: a link in the bar of the home page and every listing, opening `/_recent`: the 50 most
  recently changed files across the mounted folders, newest first, with the same checkboxes,
  links and zip as the search results.
- "inside text files" on the search page: finds the words inside text files (notes, logs,
  subtitles, configuration, code; under 5 MB each) in the chosen folder, ignoring case, matched
  exactly as typed, 200 results at most.
- Under a picture in the viewer: its size in pixels, the file's size and, for a JPEG, when it was
  taken and the camera (from its Exif; never the location).
- Subtitle files next to a video (`Movie.srt`, `Movie.fr.srt`, `.vtt`, `.ass`, `.ssa`) appear in
  the player's subtitle list as "fr (file)" or "file", converted to WebVTT (5 MB at most).

### Changed

- A PDF's name and every `[raw]` (in the listing and in the viewer) open in a new tab, the
  listing or the viewer kept; the viewer's links, `[download]`, folders and `[zip]` stay in the
  same tab.

### Fixed

- The search page's "in:" list showed a blank choice instead of "everywhere" when a folder's
  name held a line break; such names are left out, and "everywhere" is selected when no folder
  is.
- A file whose name holds a backslash had a broken link in the search results (a browser reads
  `\` as `/`); it is now encoded.
- On a computer screen narrower than about 1,300 px, the upload line (with the scp line) made
  the page scroll sideways; it now wraps.

## [1.2.0] - 2026-10-31

### Changed

- A click on a file's name opens it: in the viewer for videos, music, pictures and text files,
  in the browser's own reader for a PDF; anything else (a zip, an ISO…) downloads, as before.
  `[download]` and `[raw]` (the file as the server sends it) are on every file; `[play]` and
  `[view]` are gone, the name does that now.
- The demo data has a `documents` folder with one file of each main kind (the README's listing
  screenshot).

## [1.1.0] - 2026-10-31

### Added

- The home page shows the free space too: once per disk holding a mounted folder.
- Drag and drop: files dropped on a writable folder's page are uploaded as if picked.
- "delete selected" and "move selected" next to "zip selected", when every ticked line can be
  changed.
- The viewer: `[raw]`, `[download]` and `[folder]`; `[← prev]` / `[next →]` and the arrow keys
  through the folder's files of the same kind; **play next** (music and videos go on into the
  next file); resume where you stopped (kept in the browser); text files (notes, logs,
  subtitles, `.nfo`, configuration, code) shown as plain text, with `[view]` in the listing.
- Tests: a browser test of the viewer (`tests/ui-viewer.mjs`); the integration test can run
  twice side by side (`INDEXOF_TEST_PROJECT`, `INDEXOF_TEST_TAG`, `INDEXOF_TEST_CDP_PORT`).

### Fixed

- An `.html` file in a mounted folder was served with the listing's upload line added at its
  end; files are now served exactly as they are.

## [1.0.1] - 2026-10-31

### Fixed

- The upload line (Upload, New folder, the scp line) was hidden at the top of a writable folder,
  which said "read-only folder" instead; its subfolders were fine.

### Added

- A browser test (`tests/ui.mjs`, run by the integration test when Chrome is there) of what the
  page shows: the upload line, "read-only folder", [rename] and [delete] where they belong.

### Changed

- The README presents indexof as what it is first: a file server for the home, media second.

## [1.0.0] - 2026-10-31

The first release: the file page of a private homelab, turned into a project anyone can run.

Security review before release: an independent attack on a running copy (authentication on every
route and method, path traversal and symlink escapes, command injection in every helper parameter,
cross-site scripting from names and media tags, signed-link forgery, WebDAV abuse, container
hardening) found no critical, high or medium issue; its two low findings are fixed below. Trivy
reports no fixable high or critical vulnerability in either image; gitleaks finds no secret in the
history.

### Security

- The two secrets may hold only characters that cannot change the nginx config.
- Request bodies are limited to 1 MB, except uploads into writable folders.
- A zip takes at most 5000 paths.

### Added

- **Login:** one shared password (`INDEXOF_PASSWORD`), a cookie that lasts 30 days, logout.
- **The listing:** nginx's own "Index of /", unchanged in look, with a live filter, a Search
  button (or Enter) to the search page, sort by name, date or size, pages of 100, checkboxes with
  "zip selected", folder sizes filled in automatically and the free space.
- **Search** (`/_search`): text, folder, files or folders, kind, maximum results; the results in
  the listing's own format with date and size.
- **Per line:** `[zip]` on folders, `[play]` / `[vlc]` on video and audio, `[view]` on pictures,
  `[rename]` (rename or move) and `[delete]` in writable folders, never on a mounted folder
  itself.
- **Uploads:** several files, three at a time, a line each with %, time left and `[cancel]`,
  `[cancel all]`, a warning before leaving mid-upload. An upload is finished by a rename from a
  temp folder on the same disk; a cancelled one leaves nothing.
- **An scp line** next to Upload with `[copy]` and `[copy destination]`, shown when
  `INDEXOF_SCP` is set and only for folder paths of plain characters.
- **Zips** streamed as they are made (nothing written on the server), stored, with random names,
  without hidden files or symbolic links; names that look like options are kept as names.
- **Player and viewer** (`/_play`): video, audio, pictures, the file as it is, never converted.
  The audio track Chrome actually plays is shown first; Dolby and DTS tracks are marked "no sound
  here". Another track goes through the browser's own switch when it has one, else through
  `/_remux` (copy-only repackaging: fragmented MP4, Matroska for AC3, E-AC3 and DTS) with the
  player's own play and seek line. Subtitles come from the file's text tracks (`/_sub`); image
  subtitles are listed but disabled.
- **Open in VLC:** `vlc://host:port/path?e=..&k=..` links signed with `INDEXOF_LINK_SECRET`
  (that file only, GET and HEAD only, 12 hours), a `.m3u` playlist and "copy VLC link". The VLC
  Link helpers for Mac (AppleScript app and installer, with a log) and Windows (PowerShell
  installer, per user, no admin) take the allowed addresses as arguments.
- **Any folders under `/data`:** mount what you like. A folder mounted `:ro` is browse-only; a
  writable one allows uploads, new folders, rename, move and delete. A mounted folder itself is
  never renamed, moved or deleted. The routes and the settings are generated at start.
- **Settings instead of fixed values:** `INDEXOF_PASSWORD`, `INDEXOF_LINK_SECRET` (32
  characters or more, never the password; the containers refuse to start without the two),
  `INDEXOF_SCP` and `INDEXOF_SCP_ROOT` (the scp line's destination and the folders' place on
  that host, both checked at start), `INDEXOF_BIND` (`127.0.0.1` by default), `INDEXOF_PORT`
  (`8099`), `PUID` / `PGID`.
- **Security in place:** dotfiles denied, symbolic links not followed, files served with
  `Content-Security-Policy: sandbox` and `X-Content-Type-Options: nosniff`, the helper on an
  internal-only network and never published, every CGI value cut down or checked to be a real
  path under a mounted folder, no line breaks in names, numbers validated, container log limits.
- **Images** `ghcr.io/lborruto/indexof` (nginx unprivileged) and
  `ghcr.io/lborruto/indexof-helper` (Alpine, busybox httpd, zip, ffmpeg) for `linux/amd64` and
  `linux/arm64`, with provenance and SBOM attestations; an example `compose.yaml` and
  `.env.example`.
- **Tests and CI:** `tests/lint.sh` (ShellCheck, `sh -n`, the pages' scripts, the Windows
  installer), `tests/integration.sh` on generated demo data (`tests/make-demo.sh`), gitleaks
  over the whole history, Trivy on both images and the Dockerfiles; Dependabot for the base
  images and the actions.

[Unreleased]: https://github.com/lborruto/indexof/compare/v1.4.1...HEAD
[1.4.1]: https://github.com/lborruto/indexof/compare/v1.4.0...v1.4.1
[1.4.0]: https://github.com/lborruto/indexof/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/lborruto/indexof/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/lborruto/indexof/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/lborruto/indexof/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/lborruto/indexof/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/lborruto/indexof/releases/tag/v1.0.0
