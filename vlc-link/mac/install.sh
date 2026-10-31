#!/bin/sh
# Installs VLC Link in ~/Applications: a small app that opens vlc:// links in VLC. Run once:
#   sh install.sh
set -e
here=$(cd "$(dirname "$0")" && pwd)
app="$HOME/Applications/VLC Link.app"
[ -d /Applications/VLC.app ] || { echo "VLC is not in /Applications: install it first (videolan.org)"; exit 1; }
mkdir -p "$HOME/Applications"
rm -rf "$app"
osacompile -o "$app" "$here/VLC Link.applescript"
plist="$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string io.lborruto.vlc-link" "$plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier io.lborruto.vlc-link" "$plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes array" -c "Add :CFBundleURLTypes:0 dict" -c "Add :CFBundleURLTypes:0:CFBundleURLName string VLC link" -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string vlc" "$plist"
codesign --force --sign - "$app" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
echo "Installed: $app (vlc:// links now open in VLC)"
