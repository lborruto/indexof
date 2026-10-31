#!/bin/sh
# Installs VLC Link in ~/Applications: a small app that opens the page's vlc:// links (the [vlc]
# next to a video, "open in VLC" in the player) in VLC. Give it the page's addresses as they are
# in the browser's address bar (host:port), one or more; only links to those are opened:
#   sh install.sh files.example:8099 10.0.0.5:8099
# Run it again to change the list. What it did with each link: ~/Library/Logs/VLC-Link.log.
set -e
usage() { echo "usage: sh install.sh <host:port> [<host:port>...]   (the page's addresses, as in the browser's address bar)" >&2; exit 2; }
[ $# -gt 0 ] || usage
# An address: a host name or IPv4 address (letters, digits, dots, dashes, starting with a letter
# or a digit) and a port. Nothing else gets into the app's list (an AppleScript text, which
# these characters cannot break).
origin_ok() {
  case "$1" in *:*) ;; *) return 1 ;; esac
  host=${1%:*}; port=${1##*:}
  [ -n "$host" ] && [ -n "$port" ] || return 1
  case "$host" in *[!A-Za-z0-9.-]*|[.-]*) return 1 ;; esac
  case "$port" in *[!0-9]*) return 1 ;; esac
  [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}
list=
for o in "$@"; do
  origin_ok "$o" || { printf "install.sh: not an origin (host:port, with letters, digits, dots and dashes): '%s'\n" "$o" >&2; exit 1; }
  list="$list${list:+, }\"vlc://$o/\""
done
[ -d /Applications/VLC.app ] || { echo "VLC is not in /Applications: install it first (videolan.org)" >&2; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
app="$HOME/Applications/VLC Link.app"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# The script with the addresses in its (empty) list, compiled into the app.
sed "s|^\([[:space:]]*\)set allowed to {}.*|\1set allowed to {$list}|" "$here/VLC Link.applescript" >"$tmp/VLC Link.applescript"
grep -qF -- "set allowed to {$list}" "$tmp/VLC Link.applescript" || { echo "install.sh: could not put the addresses into the script" >&2; exit 1; }
mkdir -p "$HOME/Applications"
rm -rf "$app"
osacompile -o "$app" "$tmp/VLC Link.applescript"
plist="$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string io.lborruto.vlc-link" "$plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier io.lborruto.vlc-link" "$plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes array" -c "Add :CFBundleURLTypes:0 dict" -c "Add :CFBundleURLTypes:0:CFBundleURLName string VLC link" -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string vlc" "$plist"
codesign --force --sign - "$app" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
echo "Installed: $app (vlc:// links to $* now open in VLC)"
