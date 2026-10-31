# VLC Link

The page's `[vlc]` / "open in VLC" open `vlc://` + a temporary link to the file (from `/_vlc`:
that file only, reading only, 12 hours). Browsers do not know `vlc://`, and VLC does not
register it: this small helper does, on each computer, once, and hands VLC the link.

It only opens links to the page itself: the addresses you give the installer, as they are in
the browser's address bar (`host:port`, a name or an IPv4 address; one for each way you reach
the page, say `files.example:8099` at home and `10.0.0.5:8099` elsewhere), and only under a
folder of the page (`/<folder>/...`), so no other website can make VLC open what it likes. Run
the installer again to change the list.

- Mac: `sh mac/install.sh files.example:8099 10.0.0.5:8099` (puts `VLC Link.app` in
  `~/Applications`; what it did with each link is in `~/Library/Logs/VLC-Link.log`).
- Windows: `powershell -ExecutionPolicy Bypass -File windows\install-vlc-link.ps1 -Allowed files.example:8099,10.0.0.5:8099`
  (for the account, no administrator; the handler goes in `%LOCALAPPDATA%\vlc-link`).

The first click in Chrome asks to open the helper: tick "Always allow".
Without the helper: the player page's "playlist" (an `.m3u` VLC opens) or "copy VLC link".
