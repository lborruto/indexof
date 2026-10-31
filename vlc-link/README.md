# VLC Link

The files page's `[vlc]` / "open in VLC" open `vlc://` + a temporary link to the file (from
`/_vlc`: that file only, reading only, 12 hours). Browsers do not know `vlc://`, and VLC does
not register it: this small helper does, on each computer, once, and hands VLC the link.
It only opens links to the files page (files.lan, its Tailscale name or 192.168.1.10, port
8099, under `/media/` or `/share/`), so no other website can make VLC open what it likes.

- Mac: `sh mac/install.sh` (puts `VLC Link.app` in `~/Applications`).
- Windows: `powershell -ExecutionPolicy Bypass -File windows\install-vlc-link.ps1` (for the
  account, no administrator; the handler goes in `%LOCALAPPDATA%\vlc-link`).

The first click in Chrome asks to open the helper: tick "Always allow".
Without the helper: the player page's "playlist" (an `.m3u` VLC opens) or "copy VLC link".
