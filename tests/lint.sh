#!/bin/sh
# Lint: every shell script through ShellCheck (as sh: the CGI scripts run under busybox) and
# the shell's own parser, each page's <script> parsed by node, and the Windows VLC Link script
# parsed by pwsh when it is installed. Exits 0 when every check passes.
#   sh tests/lint.sh
set -u
cd "$(dirname "$0")/.." || exit 1
status=0
fail() { echo "FAIL  $*" >&2; status=1; }

# The shell scripts: the helper's CGI scripts, the image's start scripts, the tests, the Mac
# installer. Only the ones that exist (a folder may not have any yet).
set --
for f in helper/cgi-bin/* web/*.sh tests/*.sh vlc-link/mac/install.sh; do
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

[ "$status" -eq 0 ] && echo 'lint: all checks passed' || echo 'lint: some checks failed' >&2
exit "$status"
