#!/bin/sh
# At start (run by the image's entrypoint, before nginx): the secrets must be there, and the
# folders mounted under /data become the page's routes and settings:
#   /tmp/mounts.conf    one block per folder, included by site.conf inside server {}. A folder
#                       the server can write to (a hidden .uploads folder can be made in it) gets
#                       uploads, new folders, rename/move and delete; one mounted read-only (:ro)
#                       is browse-only. The folder itself is listed but never deleted or moved.
#   /tmp/settings.json  for the pages (/_settings): {"mounts":{"name":"ro"|"rw",...},"scp":...,
#                       "scp_root":...} (the scp line's destination and the folders' place on it)
#   /tmp/indexof-home/  a link to each folder: what the home page lists.
# A folder is refused, with a line in the log, when its name starts with a dot (hidden) or an
# underscore (the page's own routes: /_login, /_search...), or holds a character nginx's config
# could not carry as it is (a double quote, a backslash, a dollar, a control character).
set -eu

[ -n "${INDEXOF_PASSWORD:-}" ] || { echo "indexof: set INDEXOF_PASSWORD (the page's password)" >&2; exit 1; }
secret=${INDEXOF_LINK_SECRET:-}
[ ${#secret} -ge 32 ] || { echo "indexof: set INDEXOF_LINK_SECRET to 32 characters or more (openssl rand -hex 32), never the password" >&2; exit 1; }
[ "$secret" != "$INDEXOF_PASSWORD" ] || { echo "indexof: INDEXOF_LINK_SECRET must not be the password" >&2; exit 1; }

# The scp line's destination, when there is one: user@host or host (letters, digits, . _ - and
# one @: nothing scp, a shell or the settings JSON could read otherwise), and the folder on that
# host holding the mounted folders: an absolute path, /data (the container's own) when unset.
scp=${INDEXOF_SCP:-}
case "$scp" in
  '') ;;
  *[!A-Za-z0-9._@-]*|-*|*@-*|*@*@*|@*|*@) echo "indexof: INDEXOF_SCP must be user@host or host (letters, digits, . _ - and one @): refusing it" >&2; exit 1 ;;
esac
root=${INDEXOF_SCP_ROOT:-/data}
case "$root" in
  [!/]*) echo "indexof: INDEXOF_SCP_ROOT must be an absolute path on the host (/srv/files): refusing it" >&2; exit 1 ;;
  *[\"\\\$\`\']*|*[[:space:]]*) echo "indexof: INDEXOF_SCP_ROOT holds a quote, a backslash, a dollar, a backtick or whitespace: refusing it" >&2; exit 1 ;;
esac
case "$(printf '%s' "$root" | tr -d '\001-\037\177')" in "$root") ;; *) echo "indexof: INDEXOF_SCP_ROOT holds a control character: refusing it" >&2; exit 1 ;; esac
while [ "$root" != "${root%/}" ]; do root=${root%/}; done # (a trailing slash dropped; / itself is empty)

conf=/tmp/mounts.conf
json=/tmp/settings.json
home=/tmp/indexof-home
rm -rf "$home"; mkdir -p "$home"
nl=$(printf '\nx'); nl=${nl%x}

# enc NAME: the name as the page puts it in a link (encodeURIComponent: letters, digits and
# -_.!~*'() as they are, every other byte as %XX). (One byte a line: IFS may be a line break.)
enc() {
  for h in $(printf '%s' "$1" | od -An -tx1 -v | tr -s ' ' '\n'); do
    case "$h" in
      3[0-9]|4[1-9a-f]|5[0-9a]|6[1-9a-f]|7[0-9a]|2d|5f|2e|21|7e|2a|27|28|29) printf '%b' "\\0$(printf '%o' "0x$h")" ;;
      *) printf '%%%s' "$(printf '%s' "$h" | tr 'a-f' 'A-F')" ;;
    esac
  done
}
# jsonstr TEXT: as a JSON string.
jsonstr() { printf '"%s"' "$(printf '%s' "$1" | sed 's/[\\"]/\\&/g')"; }

# The folders: which are there, which are writable. One "mode name" line each.
mounts=
for path in /data/* /data/.*; do
  [ -e "$path" ] || [ -L "$path" ] || continue # (the pattern itself, when nothing matches; a link to nowhere is refused below)
  name=${path#/data/}
  case "$name" in .|..) continue ;; esac
  reason=
  case "$name" in
    .*) reason='its name starts with a dot (hidden)' ;;
    _*) reason='its name starts with an underscore (kept for the page: /_login, /_search...)' ;;
    *[\"\\\$]*) reason='its name holds a double quote, a backslash or a dollar' ;;
  esac
  case "$(printf '%s' "$name" | tr -d '\001-\037\177')" in "$name") ;; *) reason='its name holds a control character' ;; esac
  if [ -z "$reason" ] && [ -L "$path" ]; then reason='it is a symbolic link'; fi
  if [ -z "$reason" ] && [ ! -d "$path" ]; then reason='it is not a folder'; fi
  if [ -n "$reason" ]; then echo "indexof: refused mount /data/$name: $reason" >&2; continue; fi
  # Writable when a hidden .uploads folder (where uploads arrive, on the same disk) can be made.
  if [ -w "$path" ] && mkdir -p "$path/.uploads" 2>/dev/null && [ -w "$path/.uploads" ]; then mode=rw; else mode=ro; fi
  if [ "$mode" = rw ]; then echo "indexof: /data/$name: writable" >&2; else echo "indexof: /data/$name: read-only" >&2; fi
  mounts="$mounts$mode $name$nl"
done
[ -n "$mounts" ] || echo "indexof: no folder mounted under /data (mount some: -v /srv/movies:/data/movies:ro)" >&2

# From here on, one line of $mounts at a time (names may hold spaces, never a line break).
set -f; IFS=$nl

# Where a MOVE may go: into a writable folder (never onto its mount point), and never into or
# onto a hidden name (nginx decodes the header after this check and maps it without matching
# the locations again, so the deny on /. would not see it: .uploads, for one, must stay what
# it is). The pattern matches the Destination header, a link as the page sends it; a read-only
# or a refused folder fails it (nginx itself refuses a .. in it).
rw_alts=
for line in $mounts; do
  [ "${line%% *}" = rw ] || continue
  rw_alts="$rw_alts${rw_alts:+|}$(enc "${line#* }" | sed 's/[.*()]/\\&/g')"
done
move_check="set \$indexof_move_ok 1;
if (\$request_method = MOVE) { set \$indexof_move_ok 0; }
if (\$http_destination ~ \"^(?:https?://[^/]+)?/(?:$rw_alts)/.\") { set \$indexof_move_ok 1; }
# (An encoded slash or backslash, %2f or %5c, is refused too: x%2f.uploads would decode to
# x/.uploads after this check; the page never sends one, a name cannot hold a slash.)
if (\$http_destination ~* \"/(?:\\.|%2e)\") { set \$indexof_move_ok 0; }
if (\$http_destination ~* \"%(?:2f|5c)\") { set \$indexof_move_ok 0; }
if (\$indexof_move_ok = 0) { return 403; }"
indent() { sed "2,\$s/^/$1/"; } # (the lines after the first, which goes where the text is pasted)

# The blocks, the home page's links and the settings.
: >"$conf"
members=
for line in $mounts; do
  mode=${line%% *}; name=${line#* }
  e=$(enc "$name")
  if [ "$mode" = rw ]; then
    files="client_body_temp_path \"/data/$name/.uploads\";
        dav_methods PUT DELETE MOVE;
        create_full_put_path on;
        dav_access user:rw group:r all:r;
        $(printf '%s' "$move_check" | indent '        ')"
    folders="dav_methods MKCOL DELETE MOVE;
    dav_access user:rw group:r all:r;
    $(printf '%s' "$move_check" | indent '    ')"
  else
    files='# (read-only: no uploads, no changes)'
    folders='# (read-only: no new folders, no changes)'
  fi
  cat >>"$conf" <<EOF
# /data/$name ($mode)
location = "/$name" { if (\$indexof_cookie = 0) { return 302 /_login; } return 301 "/$e/"; }
# The folder itself: listed like any folder, but never deleted or moved (it would take all of it).
location = "/$name/" {
    if (\$indexof_cookie = 0) { return 302 /_login; }
    autoindex on;
    autoindex_exact_size off;
    autoindex_localtime on;
    add_after_body /_upload;
    dav_methods off;
}
location ^~ "/$name/" {
    location ~ /\\. { deny all; }
    # Files (downloads, uploads): sandboxed, so an uploaded page cannot run as this site and read
    # the session cookie; a temporary link from /_vlc also opens them (reading only).
    location ~ [^/]\$ {
        if (\$indexof_ok = 0) { return 302 /_login; }
        add_header Content-Security-Policy "sandbox" always;
        add_header X-Content-Type-Options nosniff always;
        $files
    }
    # Folders: the listing, with the line under it.
    if (\$indexof_cookie = 0) { return 302 /_login; }
    autoindex on;
    autoindex_exact_size off;
    autoindex_localtime on;
    add_after_body /_upload;
    $folders
}
EOF
  ln -s "/data/$name" "$home/$name"
  members="$members,$(jsonstr "$name"):\"$mode\""
done
unset IFS; set +f

# The settings: the folders, in the listing's order, the scp destination (user@host) when one
# is set, and the folders' place on that host (for the scp line: root + the page's path).
if [ -n "$scp" ]; then scp=$(jsonstr "$scp"); else scp=null; fi
printf '{"mounts":{%s},"scp":%s,"scp_root":%s}\n' "${members#,}" "$scp" "$(jsonstr "$root")" >"$json"
