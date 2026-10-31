#!/bin/sh
# Lint: every shell script through ShellCheck (as sh: the CGI scripts run under busybox) and
# the shell's own parser, each page's <script> parsed by node, and the Windows VLC Link script
# parsed by pwsh when it is installed. Exits 0 when every check passes.
#   sh tests/lint.sh
set -u
cd "$(dirname "$0")/.." || exit 1
status=0
fail() { echo "FAIL  $*" >&2; status=1; }

# The shell scripts: the helper's CGI scripts (and their lib.sh), the images' start scripts,
# the tests, the Mac installer. Only the ones that exist (a folder may not have any yet).
set --
for f in helper/cgi-bin/* helper/*.sh web/*.sh tests/*.sh vlc-link/mac/install.sh; do
  [ -f "$f" ] && set -- "$@" "$f"
done
[ $# -gt 0 ] || fail 'no shell scripts found'
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -s sh "$@"; then echo "ok    shellcheck ($# scripts)"; else fail 'shellcheck'; fi
else
  fail 'shellcheck is not installed'
fi
for f in "$@"; do
  if sh -n "$f"; then echo "ok    sh -n $f"; else fail "sh -n $f"; fi
done

# The pages: each <script> parsed as a function body (a syntax error fails it).
if command -v node >/dev/null 2>&1; then
  for f in web/pages/*.html; do
    [ -f "$f" ] || continue
    if node -e '
      const html = require("fs").readFileSync(process.argv[1], "utf8");
      const re = /<script\b[^>]*>([\s\S]*?)<\/script>/gi;
      let m, n = 0;
      while ((m = re.exec(html))) { new Function(m[1]); n++; }
      if (!n) { console.error("no <script> in " + process.argv[1]); process.exit(1); }
    ' "$f"; then echo "ok    node  $f"; else fail "node parse $f"; fi
  done
else
  fail 'node is not installed'
fi

# The Windows VLC Link script: parsed by PowerShell (not run) when pwsh is there.
ps1=vlc-link/windows/install-vlc-link.ps1
if command -v pwsh >/dev/null 2>&1; then
  # shellcheck disable=SC2016 # PowerShell's $variables, not the shell's
  if INDEXOF_PS1="$ps1" pwsh -NoProfile -NonInteractive -Command '
    $tokens = $null; $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $env:INDEXOF_PS1).Path, [ref]$tokens, [ref]$errors) | Out-Null
    foreach ($e in $errors) { Write-Host ("{0}:{1}: {2}" -f $env:INDEXOF_PS1, $e.Extent.StartLineNumber, $e.Message) }
    if ($errors) { exit 1 }
  '; then echo "ok    pwsh  $ps1"; else fail "pwsh parse $ps1"; fi
else
  echo "skip  pwsh  $ps1 (pwsh is not installed)"
fi

# The owner's values are settings now: none of these may be fixed in the code (web/, helper/,
# vlc-link/). The docs and the compose example (./data/share) are not code.
fixed='debian-server|192\.168\.0\.15|tail38eefe|lucab|files\.lan|192\.168\.1\.10|example-tailnet|/data/media|/data/share'
if grep -rnE "$fixed" web helper vlc-link; then fail 'fixed hosts, users or folders in the code (above): make them settings'; else echo 'ok    no fixed hosts, users or folders in web/, helper/, vlc-link/'; fi

# The example compose.yaml and .env.example agree: every variable the one interpolates is in
# the other, with the two secrets, the address and the scp line's settings, and the hint for
# the link secret.
# shellcheck disable=SC2016 # (compose's ${VAR}, not the shell's)
for v in $(grep -o '\${[A-Z_]*' compose.yaml | tr -d '${' | sort -u) INDEXOF_PASSWORD INDEXOF_LINK_SECRET INDEXOF_BIND INDEXOF_PORT PUID PGID INDEXOF_SCP INDEXOF_SCP_ROOT; do
  if grep -q "^$v=" .env.example 2>/dev/null; then echo "ok    .env.example has $v"; else fail ".env.example: no $v= line"; fi
done
if grep -q 'openssl rand -hex 32' .env.example 2>/dev/null; then echo 'ok    .env.example says how to make the link secret'; else fail '.env.example: no openssl rand -hex 32 hint'; fi

# The VLC Link installers take the page's addresses (host:port) and refuse anything else before
# they touch the computer. They are run for their refusals only, with HOME and PATH pointing at
# an empty folder, so that an older or broken installer could do nothing either.
tmp=$(mktemp -d "${TMPDIR:-/tmp}/indexof-lint.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
sandbox=$tmp/empty; mkdir -p "$sandbox"
mac=vlc-link/mac/install.sh
out=$(HOME=$sandbox PATH=$sandbox /bin/sh "$mac" 2>&1)
case "$out" in *usage*) echo "ok    $mac: usage without arguments" ;; *) fail "$mac without arguments: $out" ;; esac
for bad in 'files.example' 'files.example:' ':8099' 'files.example:8099;rm -rf x' 'files.example:abc' 'a"b:1' 'files.example:8099/' 'http://files.example:8099' 'files.example:70000' 'a:1:2' 'a b:1' '-a:1' '.a:1' 'files.example:0'; do
  if HOME=$sandbox PATH=$sandbox /bin/sh "$mac" "$bad" >"$tmp/out" 2>&1; then fail "$mac took '$bad'"; fi
  if grep -q 'not an origin' "$tmp/out"; then echo "ok    $mac refuses '$bad'"; else fail "$mac '$bad': $(cat "$tmp/out")"; fi
done
HOME=$sandbox PATH=$sandbox /bin/sh "$mac" files.example:8099 10.0.0.5:8099 >"$tmp/out" 2>&1 || true
if grep -q 'not an origin' "$tmp/out"; then fail "$mac refused good origins: $(cat "$tmp/out")"; else echo "ok    $mac takes files.example:8099 10.0.0.5:8099"; fi

# The Windows installer the same way, then the handler it writes (open.ps1) against links: it
# opens the page's own (host:port given, a folder, a percent-encoded path) and nothing else. A
# fake VLC and LOCALAPPDATA under the temporary folder; the registry step fails here (no
# HKCU on this system), which is why this runs everywhere but on Windows.
if command -v pwsh >/dev/null 2>&1; then
  case "$(uname -s)" in *NT*|MINGW*|MSYS*|CYGWIN*) echo "skip  $ps1 run (it would register the handler on this Windows)" ;; *)
  if pwsh -NoProfile -NonInteractive -File "$ps1" >"$tmp/out" 2>&1; then fail "$ps1 ran without -Allowed"; fi
  if grep -q 'Allowed' "$tmp/out"; then echo "ok    $ps1 needs -Allowed"; else fail "$ps1 without -Allowed: $(cat "$tmp/out")"; fi
  for bad in 'files.example' ':8099' 'files.example:8099;x' 'files.example:abc' 'a b:1' 'files.example:8099/' 'http://files.example:8099' 'a:1:2' '.a:1' 'a"b:1'; do # (-a:1: PowerShell itself refuses it as a parameter)
    if pwsh -NoProfile -NonInteractive -File "$ps1" -Allowed "$bad" >"$tmp/out" 2>&1; then fail "$ps1 took '$bad'"; fi
    if grep -qi 'not an origin' "$tmp/out"; then echo "ok    $ps1 refuses '$bad'"; else fail "$ps1 '$bad': $(cat "$tmp/out")"; fi
  done
  mkdir -p "$tmp/pf/VideoLAN/VLC" "$tmp/appdata"; : >"$tmp/pf/VideoLAN/VLC/vlc.exe"
  ProgramFiles=$tmp/pf LOCALAPPDATA=$tmp/appdata pwsh -NoProfile -NonInteractive -File "$ps1" -Allowed 'files.example:8099,10.0.0.5:8099' >"$tmp/out" 2>&1 || true
  open=$tmp/appdata/vlc-link/open.ps1
  if [ -f "$open" ]; then echo "ok    $ps1 wrote open.ps1"; else fail "$ps1 wrote no open.ps1: $(cat "$tmp/out")"; fi
  if grep -qF 'files\.example:8099|10\.0\.0\.5:8099' "$open"; then echo "ok    open.ps1 holds the origins, regex-escaped"; else fail "open.ps1 pattern: $(grep -n 'ok = ' "$open")"; fi
  for good in 'vlc://files.example:8099/movies/film.mkv?e=1761900000&k=abcDEF-_12' 'vlc://10.0.0.5:8099/My%20Stuff/Am%C3%A9lie%20%282001%29/a.mkv?e=1&k=a' 'vlc://FILES.example:8099/movies/a.mp3?e=1&k=a'; do
    if ProgramFiles='' pwsh -NoProfile -NonInteractive -File "$open" "$good" >"$tmp/out" 2>&1; then echo "ok    open.ps1 opens $good"; else fail "open.ps1 refused $good: $(cat "$tmp/out")"; fi
  done
  for bad in 'vlc://evil.example:8099/movies/a.mkv?e=1&k=a' 'vlc://filesXexample:8099/movies/a.mkv?e=1&k=a' 'vlc://files.example:80990/movies/a.mkv?e=1&k=a' 'vlc://files.example:8099/a.mkv?e=1&k=a' 'vlc://files.example:8099//a.mkv' 'vlc://files.example:8099/movies/a b.mkv' 'vlc://files.example:8099/movies/a.mkv"' "vlc://files.example:8099/movies/a'.mkv" 'http://files.example:8099/movies/a.mkv' 'vlc://files.example:8099/movies/' 'vlc://files.example:8099/mo?vies/a.mkv' 'vlc://files.example:8099.evil/movies/a.mkv'; do
    if ProgramFiles='' pwsh -NoProfile -NonInteractive -File "$open" "$bad" >"$tmp/out" 2>&1; then fail "open.ps1 opened $bad"; else echo "ok    open.ps1 refuses $bad"; fi
  done
  ;; esac
fi

[ "$status" -eq 0 ] && echo 'lint: all checks passed' || echo 'lint: some checks failed' >&2
exit "$status"
