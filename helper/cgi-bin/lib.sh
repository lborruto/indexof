#!/bin/sh
# Shared by the scripts here, which source it (. "$(dirname "$0")/lib.sh": busybox httpd runs
# them from this folder). Not a script of its own: not executable, so httpd never runs it.
#
# allowed_path PATH: PATH, a path of the page (/folder/...), as the real file or folder under
# /data it names, printed. Nothing (and 1) unless it is in a mounted folder (/data/<folder>/...,
# or that folder itself; never /data, never a folder whose name starts with a dot or an
# underscore, which the page refuses too), has no hidden part, holds no line break and exists.
# Symbolic links are resolved first (realpath), so one pointing outside is refused like any
# other path outside.
allowed_path() {
  nl=$(printf '\nx'); nl=${nl%x}
  case "$1" in *"$nl"*) return 1 ;; esac
  d=$(realpath "/data/${1#/}" 2>/dev/null) || return 1
  case "$d" in /data/[!._]*) ;; *) return 1 ;; esac
  case "$d" in */.*) return 1 ;; esac
  [ -e "$d" ] || return 1
  printf '%s\n' "$d"
}

# esc: its input with & < > " as HTML's entities (a name, in a page).
esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }

# listing MAX: the paths on its input (under /data, one a line), at most MAX, as nginx lists them
# (link, date, size), in the <pre id="list"> the page's script finds (the search's results, the
# recent files).
listing() {
  echo "<pre id=\"list\" data-max=\"$1\">"
  head -n "$1" | while IFS= read -r f; do [ -n "$f" ] && stat -c '%F|%s|%Y|%n' "$f"; done | awk -F'|' '
    BEGIN { for (i = 0; i < 256; i++) ord[sprintf("%c", i)] = i }
    function enc(s,  r, i, c) { r = ""; for (i = 1; i <= length(s); i++) { c = substr(s, i, 1); r = r (c ~ "^[A-Za-z0-9/._~-]$" ? c : sprintf("%%%02X", ord[c])) } return r }
    function esc(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); gsub(/"/, "\\&quot;", s); return s }
    function human(n,  i) { if (n < 1024) return n; for (i = 0; n >= 1024 && i < 4; i++) n /= 1024; return int(n + 0.5) substr("KMGT", i, 1) }
    { path = substr($0, length($1 $2 $3) + 10); dir = $1 == "directory"; if (dir) path = path "/"
      pad = 51 - length(path); if (pad < 1) pad = 1
      printf "<a href=\"/%s\">%s</a>%" pad "s%s %8s\n", enc(path), esc(path), "", strftime("%d-%b-%Y %H:%M", $3), dir ? "-" : human($2) }'
  echo "</pre><hr>"
}
