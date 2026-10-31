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
