#!/bin/sh
# Integration test: builds both images, brings up a throwaway stack (compose project
# indexof-test, published on 127.0.0.1:18099 only) on a small fixture made here, runs every
# check, and takes everything down again (also on failure). Needs docker (with compose v2),
# curl, python3 (to validate zips) and node (the pages' logic). Exits non-zero on the first
# failed check, printing ok/FAIL lines.
#   sh tests/integration.sh
set -u
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh

PORT=${INDEXOF_TEST_PORT:-18099}
BASE="http://127.0.0.1:$PORT"
PASSWORD=Test123pw
SECRET=0123456789abcdef0123456789abcdef
COOKIE="session=$PASSWORD"
PROJECT=indexof-test

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
  rm -rf "$TMP"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

# The fixture: movies (mounted read-only), share and "My Stuff" (writable), plus _search and
# .hidden, which the server must refuse; a dangling symbolic link and a plain file, refused too
# (seen only when the whole fixture is scanned, below).
mkdir -p "$DATA/movies/Sub Folder" "$DATA/share/pat" "$DATA/My Stuff" "$DATA/_search" "$DATA/.hidden" || exit 1
head -c 200000 /dev/urandom >"$DATA/movies/film.mkv"
echo 'a' >"$DATA/movies/Sub Folder/note.txt"
echo 'hidden' >"$DATA/_search/secret.txt"
echo 'hidden' >"$DATA/.hidden/secret.txt"
: >"$DATA/share/pat/*"; : >"$DATA/share/pat/[ab].txt"; : >"$DATA/share/pat/a.txt"; : >"$DATA/share/pat/b.txt"
ln -s /nowhere "$DATA/dangling"
echo 'x' >"$DATA/file.txt"
head -c 30000000 /dev/zero >"$TMP/big.bin"
echo 'hello' >"$TMP/hello.txt"
nl=$(printf '\nx'); nl=${nl%x}

# The stack: the example compose.yaml as it is, with an .env of test values (the secrets, the
# test port, the current user as PUID/PGID so it can write into the fixture, an scp
# destination) and an override for the images built here and the fixture's folders: movies
# mounted read-only, the other folders writable for the page; everything read-only for the helper.
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
for m in movies share 'My Stuff' _search .hidden; do
  ro=; [ "$m" = movies ] && ro=:ro
  web_volumes="$web_volumes      - \"$DATA/$m:/data/$m$ro\"
"
  helper_volumes="$helper_volumes      - \"$DATA/$m:/data/$m:ro\"
"
done
cat >"$TMP/override.yaml" <<EOF
services:
  indexof:
    image: indexof:test
    volumes: !override
$web_volumes  indexof-helper:
    image: indexof-helper:test
    volumes: !override
$helper_volumes
EOF

# The example compose.yaml: it refuses to run without each of the two secrets, and with them
# (nothing else set) it publishes the page on 127.0.0.1:8099 only, as 1000:1000, the helper on
# the internal network alone, without the password, both with log limits.
: >"$TMP/empty.env"
if env -u INDEXOF_PASSWORD -u INDEXOF_LINK_SECRET docker compose --env-file "$TMP/empty.env" -f compose.yaml config >"$BODY" 2>&1; then fail 'compose.yaml ran without the secrets'; fi
if grep -q INDEXOF_PASSWORD "$BODY"; then ok 'compose.yaml refuses to run without INDEXOF_PASSWORD'; else fail "compose.yaml without the secrets: $(cat "$BODY")"; fi
printf 'INDEXOF_PASSWORD=%s\n' "$PASSWORD" >"$TMP/half.env"
if env -u INDEXOF_LINK_SECRET docker compose --env-file "$TMP/half.env" -f compose.yaml config >"$BODY" 2>&1; then fail 'compose.yaml ran without INDEXOF_LINK_SECRET'; fi
if grep -q INDEXOF_LINK_SECRET "$BODY"; then ok 'compose.yaml refuses to run without INDEXOF_LINK_SECRET'; else fail "compose.yaml without the link secret: $(cat "$BODY")"; fi
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
docker build -q -t indexof:test web >/dev/null || fail 'docker build web'
docker build -q -t indexof-helper:test helper >/dev/null || fail 'docker build helper'
ok 'images built'

# The image's own checks, before the stack: the config (rendered with the mounts, none here)
# passes nginx -t, and a missing or short secret stops the start.
if docker run --rm -e INDEXOF_PASSWORD=$PASSWORD -e INDEXOF_LINK_SECRET=$SECRET indexof:test nginx -t >"$BODY" 2>&1; then ok 'nginx -t on the rendered config'; else fail "nginx -t: $(cat "$BODY")"; fi
if docker run --rm -e INDEXOF_LINK_SECRET=$SECRET indexof:test nginx -t >"$BODY" 2>&1; then fail 'started without INDEXOF_PASSWORD'; fi
if grep -q INDEXOF_PASSWORD "$BODY"; then ok 'refuses to start without INDEXOF_PASSWORD'; else fail "no INDEXOF_PASSWORD message in: $(cat "$BODY")"; fi
if docker run --rm -e INDEXOF_PASSWORD=$PASSWORD -e INDEXOF_LINK_SECRET=short indexof:test nginx -t >"$BODY" 2>&1; then fail 'started with a short INDEXOF_LINK_SECRET'; fi
if grep -q INDEXOF_LINK_SECRET "$BODY"; then ok 'refuses to start with a short INDEXOF_LINK_SECRET'; else fail "no INDEXOF_LINK_SECRET message in: $(cat "$BODY")"; fi
if docker run --rm indexof-helper:test >"$BODY" 2>&1; then fail 'helper started without INDEXOF_LINK_SECRET'; fi
if grep -q INDEXOF_LINK_SECRET "$BODY"; then ok 'helper refuses to start without INDEXOF_LINK_SECRET'; else fail "helper: no INDEXOF_LINK_SECRET message in: $(cat "$BODY")"; fi

# INDEXOF_SCP (the scp line's destination) must be user@host or host, INDEXOF_SCP_ROOT (the
# folder on that host holding the mounted folders) an absolute path: anything scp, a shell or
# the settings JSON could read otherwise stops the start, with a line naming the variable.
refused_start() { # VARIABLE VALUE WHAT: the start refuses VARIABLE=VALUE, naming it
  if docker run --rm -e INDEXOF_PASSWORD=$PASSWORD -e INDEXOF_LINK_SECRET=$SECRET -e INDEXOF_SCP=me@nas.example -e "$1=$2" indexof:test nginx -t >"$BODY" 2>&1; then fail "started with $1 $3"; fi
  if grep -q "$1" "$BODY"; then ok "refuses $1 $3"; else fail "$1 $3: no $1 in: $(cat "$BODY")"; fi
}
refused_start INDEXOF_SCP 'me@host x' 'with a space'
refused_start INDEXOF_SCP "me@host'" 'with a quote'
refused_start INDEXOF_SCP 'me@host"' 'with a double quote'
refused_start INDEXOF_SCP 'me@ho\st' 'with a backslash'
refused_start INDEXOF_SCP "$(printf 'me@host\001')" 'with a control character'
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
refused_start INDEXOF_SCP_ROOT "$(printf '/srv\001')" 'with a control character'
refused_start INDEXOF_SCP_ROOT "/srv${nl}x" 'with a line break'
# What the settings say, from the start script alone: the destination as given, null without
# one; the root as given (a trailing slash dropped, / itself empty), /data without one.
expect_settings() { # WANT [docker run options...]
  want=$1; shift
  got=$(docker run --rm -e INDEXOF_PASSWORD=$PASSWORD -e INDEXOF_LINK_SECRET=$SECRET "$@" indexof:test sh -c '/docker-entrypoint.d/50-indexof-mounts.sh >/dev/null 2>&1 && cat /tmp/settings.json')
  if [ "$got" = "$want" ]; then ok "settings (${*:-nothing set}): $got"; else fail "settings (${*:-nothing set}): $got, wanted $want"; fi
}
expect_settings '{"mounts":{},"scp":null,"scp_root":"/data"}'
expect_settings '{"mounts":{},"scp":null,"scp_root":"/data"}' -e INDEXOF_SCP= -e INDEXOF_SCP_ROOT=
expect_settings '{"mounts":{},"scp":"me@nas.example","scp_root":"/data"}' -e INDEXOF_SCP=me@nas.example
expect_settings '{"mounts":{},"scp":"nas","scp_root":"/srv/files"}' -e INDEXOF_SCP=nas -e INDEXOF_SCP_ROOT=/srv/files/
expect_settings '{"mounts":{},"scp":"me.x_y-z@h-1.example","scp_root":""}' -e INDEXOF_SCP=me.x_y-z@h-1.example -e INDEXOF_SCP_ROOT=/
expect_settings '{"mounts":{},"scp":null,"scp_root":"/srv"}' -e INDEXOF_SCP_ROOT=/srv

# Every entry under /data is looked at: a dangling symbolic link and a plain file are refused
# with a line each, never skipped in silence (the whole fixture mounted, read-only).
docker run --rm -e INDEXOF_PASSWORD=$PASSWORD -e INDEXOF_LINK_SECRET=$SECRET -v "$DATA:/data:ro" indexof:test sh -c '/docker-entrypoint.d/50-indexof-mounts.sh' >"$BODY" 2>&1 || fail "start script on the whole fixture: $(cat "$BODY")"
if grep -q 'refused mount /data/dangling: it is a symbolic link' "$BODY"; then ok 'start log: refused mount dangling (a symbolic link to nowhere)'; else fail "no 'refused mount' for the dangling link in: $(cat "$BODY")"; fi
if grep -q 'refused mount /data/file.txt: it is not a folder' "$BODY"; then ok 'start log: refused mount file.txt (not a folder)'; else fail "no 'refused mount' for file.txt in: $(cat "$BODY")"; fi

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

# Login gating.
expect_status -n GET / 302
expect_status -n GET /share/ 302
expect_status -n GET /_settings 403
expect_status -n GET '/_size?p=/movies/' 403
expect_status -n GET /movies/film.mkv 302

# /_settings: the mounts, read-only or writable; the refused ones absent; the scp destination
# and root from the .env (the root's trailing slash dropped).
expect_status GET /_settings 200
expect_body /_settings '"movies":"ro"'
expect_body /_settings '"share":"rw"'
expect_body /_settings '"My Stuff":"rw"'
expect_body /_settings '"scp":"me@nas.example"'
expect_body /_settings '"scp_root":"/srv/files"'
expect_no_body /_settings '_search'
expect_no_body /_settings '.hidden'
expect_header /_settings 'Content-Type: application/json'

# The home page lists the mounted folders, and only them; the refused ones are never served.
expect_body / 'href="movies/"'
expect_body / 'href="share/"'
expect_body / 'href="My%20Stuff/"'
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

# A read-only folder: browse and download only.
expect_status GET /movies 301
expect_header /movies 'Location: /movies/'
expect_body /movies/ 'film.mkv'
expect_body '/movies/Sub%20Folder/' 'note.txt'
expect_status GET /movies/film.mkv 200
expect_header /movies/film.mkv 'Content-Security-Policy: sandbox'
expect_status PUT /movies/x.txt 405 -T "$TMP/hello.txt"
expect_status DELETE /movies/film.mkv 405
expect_status MKCOL /movies/new/ 405
expect_status MOVE /movies/film.mkv 405 -H "Destination: $BASE/movies/x.mkv"
expect_status DELETE /movies/ 405
expect_no_file "$DATA/movies/x.txt" 'read-only folder'
expect_status GET /movies/.uploads/ 403

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
# Moves stay inside writable folders: never into a read-only or a refused one.
expect_status PUT /share/m.txt 201 -T "$TMP/hello.txt"
expect_not_2xx MOVE /share/m.txt -H "Destination: $BASE/movies/m.txt"
expect_not_2xx MOVE /share/m.txt -H "Destination: $BASE/_search/m.txt"
expect_not_2xx MOVE /share/m.txt -H "Destination: $BASE/share/%2e%2e/_search/m.txt"
expect_not_2xx MOVE /share/m.txt -H "Destination: $BASE/share/../_search/m.txt"
expect_not_2xx MOVE /share/m.txt -H "Destination: $BASE/.hidden/m.txt"
expect_not_2xx MOVE /share/m.txt -H "Destination: $BASE/share/"
expect_not_2xx MOVE /share/m.txt -H "Destination: $BASE/m.txt"
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

# The helper, through the page's routes: paths of the page only, inside a mounted folder.
expect_status GET '/_size?p=/movies/' 200
if grep -Eq '^[0-9.]+[KMGT]?$' "$BODY"; then ok "/_size?p=/movies/ -> $(cat "$BODY")"; else fail "/_size?p=/movies/: not a size: $(cat "$BODY")"; fi
expect_empty '/_size?p=/../etc/'
expect_empty '/_size?p=/'
expect_empty '/_size?p=/_search/'
expect_empty '/_size?p=/.hidden/'
expect_empty '/_size?p=/share/.uploads'
expect_body '/_space?p=/share/' ' free / '
expect_body '/_zip?p=/' 'nothing to zip'
expect_body '/_zip?p=/_search/' 'nothing to zip'
expect_body '/_zip?p=/../etc/' 'nothing to zip'
expect_zip '/_zip?p=/movies/' 'movies/' 'movies/film.mkv' 'movies/Sub Folder/' 'movies/Sub Folder/note.txt'
expect_body '/_search?q=film' 'film.mkv'
expect_no_body '/_search?q=secret' 'secret.txt'
expect_no_body '/_search?q=film' 'value="_search"'
expect_no_body '/_search?q=film' 'value=".hidden"'
expect_body '/_search?q=film' 'value="My Stuff"'
# Names are names, never patterns: a file called * and one called [ab].txt are zipped alone.
expect_zip '/_zip?p=/share/pat/%2A' '*'
expect_zip '/_zip?p=/share/pat/%5Bab%5D.txt' '[ab].txt'

# The player's helpers (no real video in this fixture: the path and number checks, then ffprobe's no).
expect_status GET '/_probe?f=/movies/film.mkv' 200
expect_status GET '/_probe?f=/../etc/passwd' 404
expect_status GET '/_probe?f=/_search/secret.txt' 404
expect_status GET '/_probe?f=/movies/film.mkv&k=abc' 400
expect_body '/_sub?f=/movies/film.mkv&s=0' 'no such subtitle track'
expect_status GET '/_sub?f=/movies/film.mkv&s=x' 400
expect_status GET '/_sub?f=/.hidden/secret.txt&s=0' 404
expect_body '/_remux?f=/movies/film.mkv&a=0&t=0' 'no video track'
expect_status GET '/_remux?f=/movies/film.mkv&a=x&t=0' 400
expect_status GET '/_remux?f=/movies/film.mkv&a=0&t=-1' 400

# Temporary links: the file only, reading only.
expect_status GET '/_vlc?f=/movies/film.mkv' 200
link=$(tr -d '\r\n' <"$BODY")
case "$link" in e=*\&k=*) ok "/_vlc -> $link" ;; *) fail "/_vlc: $link" ;; esac
expect_status -n GET "/movies/film.mkv?$link" 200
expect_status -n HEAD "/movies/film.mkv?$link" 200
expect_status -n GET "/movies/Sub%20Folder/note.txt?$link" 302
expect_status -n GET "/movies/film.mkv?e=${link#e=}x" 302
expect_status -n PUT "/share/film.mkv?$link" 302 -T "$TMP/hello.txt"
expect_status GET '/_vlc?f=/_search/secret.txt' 404
expect_status GET '/_vlc?f=/movies/' 404

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
out=$(play_src '/movies/film.mkv')
if [ "$out" = "/movies/film.mkv
$BASE/movies/film.mkv" ]; then ok "player: f=/movies/film.mkv -> src=$BASE/movies/film.mkv"; else fail "player: f=/movies/film.mkv gave: $out"; fi
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

echo 'integration: all checks passed'
