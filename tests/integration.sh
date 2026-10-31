#!/bin/sh
# Integration test: builds both images, brings up a throwaway stack (compose project
# indexof-test, published on 127.0.0.1:18099 only) on the demo data (tests/make-demo.sh: real
# media and awkward names) plus a few folders made here, runs every check, and takes everything
# down again (also on failure). Needs docker (with compose v2), curl, python3 (to validate zips
# and sign links) and node (the pages' logic); ffprobe runs in the helper image. Exits non-zero
# on the first failed check, printing ok/FAIL lines.
#   sh tests/integration.sh
set -u
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh

PORT=${INDEXOF_TEST_PORT:-18099}
BASE="http://127.0.0.1:$PORT"
PASSWORD=Test123pw
SECRET=0123456789abcdef0123456789abcdef
COOKIE="session=$PASSWORD"
PROJECT=${INDEXOF_TEST_PROJECT:-indexof-test}
TAG=${INDEXOF_TEST_TAG:-test}           # the images built here (indexof:$TAG, indexof-helper:$TAG)
CDP_PORT=${INDEXOF_TEST_CDP_PORT:-9333} # the browser test's Chrome
RO_PORT=$((PORT + 1)) # (a second page, every folder read-only, at the end)

# Everything made here goes under one temporary folder, removed at the end whatever happens.
TMP=$(mktemp -d "${TMPDIR:-/tmp}/indexof-test.XXXXXX") || exit 1
BODY=$TMP/body
DATA=$TMP/data
compose() { docker compose -p "$PROJECT" --env-file "$TMP/test.env" -f compose.yaml -f "$TMP/override.yaml" "$@"; }
cleaned=
cleanup() {
  [ -n "$cleaned" ] && return; cleaned=1
  echo "cleaning up"
  [ -f "$TMP/override.yaml" ] && compose down -v --remove-orphans >/dev/null 2>&1
  docker rm -f "$PROJECT-ro" >/dev/null 2>&1
  rm -rf "$TMP"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

# The fixture: the demo data (movies and music mounted read-only; pictures and share writable),
# "My Stuff" and a writable folder with an accent, parentheses, an ampersand, an apostrophe and a
# hash in its name, plus _search and .hidden, which the server must refuse; a dangling symbolic
# link and a plain file, refused too (seen only when the whole fixture is scanned, below). The
# demo data itself is made once the helper image is built (ffmpeg runs in it).
ODD="Amélie (2001) & co's #1"
ODD_E="Am%C3%A9lie%20(2001)%20%26%20co's%20%231" # (as the page encodes it: encodeURIComponent)
MKV='/movies/Big%20Buck%20Test%20(2024)/Big%20Buck%20Test%20(2024).mkv'
MKV_FILE="$DATA/movies/Big Buck Test (2024)/Big Buck Test (2024).mkv"
MKV2="/movies/Am%C3%A9lie%20(2001)/L'Amour%20%26%20%231%3F.mkv" # (the same file behind an odd name)
MP4='/movies/Short%20(2023).mp4'
mkdir -p "$DATA/share/pat" "$DATA/My Stuff/subs" "$DATA/$ODD" "$DATA/_search" "$DATA/.hidden" || exit 1
echo 'hidden' >"$DATA/_search/secret.txt"
echo 'hidden' >"$DATA/.hidden/secret.txt"
: >"$DATA/share/pat/*"; : >"$DATA/share/pat/[ab].txt"; : >"$DATA/share/pat/a.txt"; : >"$DATA/share/pat/b.txt"
printf '1\n00:00:01,000 --> 00:00:02,000\nA subtitle file.\n' >"$DATA/My Stuff/subs/Big Buck Test (2024).srt"
# The player's text view (tests/ui-viewer.mjs): plain text, a page (shown as its source), an old
# .nfo in Windows-1252 (é as the one byte E9, not UTF-8) and a log of more than 1 MiB.
mkdir -p "$DATA/My Stuff/text" || exit 1
printf 'Plain text for the viewer.\n' >"$DATA/My Stuff/text/readme.txt"
printf '<html><body><b>shown as source</b></body></html>\n' >"$DATA/My Stuff/text/page.html"
printf 'a backslash in the name\n' >"$DATA/My Stuff/subs/back\\slash.txt"
printf 'Caf\351 cr\350me\n' >"$DATA/My Stuff/text/old.nfo"
awk 'BEGIN { for (i = 1; i <= 30000; i++) printf "line %05d of a log longer than one mebibyte\n", i }' >"$DATA/My Stuff/text/big.log"
ln -s /nowhere "$DATA/dangling"
echo 'x' >"$DATA/file.txt"
head -c 30000000 /dev/zero >"$TMP/big.bin"
echo 'hello' >"$TMP/hello.txt"
nl=$(printf '\nx'); nl=${nl%x}
ctl=$(printf '\001')

# The stack: the example compose.yaml as it is, with an .env of test values (the secrets, the
# test port, the current user as PUID/PGID so it can write into the fixture, an scp
# destination) and an override for the images built here and the fixture's folders: movies and
# music mounted read-only, the other folders writable for the page; everything read-only for
# the helper.
cat >"$TMP/test.env" <<EOF
INDEXOF_PASSWORD=$PASSWORD
INDEXOF_LINK_SECRET=$SECRET
INDEXOF_BIND=127.0.0.1
INDEXOF_PORT=$PORT
PUID=$(id -u)
PGID=$(id -g)
INDEXOF_SCP=me@nas.example
INDEXOF_SCP_ROOT=/srv/files/
EOF
web_volumes=; helper_volumes=
for m in movies music pictures share 'My Stuff' "$ODD" _search .hidden; do
  ro=; case "$m" in movies|music) ro=:ro ;; esac
  web_volumes="$web_volumes      - \"$DATA/$m:/data/$m$ro\"
"
  helper_volumes="$helper_volumes      - \"$DATA/$m:/data/$m:ro\"
"
done
cat >"$TMP/override.yaml" <<EOF
services:
  indexof:
    image: indexof:$TAG
    volumes: !override
$web_volumes  indexof-helper:
    image: indexof-helper:$TAG
    volumes: !override
$helper_volumes
EOF

# The example compose.yaml: it refuses to run without each of the two secrets, and with them
# (nothing else set) it publishes the page on 127.0.0.1:8099 only, as 1000:1000, the helper on
# the internal network alone, without the password, both with log limits.
: >"$TMP/empty.env"
if env -u INDEXOF_PASSWORD -u INDEXOF_LINK_SECRET docker compose --env-file "$TMP/empty.env" -f compose.yaml config >"$BODY" 2>&1; then fail 'compose.yaml ran without the secrets'; fi
# (compose names the first missing variable it meets, in no fixed order: either one here)
if grep -Eq 'INDEXOF_PASSWORD|INDEXOF_LINK_SECRET' "$BODY"; then ok "compose.yaml refuses to run without the secrets, naming $(grep -Eo 'INDEXOF_PASSWORD|INDEXOF_LINK_SECRET' "$BODY" | head -n 1)"; else fail "compose.yaml without the secrets: $(cat "$BODY")"; fi
printf 'INDEXOF_PASSWORD=%s\n' "$PASSWORD" >"$TMP/half.env"
if env -u INDEXOF_LINK_SECRET docker compose --env-file "$TMP/half.env" -f compose.yaml config >"$BODY" 2>&1; then fail 'compose.yaml ran without INDEXOF_LINK_SECRET'; fi
if grep -q INDEXOF_LINK_SECRET "$BODY"; then ok 'compose.yaml refuses to run without INDEXOF_LINK_SECRET'; else fail "compose.yaml without the link secret: $(cat "$BODY")"; fi
printf 'INDEXOF_LINK_SECRET=%s\n' "$SECRET" >"$TMP/half2.env"
if env -u INDEXOF_PASSWORD docker compose --env-file "$TMP/half2.env" -f compose.yaml config >"$BODY" 2>&1; then fail 'compose.yaml ran without INDEXOF_PASSWORD'; fi
if grep -q INDEXOF_PASSWORD "$BODY"; then ok 'compose.yaml refuses to run without INDEXOF_PASSWORD'; else fail "compose.yaml without the password: $(cat "$BODY")"; fi
printf 'INDEXOF_PASSWORD=%s\nINDEXOF_LINK_SECRET=%s\n' "$PASSWORD" "$SECRET" >"$TMP/both.env"
if env -u INDEXOF_BIND -u INDEXOF_PORT -u PUID -u PGID -u INDEXOF_SCP -u INDEXOF_SCP_ROOT docker compose --env-file "$TMP/both.env" -f compose.yaml config --format json >"$BODY" 2>"$TMP/err"; then ok 'compose.yaml runs with the two secrets'; else fail "compose.yaml with the two secrets: $(cat "$TMP/err")"; fi
if python3 -I -c '
import json, sys
c = json.load(open(sys.argv[1])); s = c["services"]; w = s["indexof"]; h = s["indexof-helper"]
def want(cond, what):
    if not cond: sys.exit(what)
want(w["image"].startswith("ghcr.io/lborruto/indexof:") and h["image"].startswith("ghcr.io/lborruto/indexof-helper:"), "images: %s, %s" % (w["image"], h["image"]))
p = w["ports"]
want(len(p) == 1 and p[0]["host_ip"] == "127.0.0.1" and p[0]["published"] == "8099" and p[0]["target"] == 8080, "page ports: %r" % p)
want("ports" not in h, "the helper publishes a port: %r" % h.get("ports"))
want(sorted(w["networks"]) == ["default", "indexof"] and list(h["networks"]) == ["indexof"], "networks: %r, %r" % (w["networks"], h["networks"]))
want(c["networks"]["indexof"].get("internal") is True, "the indexof network is not internal")
want(w["user"] == "1000:1000" and h["user"] == "1000:1000", "users: %s, %s" % (w["user"], h["user"]))
want(w["environment"]["INDEXOF_PASSWORD"] == sys.argv[2] and w["environment"]["INDEXOF_LINK_SECRET"] == sys.argv[3], "the page misses a secret")
want(h["environment"]["INDEXOF_LINK_SECRET"] == sys.argv[3] and "INDEXOF_PASSWORD" not in h["environment"], "the helper: the link secret only")
for x in (w, h): want(x.get("logging", {}).get("options", {}).get("max-size") == "20m" and x["logging"]["options"].get("max-file") == "3", "log limits")
want(any(v["target"] == "/data/share" and not v.get("read_only") for v in w["volumes"]), "no writable /data/share example")
want(all(v.get("read_only") for v in h["volumes"]), "the helper has a writable mount")
' "$BODY" "$PASSWORD" "$SECRET"; then ok 'compose.yaml: 127.0.0.1:8099, 1000:1000, helper internal only, log limits'; else fail "compose.yaml: $(python3 -I -c 'import json,sys; c=json.load(open(sys.argv[1])); print(json.dumps(c["services"], indent=1)[:1500])' "$BODY")"; fi

echo "building the images"
docker build -q -t indexof:"$TAG" web >/dev/null || fail 'docker build web'
docker build -q -t indexof-helper:"$TAG" helper >/dev/null || fail 'docker build helper'
ok 'images built'

# The demo data, made with the helper image's ffmpeg: the movies (one with two audio tracks and
# two subtitle tracks, one behind an odd name), music, pictures and share's awkward entries (a
# symbolic link out of the folder, a name ending with a line break, -TT=x, *, 1,500 files).
echo "making the demo data"
INDEXOF_HELPER_IMAGE=indexof-helper:"$TAG" sh tests/make-demo.sh "$DATA" >"$BODY" 2>&1 || fail "make-demo.sh: $(cat "$BODY")"
expect_file "$MKV_FILE" 'demo data'
expect_file "$DATA/movies/Amélie (2001)/L'Amour & #1?.mkv" 'demo data'
expect_file "$DATA/movies/Short (2023).fr.srt" 'demo data'
expect_file "$DATA/pictures/Beach Walk (2024).jpg" 'demo data'
expect_file "$DATA/share/link-to-passwd" 'demo data'
if [ -f "$DATA/share/a$nl/etc/passwd" ]; then ok 'demo data: share/a<line break>/etc/passwd is there'; else fail 'demo data: no share/a<line break>/etc/passwd'; fi
many=$(find "$DATA/share/many" -type f | wc -l | tr -d ' ')
if [ "$many" = 1500 ]; then ok 'demo data: share/many holds 1,500 files'; else fail "demo data: share/many holds $many files, wanted 1500"; fi
expect_no_file "$DATA/.make-demo" 'demo data: scratch folder removed'
# ffprobe, from the helper image (as the current user: the temporary folder is theirs alone), on
# a file under the temporary folder: media_of writes its streams and format to $TMP/probe.txt;
# video_packets prints the video track's bytes and packets.
ffprobe_t() { docker run --rm --network none --user "$(id -u):$(id -g)" -v "$TMP:/x:ro" --entrypoint ffprobe indexof-helper:"$TAG" -v error "$@"; }
media_of() { ffprobe_t -show_entries format=format_name:stream=codec_type,codec_name,channels -of flat "/x/${1#"$TMP"/}" >"$TMP/probe.txt" 2>&1; }
expect_media() { # FILE WHAT NEEDLE...: each NEEDLE in ffprobe's view of FILE
  f=$1; what=$2; shift 2
  media_of "$f"
  for needle in "$@"; do grep -qF -- "$needle" "$TMP/probe.txt" || fail "$what: no '$needle' in ffprobe's: $(tr '\n' ' ' <"$TMP/probe.txt" | head -c 400)"; done
  ok "$what: $*"
}
expect_no_media() { # FILE WHAT NEEDLE: NEEDLE absent from ffprobe's view of FILE (made by expect_media before)
  if grep -qF -- "$3" "$TMP/probe.txt"; then fail "$2: '$3' in ffprobe's view (it must not)"; else ok "$2: no $3"; fi
}
video_packets() { ffprobe_t -select_streams v:0 -show_entries packet=size -of csv=p=0 "/x/${1#"$TMP"/}" 2>/dev/null | awk '{ s += $1; n++ } END { print s + 0, n + 0 }'; }
audio_packets() { ffprobe_t -select_streams "a:$2" -show_entries packet=size -of csv=p=0 "/x/${1#"$TMP"/}" 2>/dev/null | awk '{ s += $1; n++ } END { print s + 0, n + 0 }'; }
expect_media "$MKV_FILE" 'demo mkv' 'codec_name="h264"' 'codec_name="eac3"' 'channels=6' 'codec_name="aac"' 'channels=2' 'codec_name="subrip"' 'format_name="matroska,webm"'
src_video=$(video_packets "$MKV_FILE"); src_audio=$(audio_packets "$MKV_FILE" 1)
case "$src_video" in *' 750') ok "demo mkv: 750 video packets ($src_video)" ;; *) fail "demo mkv: video packets: $src_video, wanted 750 (30 s at 25 fps)" ;; esac

# The image's own checks, before the stack: the config (rendered with the mounts, none here)
# passes nginx -t, and a missing or short secret stops the start.
if docker run --rm -e INDEXOF_PASSWORD=$PASSWORD -e INDEXOF_LINK_SECRET=$SECRET indexof:"$TAG" nginx -t >"$BODY" 2>&1; then ok 'nginx -t on the rendered config'; else fail "nginx -t: $(cat "$BODY")"; fi
if docker run --rm -e INDEXOF_LINK_SECRET=$SECRET indexof:"$TAG" nginx -t >"$BODY" 2>&1; then fail 'started without INDEXOF_PASSWORD'; fi
if grep -q INDEXOF_PASSWORD "$BODY"; then ok 'refuses to start without INDEXOF_PASSWORD'; else fail "no INDEXOF_PASSWORD message in: $(cat "$BODY")"; fi
if docker run --rm -e INDEXOF_PASSWORD=$PASSWORD -e INDEXOF_LINK_SECRET=short indexof:"$TAG" nginx -t >"$BODY" 2>&1; then fail 'started with a short INDEXOF_LINK_SECRET'; fi
if grep -q INDEXOF_LINK_SECRET "$BODY"; then ok 'refuses to start with a short INDEXOF_LINK_SECRET'; else fail "no INDEXOF_LINK_SECRET message in: $(cat "$BODY")"; fi
if docker run --rm indexof-helper:"$TAG" >"$BODY" 2>&1; then fail 'helper started without INDEXOF_LINK_SECRET'; fi
if grep -q INDEXOF_LINK_SECRET "$BODY"; then ok 'helper refuses to start without INDEXOF_LINK_SECRET'; else fail "helper: no INDEXOF_LINK_SECRET message in: $(cat "$BODY")"; fi

# INDEXOF_SCP (the scp line's destination) must be user@host or host, INDEXOF_SCP_ROOT (the
# folder on that host holding the mounted folders) an absolute path: anything scp, a shell or
# the settings JSON could read otherwise stops the start, with a line naming the variable.
refused_start() { # VARIABLE VALUE WHAT: the start refuses VARIABLE=VALUE, naming it
  if docker run --rm -e INDEXOF_PASSWORD=$PASSWORD -e INDEXOF_LINK_SECRET=$SECRET -e INDEXOF_SCP=me@nas.example -e "$1=$2" indexof:"$TAG" nginx -t >"$BODY" 2>&1; then fail "started with $1 $3"; fi
  if grep -q "$1" "$BODY"; then ok "refuses $1 $3"; else fail "$1 $3: no $1 in: $(cat "$BODY")"; fi
}
refused_start INDEXOF_SCP 'me@host x' 'with a space'
refused_start INDEXOF_SCP "me@host'" 'with a quote'
refused_start INDEXOF_SCP 'me@host"' 'with a double quote'
refused_start INDEXOF_SCP 'me@ho\st' 'with a backslash'
refused_start INDEXOF_SCP "me@host$ctl" 'with a control character'
refused_start INDEXOF_SCP "me@ho${nl}st" 'with a line break'
refused_start INDEXOF_SCP '-x@host' 'starting with a dash (an option to scp)'
refused_start INDEXOF_SCP 'me@-host' 'whose host starts with a dash'
refused_start INDEXOF_SCP 'me@host:/srv' 'with a path (that is INDEXOF_SCP_ROOT)'
refused_start INDEXOF_SCP 'a@b@c' 'with two @'
refused_start INDEXOF_SCP '@host' 'with an empty user'
refused_start INDEXOF_SCP 'me@' 'with an empty host'
refused_start INDEXOF_SCP 'me@host;id' 'with a semicolon'
# shellcheck disable=SC2016 # (the value stays as written: that is the point)
refused_start INDEXOF_SCP 'me@$(id)' 'with $()'
refused_start INDEXOF_SCP_ROOT 'srv/files' 'that is not absolute'
refused_start INDEXOF_SCP_ROOT '/srv files' 'with a space'
refused_start INDEXOF_SCP_ROOT '/srv"x' 'with a double quote'
refused_start INDEXOF_SCP_ROOT "/srv'x" 'with a quote'
refused_start INDEXOF_SCP_ROOT '/srv\x' 'with a backslash'
# shellcheck disable=SC2016 # (as written)
refused_start INDEXOF_SCP_ROOT '/srv$x' 'with a dollar'
refused_start INDEXOF_SCP_ROOT '/srv`x' 'with a backtick'
refused_start INDEXOF_SCP_ROOT "/srv$ctl" 'with a control character'
refused_start INDEXOF_SCP_ROOT "/srv${nl}x" 'with a line break'
# What the settings say, from the start script alone: the destination as given, null without
# one; the root as given (a trailing slash dropped, / itself empty), /data without one.
expect_settings() { # WANT [docker run options...]
  want=$1; shift
  got=$(docker run --rm -e INDEXOF_PASSWORD=$PASSWORD -e INDEXOF_LINK_SECRET=$SECRET "$@" indexof:"$TAG" sh -c '/docker-entrypoint.d/50-indexof-mounts.sh >/dev/null 2>&1 && cat /tmp/settings.json')
  if [ "$got" = "$want" ]; then ok "settings (${*:-nothing set}): $got"; else fail "settings (${*:-nothing set}): $got, wanted $want"; fi
}
expect_settings '{"mounts":{},"scp":null,"scp_root":"/data"}'
expect_settings '{"mounts":{},"scp":null,"scp_root":"/data"}' -e INDEXOF_SCP= -e INDEXOF_SCP_ROOT=
expect_settings '{"mounts":{},"scp":"me@nas.example","scp_root":"/data"}' -e INDEXOF_SCP=me@nas.example
expect_settings '{"mounts":{},"scp":"nas","scp_root":"/srv/files"}' -e INDEXOF_SCP=nas -e INDEXOF_SCP_ROOT=/srv/files/
expect_settings '{"mounts":{},"scp":"me.x_y-z@h-1.example","scp_root":""}' -e INDEXOF_SCP=me.x_y-z@h-1.example -e INDEXOF_SCP_ROOT=/
expect_settings '{"mounts":{},"scp":null,"scp_root":"/srv"}' -e INDEXOF_SCP_ROOT=/srv

# Every entry under /data is looked at: a dangling symbolic link and a plain file are refused
# with a line each, never skipped in silence (the whole fixture mounted, read-only); the others
# are the settings, the odd name as it is.
docker run --rm -e INDEXOF_PASSWORD=$PASSWORD -e INDEXOF_LINK_SECRET=$SECRET -v "$DATA:/data:ro" indexof:"$TAG" sh -c '/docker-entrypoint.d/50-indexof-mounts.sh && cat /tmp/settings.json' >"$BODY" 2>&1 || fail "start script on the whole fixture: $(cat "$BODY")"
if grep -q 'refused mount /data/dangling: it is a symbolic link' "$BODY"; then ok 'start log: refused mount dangling (a symbolic link to nowhere)'; else fail "no 'refused mount' for the dangling link in: $(cat "$BODY")"; fi
if grep -q 'refused mount /data/file.txt: it is not a folder' "$BODY"; then ok 'start log: refused mount file.txt (not a folder)'; else fail "no 'refused mount' for file.txt in: $(cat "$BODY")"; fi
if grep -q "^{\"mounts\":{\"$ODD\":\"ro\",\"My Stuff\":\"ro\",\"documents\":\"ro\",\"movies\":\"ro\",\"music\":\"ro\",\"pictures\":\"ro\",\"share\":\"ro\"}," "$BODY"; then ok 'settings (whole fixture, read-only): the seven folders, the odd name as it is'; else fail "settings (whole fixture): $(grep '^{' "$BODY")"; fi
# A folder whose name holds a control character (Docker mounts it as such) is refused with a
# line, and is not in the settings.
docker run --rm -e INDEXOF_PASSWORD=$PASSWORD -e INDEXOF_LINK_SECRET=$SECRET -v "$DATA/share:/data/share:ro" -v "$DATA/share:/data/a${ctl}b:ro" indexof:"$TAG" sh -c '/docker-entrypoint.d/50-indexof-mounts.sh && cat /tmp/settings.json' >"$BODY" 2>&1 || fail "start script with a control character mount: $(tr -d '\001' <"$BODY")"
if grep -q 'refused mount /data/a.b: its name holds a control character' "$BODY"; then ok 'start log: refused mount a<control character>b'; else fail "no 'refused mount' for the control character in: $(tr -d '\001' <"$BODY")"; fi
if grep -q '^{"mounts":{"share":"ro"},' "$BODY"; then ok 'settings: the control character mount left out'; else fail "settings with a control character mount: $(grep '^{' "$BODY")"; fi

echo "starting the stack"
compose up -d >/dev/null 2>&1 || { compose logs --no-color; fail 'compose up'; }
n=0
until [ "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/_login")" = 200 ]; do
  n=$((n + 1)); [ "$n" -lt 60 ] || { compose logs --no-color; fail 'the stack did not come up in 30 s'; }
  sleep 0.5
done
ok 'stack up'

# The start: the refused mounts are logged, the others become the settings.
compose logs --no-color indexof >"$BODY" 2>&1
if grep -q 'refused mount.*_search' "$BODY"; then ok 'start log: refused mount _search'; else fail "no 'refused mount' for _search in the start log: $(cat "$BODY")"; fi
if grep -q 'refused mount.*\.hidden' "$BODY"; then ok 'start log: refused mount .hidden'; else fail "no 'refused mount' for .hidden in the start log"; fi
if grep -q "/data/$ODD: writable" "$BODY"; then ok "start log: /data/$ODD: writable"; else fail "no 'writable' line for the odd name in the start log"; fi

# Login gating: a page without the cookie (or with a wrong one) goes to /_login; the helper's
# routes answer 403 (the pages' scripts) or go to /_login (what a browser opens).
expect_status -n GET / 302
expect_header -n / 'Location: /_login'
expect_status -n GET /share/ 302
expect_status -n GET / 302 -H 'Cookie: session=wrong'
expect_status -n GET "$MP4" 302
expect_status -n GET /_settings 403
expect_status -n GET '/_size?p=/movies/' 403
expect_status -n GET '/_space?p=/movies/' 403
expect_status -n GET "/_vlc?f=$MP4" 403
expect_status -n GET "/_probe?f=$MP4" 403
expect_status -n GET "/_sub?f=$MKV&s=0" 403
expect_status -n GET '/_zip?p=/movies/' 302
expect_status -n GET "/_remux?f=$MKV&a=1&t=0" 302
expect_status -n GET '/_search?q=demo' 302
expect_status -n GET /_recent 302
expect_status -n GET "/_play?f=$MP4" 302
expect_status -n PUT /share/x.txt 302 -T "$TMP/hello.txt"
expect_no_file "$DATA/share/x.txt" 'upload without the cookie'

# /_settings: the mounts, read-only or writable; the refused ones absent; the scp destination
# and root from the .env (the root's trailing slash dropped).
expect_status GET /_settings 200
expect_body /_settings '"movies":"ro"'
expect_body /_settings '"music":"ro"'
expect_body /_settings '"pictures":"rw"'
expect_body /_settings '"share":"rw"'
expect_body /_settings '"My Stuff":"rw"'
expect_body /_settings "\"$ODD\":\"rw\""
expect_body /_settings '"scp":"me@nas.example"'
expect_body /_settings '"scp_root":"/srv/files"'
expect_no_body /_settings '_search'
expect_no_body /_settings '.hidden'
expect_header /_settings 'Content-Type: application/json'

# The home page lists the mounted folders, and only them; the refused ones are never served.
expect_body / 'href="movies/"'
expect_body / 'href="share/"'
expect_body / 'href="My%20Stuff/"'
expect_body / 'href="Am%C3%A9lie%20%282001%29%20%26%20co%27s%20%231/">Amélie (2001) &amp; co'"'"'s #1/</a>'
expect_no_body / 'href="_search/"'
expect_no_body / 'href=".hidden/"'
expect_status GET /_search/ 404
expect_status GET /_search/secret.txt 404
expect_status GET /.hidden/ 403
expect_status GET /.hidden/secret.txt 403
expect_status GET /nowhere/ 404
expect_status GET /nowhere.txt 404
expect_status PUT /x.txt 404 -T "$TMP/hello.txt"
expect_status MKCOL /new/ 404

# A read-only folder: browse and download only; the names with spaces, accents and signs are
# listed as the page expects them (encoded in the link, as they are in the text).
expect_status GET /movies 301
expect_header /movies 'Location: /movies/'
expect_body /movies/ 'Short%20%282023%29.mp4'
expect_body /movies/ 'href="Am%C3%A9lie%20%282001%29/">Amélie (2001)/</a>'
expect_body '/movies/Am%C3%A9lie%20(2001)/' "L%27Amour%20%26%20%231%3F.mkv\">L'Amour &amp; #1?.mkv</a>"
expect_status GET "$MP4" 200
expect_status GET "$MKV2" 200
expect_header "$MP4" 'Content-Security-Policy: sandbox'
expect_header "$MP4" 'Content-Type: video/mp4'
expect_status PUT /movies/x.txt 405 -T "$TMP/hello.txt"
expect_status DELETE "$MP4" 405
expect_status MKCOL /movies/new/ 405
expect_status MOVE "$MP4" 405 -H "Destination: $BASE/movies/x.mp4"
expect_status DELETE /movies/ 405
expect_no_file "$DATA/movies/x.txt" 'read-only folder'
expect_file "$DATA/movies/Short (2023).mp4" 'read-only folder'
expect_status GET /movies/.uploads/ 403
expect_status GET /share/link-to-passwd 403
expect_no_body /share/link-to-passwd 'root:'

# A writable folder: uploads, new folders, rename/move, delete; the folder itself never.
expect_status PUT /share/x.txt 201 -T "$TMP/hello.txt"
expect_body /share/x.txt 'hello'
expect_header /share/x.txt 'Content-Security-Policy: sandbox'
expect_status PUT '/My%20Stuff/x.txt' 201 -T "$TMP/hello.txt"
expect_file "$DATA/My Stuff/x.txt" 'upload into My Stuff'
expect_status MKCOL /share/new/ 201
expect_status MOVE /share/x.txt 204 -H "Destination: $BASE/share/new/y.txt"
expect_no_file "$DATA/share/x.txt" 'move'
expect_file "$DATA/share/new/y.txt" 'move'
expect_status MOVE /share/new/ 201 -H "Destination: $BASE/share/newer/"
expect_file "$DATA/share/newer/y.txt" 'folder move'
expect_status DELETE /share/newer/y.txt 204
expect_status DELETE /share/newer/ 204
expect_status DELETE '/My%20Stuff/x.txt' 204
expect_status DELETE /share/ 405
expect_status MOVE /share/ 405 -H "Destination: $BASE/share2/"
expect_status DELETE '/My%20Stuff/' 405
expect_status MOVE '/My%20Stuff/' 405 -H "Destination: $BASE/share/stuff/"
expect_status GET /share 301
expect_status GET /share/.uploads/ 403
expect_status PUT /share/.secret 403 -T "$TMP/hello.txt"
# Odd names everywhere: a file with an accent, an ampersand, a hash and parentheses is uploaded,
# listed, downloaded, renamed and deleted; the folder with such a name takes uploads, moves, has
# a size and a zip like any other, and its 301 points at its encoded name.
expect_status PUT '/share/pat/caf%C3%A9%20%26%20%231%20(x).txt' 201 -T "$TMP/hello.txt"
expect_file "$DATA/share/pat/café & #1 (x).txt" 'upload of an odd name'
expect_body /share/pat/ 'href="caf%C3%A9%20%26%20%231%20%28x%29.txt">café &amp; #1 (x).txt</a>'
expect_body '/share/pat/caf%C3%A9%20%26%20%231%20(x).txt' 'hello'
# A file is served as it is: the listing's line (Upload, Logout, the script) goes under folders only.
expect_body '/My%20Stuff/text/page.html' '<b>shown as source</b>'
expect_no_body '/My%20Stuff/text/page.html' 'Logout'
expect_body '/My%20Stuff/text/' 'Logout'
# The viewport tag (a phone shows the page at its own width): in the listings' <head> and the
# pages', never added to a file.
vp='<head><meta name="viewport" content="width=device-width, initial-scale=1">'
expect_body / "$vp"
expect_body /share/ "$vp"
expect_body '/My%20Stuff/text/' "$vp"
expect_body '/_search?q=Buck' "$vp"
expect_body /_login 'name="viewport"'
expect_body "/_play?f=$MP4" 'name="viewport"'
expect_no_body '/My%20Stuff/text/page.html' 'viewport'
expect_status MOVE '/share/pat/caf%C3%A9%20%26%20%231%20(x).txt' 204 -H "Destination: $BASE/share/pat/caf%C3%A9%20(2).txt"
expect_file "$DATA/share/pat/café (2).txt" 'rename of an odd name'
expect_status DELETE '/share/pat/caf%C3%A9%20(2).txt' 204
expect_no_file "$DATA/share/pat/café (2).txt" 'delete of an odd name'
expect_status GET "/$ODD_E" 301
expect_header "/$ODD_E" "Location: /$ODD_E/"
expect_status GET "/$ODD_E/" 200
expect_status PUT "/$ODD_E/x.txt" 201 -T "$TMP/hello.txt"
expect_file "$DATA/$ODD/x.txt" 'upload into the odd folder'
expect_body "/$ODD_E/" 'href="x.txt"'
expect_status MKCOL "/$ODD_E/sub/" 201
expect_status PUT /share/m.txt 201 -T "$TMP/hello.txt"
expect_status MOVE /share/m.txt 204 -H "Destination: $BASE/$ODD_E/sub/m.txt"
expect_file "$DATA/$ODD/sub/m.txt" 'move into the odd folder'
expect_status MOVE "/$ODD_E/sub/m.txt" 204 -H "Destination: $BASE/share/m.txt"
expect_file "$DATA/share/m.txt" 'move out of the odd folder'
expect_status DELETE "/$ODD_E/sub/" 204
expect_status DELETE "/$ODD_E/" 405
expect_status GET "/_size?p=/$ODD_E/" 200
if grep -Eq '^[0-9.]+[KMGT]?$' "$BODY"; then ok "/_size of the odd folder -> $(cat "$BODY")"; else fail "/_size of the odd folder: not a size: $(cat "$BODY")"; fi
expect_zip "/_zip?p=/$ODD_E/" "$ODD/" "$ODD/x.txt"
expect_body "/_space?p=/$ODD_E/" ' free / '
expect_status GET "/_vlc?f=/$ODD_E/x.txt" 200
# Moves stay inside writable folders: never into a read-only or a refused one, never to another
# host (nginx refuses the Destination).
expect_not_2xx MOVE /share/m.txt -H "Destination: $BASE/movies/m.txt"
expect_not_2xx MOVE /share/m.txt -H "Destination: $BASE/music/m.txt"
expect_not_2xx MOVE /share/m.txt -H "Destination: $BASE/_search/m.txt"
expect_not_2xx MOVE /share/m.txt -H "Destination: $BASE/share/%2e%2e/_search/m.txt"
expect_not_2xx MOVE /share/m.txt -H "Destination: $BASE/share/../_search/m.txt"
expect_not_2xx MOVE /share/m.txt -H "Destination: $BASE/.hidden/m.txt"
expect_not_2xx MOVE /share/m.txt -H "Destination: $BASE/share/"
expect_not_2xx MOVE /share/m.txt -H "Destination: $BASE/m.txt"
expect_not_2xx MOVE /share/m.txt -H "Destination: http://evil.example/share/m2.txt"
expect_not_2xx MOVE /share/m.txt -H "Destination: http://evil.example/My%20Stuff/m2.txt"
# Never into or onto a hidden name (the page could neither list nor delete it there; .uploads
# must stay the upload folder), however the dot is written.
expect_not_2xx MOVE /share/m.txt -H "Destination: $BASE/share/.uploads/m.txt"
expect_not_2xx MOVE /share/m.txt -H "Destination: $BASE/share/%2euploads/m.txt"
expect_not_2xx MOVE /share/m.txt -H "Destination: $BASE/share/%2Euploads/m.txt"
# An encoded slash or backslash would hide a dot from the check (decoded after it).
expect_not_2xx MOVE /share/m.txt -H "Destination: $BASE/share/x%2f.uploads/m.txt"
expect_not_2xx MOVE /share/m.txt -H "Destination: $BASE/share/x%2F.uploads/m.txt"
expect_not_2xx MOVE /share/m.txt -H "Destination: $BASE/share/x%5c.uploads/m.txt"
expect_not_2xx MOVE /share/m.txt -H "Destination: $BASE/share/.m.txt"
expect_not_2xx MOVE /share/m.txt -H "Destination: $BASE/share/pat/%2Em.txt"
expect_status MKCOL /share/dir/ 201
expect_not_2xx MOVE /share/dir/ -H "Destination: $BASE/share/.uploads/"
expect_not_2xx MOVE /share/dir/ -H "Destination: $BASE/share/%2Euploads/"
expect_not_2xx MOVE /share/dir/ -H "Destination: $BASE/share/.dir/"
expect_file "$DATA/share/dir" 'refused moves'
expect_dir_empty "$DATA/share/.uploads" 'refused moves onto .uploads'
expect_status DELETE /share/dir/ 204
expect_file "$DATA/share/m.txt" 'refused moves'
expect_no_file "$DATA/share/.m.txt" 'refused moves'
expect_no_file "$DATA/_search/m.txt" 'refused moves'
expect_no_file "$DATA/.hidden/m.txt" 'refused moves'
expect_no_file "$DATA/movies/m.txt" 'refused moves'
expect_status MOVE /share/m.txt 204 -H "Destination: $BASE/My%20Stuff/m.txt"
expect_file "$DATA/My Stuff/m.txt" 'move between writable folders'
expect_status DELETE '/My%20Stuff/m.txt' 204

# Uploads: finished or cancelled, nothing stays in the folder's .uploads.
expect_status PUT /share/big.bin 201 -T "$TMP/big.bin"
expect_file "$DATA/share/big.bin" 'big upload'
expect_dir_empty "$DATA/share/.uploads" 'after an upload'
expect_status DELETE /share/big.bin 204
curl -s -o /dev/null -X PUT -H "Cookie: $COOKIE" --limit-rate 2M -m 2 -T "$TMP/big.bin" "$BASE/share/cancelled.bin"
sleep 1
expect_no_file "$DATA/share/cancelled.bin" 'cancelled upload'
expect_dir_empty "$DATA/share/.uploads" 'after a cancelled upload'

# A folder of 1,500 entries is listed whole (the page splits it into pages of 100 itself).
expect_status GET /share/many/ 200
links=$(grep -c '<a href' "$BODY")
if [ "$links" -ge 1500 ]; then ok "GET /share/many/ lists $links links (1,500 files)"; else fail "GET /share/many/ lists $links links, wanted 1,500 or more"; fi
expect_body /share/many/ 'href="file-1500.txt"'

# The helper, through the page's routes: paths of the page only, inside a mounted folder.
expect_status GET '/_size?p=/movies/' 200
if grep -Eq '^[0-9.]+[KMGT]?$' "$BODY"; then ok "/_size?p=/movies/ -> $(cat "$BODY")"; else fail "/_size?p=/movies/: not a size: $(cat "$BODY")"; fi
expect_status GET '/_size?p=/share/many/' 200
if grep -Eq '^[0-9.]+[KMGT]?$' "$BODY"; then ok "/_size?p=/share/many/ -> $(cat "$BODY")"; else fail "/_size?p=/share/many/: not a size: $(cat "$BODY")"; fi
expect_status GET "/_size?p=$MP4" 200
# (1.2M on disk; Docker Desktop's file sharing may still count 2.0M just after it was written)
if grep -Eq '^(1\.[0-9]|2\.0)M$' "$BODY"; then ok "/_size of the mp4 -> $(cat "$BODY")"; else fail "/_size of the mp4: $(cat "$BODY"), wanted 1.xM"; fi
expect_empty '/_size?p=/../etc/'
expect_empty '/_size?p=/'
expect_empty '/_size?p=/_search/'
expect_empty '/_size?p=/.hidden/'
expect_empty '/_size?p=/share/.uploads'
expect_empty '/_size?p=/share/link-to-passwd'
expect_empty "/_size?p=/share/a%0A/"
expect_body '/_space?p=/share/' ' free / '
if grep -Eq '^[0-9.]+[KMGTP]? free / [0-9.]+[KMGTP]?$' "$BODY"; then ok "/_space?p=/share/ -> $(cat "$BODY")"; else fail "/_space?p=/share/: $(cat "$BODY")"; fi
expect_empty '/_space?p=/../'
expect_empty '/_space?p=/_search/'
expect_empty '/_space?p='
# The home page (p=/): each disk holding a mounted folder, once; the fixture's folders are all on
# one disk, so "X free / Y" alone, as in a folder.
for p in %2F /; do
  expect_status GET "/_space?p=$p" 200
  if [ "$(sed -E 's/[0-9.]+[KMGTP]?/N/g' "$BODY")" = 'N free / N' ]; then ok "/_space?p=$p (the home page, one disk) -> $(cat "$BODY")"; else fail "/_space?p=$p: '$(cat "$BODY")', wanted 'X free / Y'"; fi
done
# Several disks (the helper image alone, two tmpfs besides the fixture's disk; a hidden one and
# one starting with _ left out): each named after its first folder by name, joined with " · ".
docker run --rm --network none -e QUERY_STRING=p=%2F -v "$DATA/share:/data/share:ro" -v "$DATA/movies:/data/movies:ro" --tmpfs /data/backup --tmpfs /data/_cache --tmpfs /data/.snap --entrypoint /www/cgi-bin/space indexof-helper:"$TAG" >"$BODY" 2>&1 || fail "space with several disks: $(cat "$BODY")"
tr -d '\r' <"$BODY" | sed '1,/^$/d' >"$TMP/space"
got=$(sed -E 's/[0-9.]+[KMGTP]?/N/g' "$TMP/space")
if [ "$got" = 'backup N free / N · movies N free / N' ]; then ok "/_space?p=/ with several disks -> $(cat "$TMP/space")"; else fail "/_space?p=/ with several disks: '$(cat "$BODY")'"; fi

# Zips: a folder's [zip] link (GET) and the selection's form (POST), valid for Python's zipfile,
# with a random 9-character name, streamed (nothing left in the helper's /tmp). The symbolic
# link out of share, the hidden .uploads and the folder whose name ends with a line break (with
# what is under it) are left out; -TT=x and * are stored as names.
expect_body '/_zip?p=/' 'nothing to zip'
# Only uploads may be big: a 2 MB zip request (thousands of paths) is refused before the helper.
head -c 2100000 /dev/zero | tr '\0' 'a' | sed 's/^/p=/' > "$TMP/huge-zip-body"
expect_status POST /_zip 413 --data-binary @"$TMP/huge-zip-body"
expect_body '/_zip?p=/_search/' 'nothing to zip'
expect_body '/_zip?p=/../etc/' 'nothing to zip'
expect_body '/_zip?p=/share/link-to-passwd' 'nothing to zip'
expect_body '/_zip?p=/share/a%0A/' 'nothing to zip'
expect_body '/_zip?p=/share/.uploads/' 'nothing to zip'
expect_zip '/_zip?p=/movies/' 'movies/' 'movies/Short (2023).mp4' 'movies/Short (2023).fr.srt' 'movies/Long Take (2022).mp4' 'movies/Big Buck Test (2024)/' 'movies/Big Buck Test (2024)/Big Buck Test (2024).mkv' 'movies/Amélie (2001)/' "movies/Amélie (2001)/L'Amour & #1?.mkv"
expect_zip '/_zip?p=/music/' 'music/' 'music/Demo Song.mp3' 'music/Démo (lossless).flac'
curl -s -o "$BODY" -D "$TMP/headers" -H "Cookie: $COOKIE" "$BASE/_zip?p=/share/"
if grep -Eq '^Content-Disposition: attachment; filename="[a-z0-9]{9}\.zip"' "$TMP/headers"; then ok "zip of /share/: $(grep -o 'filename="[^"]*"' "$TMP/headers")"; else fail "zip of /share/: no random name: $(grep -i disposition "$TMP/headers")"; fi
if python3 -I -c '
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    bad = z.testzip()
    if bad: sys.exit("corrupt entry " + bad)
    names = z.namelist()
for w in ["share/", "share/notes.txt", "share/-TT=x", "share/*", "share/100% done.txt", "share/pat/", "share/pat/*", "share/pat/[ab].txt", "share/many/", "share/many/file-0001.txt", "share/many/file-1500.txt"]:
    if w not in names: sys.exit("missing " + repr(w) + " in " + repr([n for n in names if not n.startswith("share/many/")]))
for n in names:
    if "link" in n or "\n" in n or "/." in n or "passwd" in n: sys.exit("unwanted entry " + repr(n))
many = sum(1 for n in names if n.startswith("share/many/") and n != "share/many/")
if many != 1500: sys.exit("share/many: %d entries, wanted 1500" % many)
' "$BODY"; then ok 'zip of /share/: -TT=x and * stored as names, 1,500 files, no link, no .uploads, no line-break folder'; else fail "zip of /share/: $(python3 -I -c 'import sys, zipfile; print(sorted(n for n in zipfile.ZipFile(sys.argv[1]).namelist() if not n.startswith("share/many/")))' "$BODY" 2>&1 | head -c 400)"; fi
# Names are names, never patterns: a file called * and one called [ab].txt are zipped alone.
expect_zip '/_zip?p=/share/pat/%2A' '*'
expect_zip '/_zip?p=/share/pat/%5Bab%5D.txt' '[ab].txt'
expect_zip '/_zip?p=/share/-TT%3Dx' '-TT=x'
# The selection's form, posted: the paths given (the refused ones dropped), named from their
# common folder, or from the root when they are in different folders.
expect_zip -d 'p=%2Fshare%2Fnotes.txt&p=%2Fshare%2F-TT%3Dx&p=%2Fshare%2F%2A&p=%2Fshare%2Flink-to-passwd&p=%2Fshare%2Fa%0A%2F&p=%2Fshare%2F.uploads&p=%2F..%2Fetc%2Fpasswd' '/_zip' 'notes.txt' '-TT=x' '*'
expect_zip -d 'p=%2Fshare%2Fnotes.txt&p=%2Fmusic%2FDemo%20Song.mp3&p=%2Fmovies%2FAm%C3%A9lie%20(2001)%2F' '/_zip' 'share/notes.txt' 'music/Demo Song.mp3' 'movies/Amélie (2001)/' "movies/Amélie (2001)/L'Amour & #1?.mkv"
got=$(req POST /_zip --data 'p=%2F_search%2Fsecret.txt&p=%2F.hidden%2Fsecret.txt')
if grep -q 'nothing to zip' "$BODY"; then ok 'POST /_zip of refused paths -> nothing to zip'; else fail "POST /_zip of refused paths ($got): $(head -c 100 "$BODY")"; fi
left=$(compose exec -T indexof-helper find /tmp -mindepth 1 2>/dev/null | tr '\n' ' ')
if [ -z "$left" ]; then ok 'zips: nothing left in the helper /tmp'; else fail "zips: left in the helper /tmp: $left"; fi

# Search: by name, in a folder, files or folders, by kind, at most so many; the refused folders
# never searched, nothing from outside the mounted folders whatever the query says (the folder
# whose name ends with a line break is left out: the part after the break would be read as
# another path); every value cut down before it reaches find or the page. (The results' links
# are encoded like nginx's listing: parentheses and quotes as %XX too.)
MKV_S='/movies/Big%20Buck%20Test%20%282024%29/Big%20Buck%20Test%20%282024%29.mkv'
ODD_S="Am%C3%A9lie%20%282001%29%20%26%20co%27s%20%231"
expect_header '/_search?q=Buck' 'Content-Type: text/html'
expect_search '/_search?q=Buck' "$MKV_S" '/movies/Big%20Buck%20Test%20%282024%29/' '/My%20Stuff/subs/Big%20Buck%20Test%20%282024%29.srt'
expect_search_count '/_search?q=Buck' 3
expect_search_count '/_search?q=Buck&type=d' 1
expect_search_count '/_search?q=Buck&type=f' 2
expect_search '/_search?q=Buck&in=movies' "$MKV_S"
expect_no_search '/_search?q=Buck&in=movies' 'My%20Stuff'
expect_search_inside '/_search?q=Buck&in=movies' '/movies/'
expect_body '/_search?q=Buck&in=movies' '<h1>Search: Buck in /movies/</h1>'
# (A backslash in a name is encoded in the link: a browser would read it as a slash.)
expect_body '/_search?q=slash' 'href="/My%20Stuff/subs/back%5Cslash.txt"'
expect_search '/_search?q=Buck&in=movies/Big%20Buck%20Test%20(2024)' "$MKV_S"
expect_search_count '/_search?q=Buck&in=movies/Big%20Buck%20Test%20(2024)' 1
expect_search "/_search?q=x.txt&in=$ODD_E" "/$ODD_S/x.txt"
expect_search_inside "/_search?q=x.txt&in=$ODD_E" "/$ODD_S/"
expect_body "/_search?q=x.txt&in=$ODD_E" "<h1>Search: x.txt in /Amélie (2001) &amp; co's #1/</h1>"
expect_search '/_search?q=Amour' '/movies/Am%C3%A9lie%20%282001%29/L%27Amour%20%26%20%231%3F.mkv'
expect_search '/_search?q=done' '/share/100%25%20done.txt'
expect_search '/_search?q=many&type=d' '/share/many/'
expect_search_count '/_search?q=many&type=f' 0
expect_no_search '/_search?q=secret' 'secret.txt'
expect_no_body '/_search?q=Buck' 'value="_search"'
expect_no_body '/_search?q=Buck' 'value=".hidden"'
expect_body '/_search?q=Buck' 'value="My Stuff"'
expect_body '/_search?q=Buck' "value=\"Amélie (2001) &amp; co's #1\""
expect_body '/_search?q=Buck' 'value="movies/Big Buck Test (2024)"'
# By kind: the extensions of videos, subtitle files, music and pictures.
expect_search '/_search?kind=video' "$MKV_S" '/movies/Short%20%282023%29.mp4' '/movies/Long%20Take%20%282022%29.mp4' '/movies/Am%C3%A9lie%20%282001%29/L%27Amour%20%26%20%231%3F.mkv'
expect_search_count '/_search?kind=video' 4
expect_search '/_search?kind=audio' '/music/Demo%20Song.mp3' '/music/D%C3%A9mo%20%28lossless%29.flac'
expect_search_count '/_search?kind=audio' 2
expect_search '/_search?kind=images&in=pictures' '/pictures/Test%20Pattern.png' '/pictures/Gradient%20%282024%29.jpg' '/pictures/Beach%20Walk%20%282024%29.jpg'
expect_search_count '/_search?kind=images' 3
expect_search '/_search?kind=subtitles' '/My%20Stuff/subs/Big%20Buck%20Test%20%282024%29.srt' '/movies/Short%20%282023%29.fr.srt'
expect_search_count '/_search?kind=subtitles' 2
expect_search_count '/_search?kind=video&in=music' 0
expect_search_count '/_search?q=Demo&kind=audio' 1
expect_body '/_search?kind=video' '<option value="video" selected>'
# At most so many: 100, 500 (also for a value that is not offered), 1000 or 2000.
expect_search_count '/_search?q=file-&max=100' 100
expect_search_count '/_search?q=file-&in=share/many&max=2000' 1500
expect_search_count '/_search?q=file-&max=7' 500
expect_body '/_search?q=file-&max=7' '<option value="500" selected>'
# Nothing without a query of two characters or more (or a kind).
expect_status GET '/_search' 200
expect_no_body '/_search' '<pre id="list"'
expect_no_body '/_search?q=a' '<pre id="list"'
# The attacks: a folder outside, a refused one, a hidden name; a shell's or a page's characters.
expect_search_inside '/_search?q=passwd' '/share/'
expect_search_count '/_search?q=passwd' 1
expect_search '/_search?q=passwd' '/share/link-to-passwd'
expect_search_inside '/_search?q=passwd&in=../../etc' '/share/'
expect_body '/_search?q=passwd&in=../../etc' '<h1>Search: passwd</h1>'
expect_search_inside '/_search?q=passwd&in=share/../../etc' '/share/'
expect_search_inside '/_search?q=passwd&in=/etc' '/share/'
expect_no_search '/_search?q=secret&in=.hidden' 'secret'
expect_no_search '/_search?q=secret&in=_search' 'secret'
expect_no_search '/_search?q=secret&in=share/../.hidden' 'secret'
expect_no_search '/_search?q=secret&in=share/link-to-passwd' 'secret'
expect_no_search '/_search?q=uploads' '.uploads'
expect_no_search '/_search?q=passwd&in=share/a%0A' 'etc'
expect_body '/_search?q=%24(id)' '<h1>Search: (id)</h1>'
expect_no_body '/_search?q=%24(id)' 'uid='
expect_body '/_search?q=%60id%60' '<h1>Search: id</h1>'
expect_no_body '/_search?q=%60id%60' 'uid='
expect_body "/_search?q=%22x%22%27y%27" '<h1>Search: xy</h1>'
expect_no_body '/_search?q=%3Cscript%3Ealert(1)%3C%2Fscript%3E' '<script>alert'
expect_no_body '/_search?q=x&in=%3Cscript%3Ealert(1)%3C%2Fscript%3E' '<script>alert'
expect_no_body '/_search?q=x&in=%22%3E%3Cscript%3Ealert(1)%3C%2Fscript%3E' '<script>alert'
expect_search '/_search?q=notes&type=x&kind=x&max=7' '/share/notes.txt'
expect_body '/_search?q=notes&type=x&kind=x&max=7' '<option value="" selected>all</option>'
expect_body '/_search?q=notes&type=x&kind=x&max=7' '<option value="" selected>any</option>'
# The "in:" list: "everywhere" chosen when no folder is; a folder whose name holds a line break
# (share's a<LF>) or another control character is left out (a line break once made it two
# options, the empty one taking "everywhere"'s place).
mkdir -p "$DATA/share/c${ctl}d" || exit 1
expect_body '/_search?q=Buck' '<option value="" selected>everywhere</option>'
expect_no_body '/_search?q=Buck' '<option value="" selected></option>'
expect_no_body '/_search?q=Buck' 'value="share/a"'
expect_no_body '/_search?q=Buck' 'value="share/c'
expect_body '/_search?q=Buck&in=movies' '<option value="">everywhere</option>'
expect_body '/_search?q=Buck&in=movies' '<option value="movies" selected>movies</option>'
rmdir "$DATA/share/c${ctl}d"

# Inside text files (text=1): the viewer's text kinds, under 5 MB, holding the words as they
# are (case aside), in the folder chosen, 200 at most; never a binary file, a big one, a hidden
# one or a symbolic link; the words are a fixed string, never a pattern, an option or the shell's.
N="$DATA/My Stuff/notes"
mkdir -p "$N/cap" "$N/.dot" || exit 1
printf 'A yellow zebrafish42 swims here.\n' >"$N/fish.txt"
printf 'zebrafish42\n' >"$N/fish.bin"
{ head -c 6000000 /dev/zero | tr '\0' 'x'; printf '\nzebrafish42\n'; } >"$N/huge.txt"
printf 'zebrafish42\n' >"$N/.hidden.txt"
printf 'zebrafish42\n' >"$N/.dot/in.txt"
ln -s fish.txt "$N/link.txt"
# shellcheck disable=SC2016 # (written as it is: the search must find it as it is)
printf 'run $(id) and x*y, then -v\n' >"$N/shell.md"
i=0; while [ $i -lt 250 ]; do echo 'capword' >"$N/cap/c-$i.log"; i=$((i + 1)); done
expect_search '/_search?q=zebrafish42&text=1' '/My%20Stuff/notes/fish.txt'
expect_search_count '/_search?q=zebrafish42&text=1' 1
expect_search_count '/_search?q=ZebraFish42&text=1' 1
expect_search_count '/_search?q=zebrafish42' 0
expect_search_count '/_search?q=zebrafish42&text=1&in=share' 0
expect_search_count '/_search?q=zebrafish42&text=1&in=My%20Stuff/notes' 1
expect_body '/_search?q=zebrafish42&text=1' '<h1>Search: zebrafish42 (inside text files)</h1>'
expect_body '/_search?q=zebrafish42&text=1' 'name="text" value="1" checked>'
expect_no_body '/_search?q=zebrafish42' 'name="text" value="1" checked>'
expect_search_count '/_search?q=capword&text=1' 200
expect_body '/_search?q=capword&text=1&max=2000' '<pre id="list" data-max="200">'
expect_search_count '/_search?q=capword&text=1&max=100' 100
expect_no_body '/_search?q=z&text=1' '<pre id="list"'
expect_search '/_search?q=%24(id)&text=1' '/My%20Stuff/notes/shell.md'
expect_search_count '/_search?q=%24(id)&text=1' 1
# shellcheck disable=SC2016 # (as written)
expect_body '/_search?q=%24(id)&text=1' '<h1>Search: $(id) (inside text files)</h1>'
expect_no_body '/_search?q=%24(id)&text=1' 'uid='
expect_search_count '/_search?q=%60id%60&text=1' 0
expect_search_count '/_search?q=x*y&text=1' 1
expect_search_count '/_search?q=**&text=1' 0
expect_search_count '/_search?q=-v&text=1' 1
expect_search_count '/_search?q=--help&text=1' 0
expect_body '/_search?q=%22%3E%3Cb%3E&text=1' '<h1>Search: &quot;&gt;&lt;b&gt; (inside text files)</h1>'
expect_no_body '/_search?q=%3Cscript%3Ealert(1)&text=1' '<script>alert'
expect_search_count '/_search?q=root:&text=1&in=../../etc' 0
expect_search_inside '/_search?q=zebrafish42&text=1&in=../../etc' '/My%20Stuff/notes/'

# Recent: the 50 files last modified, everywhere, newest first, in the search's listing format
# (the line under it, the viewport tag, never stored); never a folder, a hidden name or a
# symbolic link, however new. (Their times set a day ahead: newer than anything else here.)
R="$DATA/share/recent"
mkdir -p "$R/newdir" "$R/.dot" || exit 1
echo older >"$R/older.txt"; echo newer >"$R/newer.txt"; echo x >"$R/.hidden.txt"; echo x >"$R/.dot/in.txt"
ln -s newer.txt "$R/link.txt"
python3 -I -c '
import os, sys, time
t = time.time() + 86400
for p, ahead in zip(sys.argv[1::2], sys.argv[2::2]):
    os.utime(p, (t + int(ahead), t + int(ahead)), follow_symlinks=False)
' "$R/older.txt" 100 "$R/newer.txt" 200 "$R/.hidden.txt" 900 "$R/.dot/in.txt" 900 "$R/newdir" 900 "$R/link.txt" 900 "$N/fish.txt" 50 || fail 'setting the recent files times'
expect_status GET /_recent 200
expect_header /_recent 'Cache-Control: no-store'
expect_body /_recent '<title>Recent</title>'
expect_body /_recent '<h1>Recent</h1>'
expect_body /_recent "$vp"
expect_body /_recent 'Logout'
expect_search_count /_recent 50
got=$(search_hrefs /_recent | head -n 3 | tr '\n' ' ')
if [ "$got" = '/share/recent/newer.txt /share/recent/older.txt /My%20Stuff/notes/fish.txt ' ]; then ok "GET /_recent: newest first ($got)"; else fail "GET /_recent: the first three are $got"; fi
expect_no_search /_recent '.hidden' '.dot' 'link.txt' 'newdir' 'link-to-passwd'
got=$(search_hrefs /_recent | grep -c '/$')
if [ "$got" = 0 ]; then ok 'GET /_recent: no folder'; else fail "GET /_recent: $got folders"; fi
rm -rf "$R" "$N"

# The player's helpers on the demo mkv: what is in it (two audio tracks, the E-AC3 one the
# default, two text subtitle tracks), its subtitles as WebVTT, and the file repackaged with its
# other audio track: copied, never converted. The same behind the odd name.
expect_status GET "/_probe?f=$MKV" 200
expect_body "/_probe?f=$MKV" 'video h264'
expect_body "/_probe?f=$MKV" 'audio 0 eac3 fre 6 1 Français 5.1'
expect_body "/_probe?f=$MKV" 'audio 1 aac eng 2 0 English'
expect_body "/_probe?f=$MKV" 'sub 0 subrip fre text 0 Français'
expect_body "/_probe?f=$MKV" 'sub 1 subrip eng text 0 English'
if grep -Eq '^duration 30\.[0-9]+$' "$BODY"; then ok "/_probe: $(grep '^duration' "$BODY")"; else fail "/_probe: no 30 s duration in: $(cat "$BODY")"; fi
expect_header "/_probe?f=$MKV" 'Content-Type: text/plain; charset=utf-8'
expect_header "/_probe?f=$MKV" 'Cache-Control: no-store'
expect_body "/_probe?f=$MKV2" 'audio 0 eac3 fre 6 1 Français 5.1'
expect_body "/_probe?f=$MKV2" 'sub 1 subrip eng text 0 English'
expect_body "/_probe?f=$MP4" 'audio 0 aac eng 2 1'
expect_no_body "/_probe?f=$MP4" 'sub '
expect_body '/_probe?f=/music/Demo%20Song.mp3' 'audio 0 mp3'
expect_no_body '/_probe?f=/music/Demo%20Song.mp3' 'video'
expect_status GET '/_probe?f=/../etc/passwd' 404
expect_status GET '/_probe?f=/_search/secret.txt' 404
expect_status GET '/_probe?f=/share/link-to-passwd' 404
expect_status GET '/_probe?f=/movies/' 404
expect_status GET "/_probe?f=$MKV&k=abc" 400
expect_status GET "/_probe?f=$MKV&k=-1" 400
expect_status GET "/_probe?f=$MKV&k=1234567" 400
expect_status GET "/_probe?f=$MKV&k=1.2345" 400
# Keyframes: one every 2 s in the demo mkv. /_probe?k= names the last one at or before k, in the
# time ffmpeg's -ss counts (the file's start_time taken off: here the AAC track's priming, a
# few ms), so that /_remux?t= starts right on it (checked below).
keyframe() { req GET "/_probe?f=$MKV&k=$1" >/dev/null; sed -n 's/^keyframe \([0-9.]*\)$/\1/p' "$BODY"; }
kf0=$(keyframe 0); kf10=$(keyframe 11.5); kf10b=$(keyframe 10.5); kf28=$(keyframe 29.9)
if awk -v a="$kf0" 'BEGIN { exit !(a >= 0 && a < 0.1) }'; then ok "/_probe?k=0 -> keyframe $kf0"; else fail "/_probe?k=0 -> '$kf0', wanted the first keyframe (0 to 0.1)"; fi
if awk -v a="$kf10" 'BEGIN { exit !(a >= 10 && a < 10.1) }'; then ok "/_probe?k=11.5 -> keyframe $kf10 (the 2 s grid)"; else fail "/_probe?k=11.5 -> '$kf10', wanted the keyframe at 10 s"; fi
if [ "$kf10b" = "$kf10" ]; then ok "/_probe?k=10.5 -> keyframe $kf10b (the same)"; else fail "/_probe?k=10.5 -> '$kf10b', wanted $kf10"; fi
if awk -v a="$kf28" 'BEGIN { exit !(a >= 28 && a < 28.1) }'; then ok "/_probe?k=29.9 -> keyframe $kf28 (the last)"; else fail "/_probe?k=29.9 -> '$kf28', wanted the keyframe at 28 s"; fi
expect_empty '/_probe?f=/music/Demo%20Song.mp3&k=1'

# Subtitles: each text track as WebVTT, with its cues.
expect_status GET "/_sub?f=$MKV&s=0" 200
if [ "$(head -c 6 "$BODY")" = WEBVTT ]; then ok '/_sub s=0 starts with WEBVTT'; else fail "/_sub s=0: $(head -c 100 "$BODY")"; fi
cues=$(grep -c -- '-->' "$BODY")
if [ "$cues" = 4 ]; then ok '/_sub s=0: 4 cues'; else fail "/_sub s=0: $cues cues, wanted 4"; fi
if grep -Eq '^00:01\.0[0-9]{2} --> 00:04\.0[0-9]{2}$' "$BODY"; then ok "/_sub s=0: the first cue at 1-4 s ($(grep -m1 -- '-->' "$BODY"))"; else fail "/_sub s=0: no cue at 1-4 s in: $(head -c 300 "$BODY")"; fi
expect_body "/_sub?f=$MKV&s=0" 'Bonjour ! Ceci est une démo.'
expect_body "/_sub?f=$MKV&s=0" 'Fin de la démo.'
expect_header "/_sub?f=$MKV&s=0" 'Content-Type: text/vtt'
expect_body "/_sub?f=$MKV&s=1" 'Hello! This is a demo.'
expect_no_body "/_sub?f=$MKV&s=1" 'Bonjour'
expect_body "/_sub?f=$MKV2&s=1" 'End of the demo.'
expect_status GET "/_sub?f=$MKV&s=2" 404
expect_body "/_sub?f=$MKV&s=2" 'no such subtitle track'
expect_body "/_sub?f=$MP4&s=0" 'no such subtitle track'
expect_status GET "/_sub?f=$MKV&s=x" 400
expect_status GET "/_sub?f=$MKV&s=-1" 400
expect_status GET "/_sub?f=$MKV" 400
expect_status GET '/_sub?f=/.hidden/secret.txt&s=0' 404
expect_status GET '/_sub?f=/share/link-to-passwd&s=0' 404
# A subtitle file next to a video (s=file): converted to WebVTT (an .srt, an old one in
# Windows-1252, an .ass), a .vtt as it is; only those extensions, 5 MB at most, under /data, not
# hidden. (The files made here, after the search's counts.)
SRT='/movies/Short%20(2023).fr.srt'
expect_status GET "/_sub?f=$SRT&s=file" 200
if [ "$(head -c 6 "$BODY")" = WEBVTT ]; then ok '/_sub s=file (.srt) starts with WEBVTT'; else fail "/_sub s=file: $(head -c 100 "$BODY")"; fi
cues=$(grep -c -- '-->' "$BODY")
if [ "$cues" = 2 ] && grep -Eq '^00:01\.000 --> 00:04\.000$' "$BODY"; then ok '/_sub s=file (.srt): 2 cues, the first at 1-4 s'; else fail "/_sub s=file: $cues cues in: $(head -c 300 "$BODY")"; fi
expect_body "/_sub?f=$SRT&s=file" 'Un fichier de sous-titres à côté de la vidéo.'
expect_header "/_sub?f=$SRT&s=file" 'Content-Type: text/vtt'
printf '1\r\n00:00:02,000 --> 00:00:03,000\r\nCaf\351 cr\350me\r\n' >"$DATA/My Stuff/subs/old.srt"
expect_body '/_sub?f=/My%20Stuff/subs/old.srt&s=file' 'Café crème'
printf '[Script Info]\nScriptType: v4.00+\n\n[V4+ Styles]\nFormat: Name, Fontname, Fontsize\nStyle: Default,Arial,20\n\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,An ASS line.\n' >"$DATA/My Stuff/subs/a.ass"
expect_body '/_sub?f=/My%20Stuff/subs/a.ass&s=file' 'An ASS line.'
printf 'WEBVTT\n\n00:01.000 --> 00:02.000\nA <b>VTT</b> line.\n' >"$DATA/My Stuff/subs/a.vtt"
expect_body '/_sub?f=/My%20Stuff/subs/a.vtt&s=file' 'A <b>VTT</b> line.'
# (a playlist dressed as an .srt: read as SubRip, it opens nothing)
printf '#EXTM3U\n#EXTINF:1,\n/data/share/notes.txt\n' >"$DATA/My Stuff/subs/playlist.srt"
expect_no_body '/_sub?f=/My%20Stuff/subs/playlist.srt&s=file' 'Demo data'
expect_status GET "/_sub?f=$MP4&s=file" 415
expect_status GET '/_sub?f=/My%20Stuff/text/readme.txt&s=file' 415
expect_status GET '/_sub?f=/../etc/passwd&s=file' 404
expect_status GET '/_sub?f=/movies/../../etc/passwd&s=file' 404
printf '1\n00:00:01,000 --> 00:00:02,000\nhidden\n' >"$DATA/My Stuff/subs/.hidden.srt"
expect_status GET '/_sub?f=/My%20Stuff/subs/.hidden.srt&s=file' 404
printf '1\n00:00:01,000 --> 00:00:02,000\nhidden\n' >"$DATA/.hidden/x.srt"
expect_status GET '/_sub?f=/.hidden/x.srt&s=file' 404
awk 'BEGIN { for (i = 0; i < 60000; i++) printf "%d\n00:00:01,000 --> 00:00:02,000\nA line of a subtitle file over five megabytes, ninety bytes long.\n\n", i + 1 }' >"$DATA/My Stuff/subs/big.srt"
expect_status GET '/_sub?f=/My%20Stuff/subs/big.srt&s=file' 413
expect_body '/_sub?f=/My%20Stuff/subs/big.srt&s=file' 'over 5 MB'

# Repackaged with another audio track: a=1 (AAC) as a fragmented MP4, a=0 (E-AC3, which MP4
# cannot stream) as Matroska; the video and the audio copied (the same packets, byte for byte, as
# the source's), the subtitles left out; from t= on: the keyframe /_probe?k= named.
remux() { # NAME QUERY: /_remux?f=<the mkv>&QUERY saved as $TMP/NAME (headers in $TMP/headers), the status printed
  curl -s -o "$TMP/$1" -D "$TMP/headers" -w '%{http_code}' -H "Cookie: $COOKIE" "$BASE/_remux?f=$MKV&$2"
}
got=$(remux remux-a1 'a=1&t=0')
if [ "$got" = 200 ] && grep -qi '^Content-Type: video/mp4' "$TMP/headers"; then ok '/_remux a=1 t=0 -> 200, video/mp4'; else fail "/_remux a=1 t=0: $got, $(grep -i content-type "$TMP/headers")"; fi
expect_media "$TMP/remux-a1" '/_remux a=1' 'stream.0.codec_name="h264"' 'stream.0.codec_type="video"' 'stream.1.codec_name="aac"' 'stream.1.codec_type="audio"' 'stream.1.channels=2' 'format_name="mov,mp4'
expect_no_media "$TMP/remux-a1" '/_remux a=1: two streams only (no subtitles)' 'stream.2.'
if python3 -I -c 'import sys; d = open(sys.argv[1], "rb").read(); sys.exit(0 if d[4:8] == b"ftyp" and b"moof" in d else 1)' "$TMP/remux-a1"; then ok '/_remux a=1: a fragmented MP4 (ftyp, moof)'; else fail '/_remux a=1: not a fragmented MP4'; fi
v=$(video_packets "$TMP/remux-a1")
if [ "$v" = "$src_video" ]; then ok "/_remux a=1: the video copied ($v bytes/packets, as the source)"; else fail "/_remux a=1: video packets $v, the source's $src_video"; fi
a=$(audio_packets "$TMP/remux-a1" 0)
if [ "$a" = "$src_audio" ]; then ok "/_remux a=1: the AAC track copied ($a bytes/packets, as the source's a:1)"; else fail "/_remux a=1: audio packets $a, the source's a:1 $src_audio"; fi
got=$(remux remux-a0 'a=0&t=0')
if [ "$got" = 200 ] && grep -qi '^Content-Type: video/x-matroska' "$TMP/headers"; then ok '/_remux a=0 t=0 -> 200, video/x-matroska'; else fail "/_remux a=0 t=0: $got, $(grep -i content-type "$TMP/headers")"; fi
expect_media "$TMP/remux-a0" '/_remux a=0' 'stream.0.codec_name="h264"' 'stream.1.codec_name="eac3"' 'stream.1.codec_type="audio"' 'stream.1.channels=6' 'format_name="matroska,webm"'
expect_no_media "$TMP/remux-a0" '/_remux a=0: two streams only (no subtitles)' 'stream.2.'
if python3 -I -c 'import sys; d = open(sys.argv[1], "rb").read(4); sys.exit(0 if d == b"\x1a\x45\xdf\xa3" else 1)' "$TMP/remux-a0"; then ok '/_remux a=0: Matroska (EBML header)'; else fail '/_remux a=0: not Matroska'; fi
v=$(video_packets "$TMP/remux-a0")
if [ "$v" = "$src_video" ]; then ok "/_remux a=0: the video copied ($v bytes/packets, as the source)"; else fail "/_remux a=0: video packets $v, the source's $src_video"; fi
got=$(remux remux-t "a=1&t=$kf10")
v=$(video_packets "$TMP/remux-t")
case "$got $v" in '200 '*' 500') ok "/_remux a=1 t=$kf10 (the keyframe /_probe?k=11.5 named): 500 of 750 packets, from the 10 s keyframe" ;; *) fail "/_remux a=1 t=$kf10: $got, video packets $v, wanted 500 (from the keyframe at 10 s)" ;; esac
got=$(remux remux-t2 'a=0&t=11.5')
v=$(video_packets "$TMP/remux-t2")
case "$got $v" in '200 '*' 500') ok '/_remux a=0 t=11.5: 500 packets, from the keyframe at or before (10 s)' ;; *) fail "/_remux a=0 t=11.5: $got, video packets $v, wanted 500" ;; esac
curl -s -o "$TMP/remux-mkv2" -w '%{http_code}' -H "Cookie: $COOKIE" "$BASE/_remux?f=$MKV2&a=1&t=0" >"$TMP/status" # (the odd name: the same file)
v=$(video_packets "$TMP/remux-mkv2")
if [ "$(cat "$TMP/status")" = 200 ] && [ "$v" = "$src_video" ]; then ok "/_remux of the odd name: 200, the video copied"; else fail "/_remux of the odd name: $(cat "$TMP/status"), video packets $v"; fi
expect_status GET "/_remux?f=$MKV&a=x&t=0" 400
expect_status GET "/_remux?f=$MKV&a=-1&t=0" 400
expect_status GET "/_remux?f=$MKV&a=100&t=0" 400
expect_status GET "/_remux?f=$MKV&a=0&t=-1" 400
expect_status GET "/_remux?f=$MKV&a=0&t=1e3" 400
expect_status GET "/_remux?f=$MKV&a=0&t=1234567" 400
expect_status GET "/_remux?f=$MKV&a=0&t=1.2345" 400
expect_status GET "/_remux?f=$MKV&a=5&t=0" 404
expect_body "/_remux?f=$MKV&a=5&t=0" 'no such audio track'
expect_status GET '/_remux?f=/music/Demo%20Song.mp3&a=0&t=0' 404
expect_body '/_remux?f=/music/Demo%20Song.mp3&a=0&t=0' 'no video track'
expect_status GET '/_remux?f=/../etc/passwd&a=0&t=0' 404
expect_status GET '/_remux?f=/.hidden/secret.txt&a=0&t=0' 404
expect_status GET '/_remux?f=/share/link-to-passwd&a=0&t=0' 404
expect_status GET '/_remux?f=/movies/&a=0&t=0' 404

# Temporary links: the file only, reading only (GET and HEAD, ranges too), until they expire;
# a changed time, a forged or missing signature, another file, a folder, a past time: no.
expect_status GET "/_vlc?f=$MP4" 200
link=$(tr -d '\r\n' <"$BODY")
case "$link" in e=*\&k=*) ok "/_vlc -> $link" ;; *) fail "/_vlc: $link" ;; esac
e=${link%%\&*}; e=${e#e=}; k=${link#*k=}
now=$(date +%s)
if [ "$e" -gt $((now + 11 * 3600)) ] && [ "$e" -le $((now + 12 * 3600 + 5)) ]; then ok '/_vlc: the link expires in 12 hours'; else fail "/_vlc: e=$e, now $now"; fi
expect_header "/_vlc?f=$MP4" 'Cache-Control: no-store'
expect_status -n GET "$MP4?$link" 200
expect_status -n HEAD "$MP4?$link" 200
expect_status -n GET "$MP4?$link" 206 -r 0-99
expect_header -n "$MP4?$link" 'Content-Range: bytes 0-99/' -r 0-99
expect_header -n "$MP4?$link" 'Content-Security-Policy: sandbox'
expect_status -n GET "$MKV?$link" 302
expect_status -n GET "/movies/Am%C3%A9lie%20(2001)/?$link" 302
expect_status -n GET "/movies/?$link" 302
expect_status -n GET "$MP4?e=$((e + 1))&k=$k" 302
expect_status -n GET "$MP4?e=$e&k=AAAAAAAAAAAAAAAAAAAAAA" 302
expect_status -n GET "$MP4?e=$e&k=${k}x" 302
expect_status -n GET "$MP4?e=$e" 302
expect_status -n GET "$MP4?k=$k" 302
expect_status -n PUT "/share/film.mkv?$link" 302 -T "$TMP/hello.txt"
expect_status -n DELETE "$MP4?$link" 302
expect_status -n MOVE "$MP4?$link" 302 -H "Destination: $BASE/share/x.mp4"
expect_file "$DATA/movies/Short (2023).mp4" 'signed links: reading only'
# The helper's recipe, followed here: a past time, signed, is refused; a time ahead is taken;
# and a link to a file in a writable folder reads it, never changes it.
sign() { python3 -I -c 'import sys, hashlib, base64; print(base64.urlsafe_b64encode(hashlib.md5((sys.argv[1] + sys.argv[2] + " " + sys.argv[3]).encode()).digest()).decode().rstrip("="))' "$1" "$2" "$SECRET"; }
past=$((now - 60)); ahead=$((now + 600))
expect_status -n GET "$MP4?e=$past&k=$(sign "$past" '/movies/Short (2023).mp4')" 302
expect_status -n GET "$MP4?e=$ahead&k=$(sign "$ahead" '/movies/Short (2023).mp4')" 200
expect_status -n GET "/share/notes.txt?e=$ahead&k=$(sign "$ahead" '/share/notes.txt')" 200
expect_status -n PUT "/share/notes.txt?e=$ahead&k=$(sign "$ahead" '/share/notes.txt')" 302 -T "$TMP/hello.txt"
expect_status -n DELETE "/share/notes.txt?e=$ahead&k=$(sign "$ahead" '/share/notes.txt')" 302
expect_body /share/notes.txt 'nothing here is real'
expect_status GET '/_vlc?f=/_search/secret.txt' 404
expect_status GET '/_vlc?f=/.hidden/secret.txt' 404
expect_status GET '/_vlc?f=/movies/' 404
expect_status GET '/_vlc?f=/share/link-to-passwd' 404
expect_status GET '/_vlc?f=/../etc/passwd' 404
expect_status GET "/_vlc?f=$MKV2" 200
link2=$(tr -d '\r\n' <"$BODY")
expect_status -n GET "$MKV2?$link2" 200
expect_status -n HEAD "$MKV2?$link2" 200
expect_status -n GET "$MKV?$link2" 302

# The player loads only paths of this server: f=//evil.example/x is not a path here.
expect_status GET '/_play?f=//evil.example/x' 200
play_src() { # the src the served player builds for ?f=$1, computed by its own script
  node -e '
    const html = require("fs").readFileSync(process.argv[1], "utf8"), m = html.match(/<script>([\s\S]*?)<\/script>/);
    if (!m) { console.error("no script"); process.exit(1); }
    const head = m[1].split("\nconst msg")[0]; // up to the player set-up: f, kind, src, title
    const location = { search: "?f=" + encodeURIComponent(process.argv[2]), origin: process.argv[3] };
    const document = { getElementById: () => ({}), title: "" };
    const r = new Function("location", "document", head + "\nreturn { f, src };")(location, document);
    console.log(r.f + "\n" + r.src);
  ' "$BODY" "$1" "$BASE"
}
out=$(play_src '//evil.example/x') || fail 'the player script did not run under node'
if [ "$out" = "/
$BASE/" ]; then ok "player: f=//evil.example/x -> f='/', src=$BASE/"; else fail "player: f=//evil.example/x gave: $out"; fi
out=$(play_src '/movies/Short (2023).mp4')
if [ "$out" = "/movies/Short (2023).mp4
$BASE/movies/Short%20(2023).mp4" ]; then ok "player: f=/movies/Short (2023).mp4 -> src=$BASE/movies/Short%20(2023).mp4"; else fail "player: f=/movies/Short (2023).mp4 gave: $out"; fi
out=$(play_src "/movies/Amélie (2001)/L'Amour & #1?.mkv")
if [ "$out" = "/movies/Amélie (2001)/L'Amour & #1?.mkv
$BASE/movies/Am%C3%A9lie%20(2001)/L'Amour%20%26%20%231%3F.mkv" ]; then ok "player: the odd name -> src=$BASE$MKV2"; else fail "player: the odd name gave: $out"; fi
out=$(play_src '\\evil.example\x')
if [ "$out" = "/
$BASE/" ]; then ok "player: f=\\\\evil.example\\x -> f='/'"; else fail "player: backslash path gave: $out"; fi

# The line under listings reads /_settings: writable means a writable folder, never the folder itself.
req GET /share/ >/dev/null
if grep -q "fetch('/_settings'" "$BODY"; then ok 'listing page reads /_settings'; else fail 'listing page does not fetch /_settings'; fi
expect_no_body /share/ "indexOf('/share/')"
if node -e '
  const html = require("fs").readFileSync(process.argv[1], "utf8"), m = html.match(/^const mountOf = .*writable = .*$/m);
  if (!m) { console.error("no writable() line in the page"); process.exit(1); }
  const writable = new Function("settings", m[0] + "\nreturn writable;")({ mounts: { share: "rw", "My Stuff": "rw", movies: "ro" }, scp: null });
  const want = { "/share/x": true, "/share/a/b/": true, "/My Stuff/x.txt": true, "/share/": false, "/share": false, "/movies/x": false, "/": false, "/_search": false, "/nowhere/x": false };
  for (const p in want) if (writable(p) !== want[p]) { console.error("writable(" + JSON.stringify(p) + ") = " + writable(p)); process.exit(1); }
' "$BODY"; then ok 'writable(): rw folders only, never the folder itself'; else fail 'writable() in the page'; fi
# The scp line's destination: the settings' destination, then the folder's path on that host
# (the root from the settings, /data when none was given, and the page's path).
if node -e '
  const html = require("fs").readFileSync(process.argv[1], "utf8"), m = html.match(/^const scpDest = .*$/m);
  if (!m) { console.error("no scpDest line in the page"); process.exit(1); }
  const scpDest = new Function(m[0] + "\nreturn scpDest;")();
  const want = [
    [{ scp: "me@nas.example", scp_root: "/srv/files" }, "/share/", "me@nas.example:/srv/files/share/"],
    [{ scp: "me@nas.example", scp_root: "/srv/files" }, "/share/sub/", "me@nas.example:/srv/files/share/sub/"],
    [{ scp: "nas", scp_root: "/data" }, "/My Stuff/", "nas:/data/My Stuff/"],
    [{ scp: "nas", scp_root: "" }, "/share/", "nas:/share/"],
  ];
  for (const [s, p, d] of want) if (scpDest(s, p) !== d) { console.error("scpDest(" + JSON.stringify(s) + ", " + JSON.stringify(p) + ") = " + scpDest(s, p)); process.exit(1); }
' "$BODY"; then ok 'scpDest(): destination:root + path'; else fail 'scpDest() in the page'; fi

# The helper stopped: the page itself goes on (listing, downloads, the player's page, uploads);
# what needs the helper answers with an error status within seconds, never hangs. Then it is
# started again and found again (nginx looks its name up at each request).
echo "stopping the helper"
compose stop -t 2 indexof-helper >/dev/null 2>&1 || fail 'compose stop indexof-helper'
expect_status GET / 200
expect_status GET /movies/ 200
expect_status GET /share/many/ 200
expect_status GET "$MP4" 200
expect_status GET "$MKV2" 200
expect_status -n GET "$MP4?$link" 200
expect_status GET "/_play?f=$MP4" 200
expect_status GET /_settings 200
expect_status PUT /share/h.txt 201 -T "$TMP/hello.txt"
expect_status DELETE /share/h.txt 204
helper_down() { # PATH: an error status (5xx), within 5 seconds
  got=$(curl -s -o "$BODY" -m 5 -w '%{http_code}' -H "Cookie: $COOKIE" "$BASE$1")
  case "$got" in 5[0-9][0-9]) ok "GET $1 -> $got (the helper stopped)" ;; *) fail "GET $1 with the helper stopped: '$got' (000: no answer in 5 s)" ;; esac
}
helper_down '/_size?p=/movies/'
helper_down '/_search?q=Buck'
helper_down '/_recent'
helper_down '/_space?p=/share/'
helper_down '/_zip?p=/movies/'
helper_down "/_probe?f=$MKV"
helper_down "/_sub?f=$MKV&s=0"
helper_down "/_remux?f=$MKV&a=1&t=0"
helper_down "/_vlc?f=$MP4"
compose start indexof-helper >/dev/null 2>&1 || fail 'compose start indexof-helper'
n=0
until [ "$(curl -s -o /dev/null -m 5 -w '%{http_code}' -H "Cookie: $COOKIE" "$BASE/_size?p=/movies/")" = 200 ]; do
  n=$((n + 1)); [ "$n" -lt 40 ] || fail 'the helper did not come back in 20 s'
  sleep 0.5
done
ok 'the helper started again: /_size answers'
expect_body '/_space?p=/share/' ' free / '
expect_search '/_search?q=Buck' "$MKV_S"

# A page whose every folder is read-only (the image alone, on another port): the settings say
# so, nothing can be changed anywhere, browsing and downloads work as before, and the line under
# the listings offers no upload (its writable() says no for every path).
echo "starting a page with every folder read-only"
docker run -d --name "$PROJECT-ro" -p "127.0.0.1:$RO_PORT:8080" --user "$(id -u):$(id -g)" -e INDEXOF_PASSWORD=$PASSWORD -e INDEXOF_LINK_SECRET=$SECRET -v "$DATA/movies:/data/movies:ro" -v "$DATA/share:/data/share:ro" -v "$DATA/My Stuff:/data/My Stuff:ro" -v "$DATA/$ODD:/data/$ODD:ro" indexof:"$TAG" >/dev/null 2>&1 || fail 'docker run (the read-only page)'
BASE="http://127.0.0.1:$RO_PORT"
n=0
until [ "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/_login")" = 200 ]; do
  n=$((n + 1)); [ "$n" -lt 60 ] || { docker logs "$PROJECT-ro"; fail 'the read-only page did not come up in 30 s'; }
  sleep 0.5
done
docker logs "$PROJECT-ro" >"$BODY" 2>&1
if grep -q 'writable' "$BODY"; then fail "read-only page: a 'writable' line in the start log: $(grep writable "$BODY")"; fi
if [ "$(grep -c ': read-only$' "$BODY")" = 4 ]; then ok 'read-only page: the start log says read-only for the four folders'; else fail "read-only page: $(grep -c ': read-only$' "$BODY") read-only lines in the start log: $(grep indexof: "$BODY")"; fi
expect_body /_settings "{\"mounts\":{\"$ODD\":\"ro\",\"My Stuff\":\"ro\",\"movies\":\"ro\",\"share\":\"ro\"},\"scp\":null,\"scp_root\":\"/data\"}"
expect_no_body /_settings '"rw"'
expect_body / 'href="share/"'
expect_body / 'href="Am%C3%A9lie%20%282001%29%20%26%20co%27s%20%231/"'
expect_status GET /share/ 200
expect_body /share/ 'notes.txt'
expect_status GET /share/notes.txt 200
expect_status GET /share/many/ 200
expect_status GET "$MP4" 200
expect_status GET "/_play?f=$MP4" 200
expect_status PUT /share/x.txt 405 -T "$TMP/hello.txt"
expect_status PUT '/My%20Stuff/x.txt' 405 -T "$TMP/hello.txt"
expect_status PUT "/$ODD_E/y.txt" 405 -T "$TMP/hello.txt"
expect_status PUT /movies/x.txt 405 -T "$TMP/hello.txt"
expect_status MKCOL /share/new/ 405
expect_status DELETE /share/notes.txt 405
expect_status DELETE "/$ODD_E/x.txt" 405
expect_status MOVE /share/notes.txt 405 -H "Destination: $BASE/share/n.txt"
expect_status MOVE /share/notes.txt 405 -H "Destination: $BASE/My%20Stuff/n.txt"
expect_file "$DATA/share/notes.txt" 'read-only page'
expect_file "$DATA/$ODD/x.txt" 'read-only page'
expect_no_file "$DATA/share/x.txt" 'read-only page'
expect_no_file "$DATA/My Stuff/x.txt" 'read-only page'
expect_no_file "$DATA/$ODD/y.txt" 'read-only page'
req GET /share/ >/dev/null
if node -e '
  const html = require("fs").readFileSync(process.argv[1], "utf8"), m = html.match(/^const mountOf = .*writable = .*$/m);
  if (!m) { console.error("no writable() line in the page"); process.exit(1); }
  const writable = new Function("settings", m[0] + "\nreturn writable;")(JSON.parse(process.argv[2]));
  for (const p of ["/share/", "/share/x", "/share/a/b/", "/My Stuff/x.txt", "/movies/x", "/Amélie (2001) & co\x27s #1/x.txt", "/"]) if (writable(p)) { console.error("writable(" + JSON.stringify(p) + ") is true"); process.exit(1); }
' "$BODY" "$(curl -s -H "Cookie: $COOKIE" "$BASE/_settings")"; then ok 'read-only page: writable() says no for every path (no upload line)'; else fail 'read-only page: writable() in the page'; fi
docker rm -f "$PROJECT-ro" >/dev/null 2>&1
BASE="http://127.0.0.1:$PORT"

# What the page shows, in a real browser when one is here (GitHub's runners have Chrome).
chrome=
for c in google-chrome google-chrome-stable chromium chromium-browser "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"; do
  if command -v "$c" >/dev/null 2>&1 || [ -x "$c" ]; then chrome=$c; break; fi
done
if [ -n "$chrome" ]; then
  "$chrome" --headless=new --no-sandbox --disable-gpu --remote-debugging-port="$CDP_PORT" --user-data-dir="$TMP/chrome" about:blank >/dev/null 2>&1 &
  chrome_pid=$!
  i=0; until curl -s http://127.0.0.1:"$CDP_PORT"/json/version >/dev/null 2>&1 || [ $i -ge 30 ]; do sleep 0.5; i=$((i + 1)); done
  INDEXOF_PASSWORD=$PASSWORD CDP_PORT="$CDP_PORT" INDEXOF_RW_DIR="$DATA/share" node "$(dirname "$0")/ui.mjs" "$BASE" share movies many || { kill "$chrome_pid" 2>/dev/null; fail 'what the page shows (tests/ui.mjs)'; }
  INDEXOF_PASSWORD=$PASSWORD CDP_PORT="$CDP_PORT" node "$(dirname "$0")/ui-viewer.mjs" "$BASE" 'My Stuff/text' || { kill "$chrome_pid" 2>/dev/null; fail 'the viewer (tests/ui-viewer.mjs)'; }
  kill "$chrome_pid" 2>/dev/null || true
else
  echo 'skip  what the page shows: no Chrome here (tests/ui.mjs, tests/ui-viewer.mjs)'
fi

echo 'integration: all checks passed'
