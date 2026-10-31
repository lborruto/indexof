#!/bin/sh
# The integration test's assertions, sourced by tests/integration.sh (which sets BASE, the test
# stack's address, COOKIE, the login cookie, and BODY, a file for the last response's body).
# Each check prints "ok    ..." or "FAIL  ..." and the first failure ends the run: integration.sh
# tears the stack down on exit, so the cause is the last line printed.

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*" >&2; exit 1; }

# req [-n] METHOD PATH [curl options...]: sends the request (logged in, unless -n) and prints
# the status; the body is left in $BODY.
req() {
  ck=$COOKIE
  if [ "$1" = -n ]; then ck=; shift; fi
  method=$1; path=$2; shift 2
  if [ -n "$ck" ]; then set -- -H "Cookie: $ck" "$@"; fi
  curl -s -o "$BODY" -w '%{http_code}' -X "$method" "$@" "$BASE$path"
}

# expect_status [-n] METHOD PATH CODE [curl options...]: the status must be CODE.
expect_status() {
  nocookie=
  if [ "$1" = -n ]; then nocookie=-n; shift; fi
  method=$1; path=$2; want=$3; shift 3
  got=$(req $nocookie "$method" "$path" "$@")
  if [ "$got" = "$want" ]; then ok "$method $path -> $want${nocookie:+ (no cookie)}"; else fail "$method $path: got $got, wanted $want${nocookie:+ (no cookie)}"; fi
}

# expect_not_2xx METHOD PATH [curl options...]: the request must be refused (no 2xx status).
expect_not_2xx() {
  method=$1; path=$2; shift 2
  got=$(req "$method" "$path" "$@")
  case "$got" in 2*) fail "$method $path: got $got, wanted a refusal" ;; *) ok "$method $path -> $got (refused)" ;; esac
}

# expect_body PATH NEEDLE [curl options...]: a GET (logged in) whose body contains NEEDLE.
expect_body() {
  path=$1; needle=$2; shift 2
  got=$(req GET "$path" "$@")
  if grep -qF -- "$needle" "$BODY"; then ok "GET $path has '$needle'"; else fail "GET $path ($got): no '$needle' in: $(head -c 300 "$BODY")"; fi
}

# expect_no_body PATH NEEDLE [curl options...]: a GET (logged in) whose body does not contain NEEDLE.
expect_no_body() {
  path=$1; needle=$2; shift 2
  req GET "$path" "$@" >/dev/null
  if grep -qF -- "$needle" "$BODY"; then fail "GET $path: has '$needle' (it must not)"; else ok "GET $path has no '$needle'"; fi
}

# expect_empty PATH: a GET (logged in) with an empty body (blank lines aside).
expect_empty() {
  got=$(req GET "$1")
  if [ -z "$(tr -d ' \r\n' <"$BODY")" ]; then ok "GET $1 -> $got, empty"; else fail "GET $1 ($got): not empty: $(head -c 200 "$BODY")"; fi
}

# expect_header [-n] PATH HEADER-LINE [curl options...]: a GET (logged in, unless -n) whose
# headers contain the line.
expect_header() {
  nocookie=
  if [ "$1" = -n ]; then nocookie=-n; shift; fi
  path=$1; needle=$2; shift 2
  if [ -z "$nocookie" ]; then set -- -H "Cookie: $COOKIE" "$@"; fi
  curl -s -o /dev/null -D "$BODY" "$@" "$BASE$path"
  if grep -qiF -- "$needle" "$BODY"; then ok "GET $path has header '$needle'${nocookie:+ (no cookie)}"; else fail "GET $path: no header '$needle' in: $(tr '\r' ' ' <"$BODY")"; fi
}

# search_hrefs PATH: a GET (logged in) of the search page; the link of each result, one a line.
search_hrefs() {
  req GET "$1" >/dev/null
  sed -n '/<pre id="list"/,/<\/pre>/p' "$BODY" | grep -o 'href="[^"]*"' | sed 's/^href="//; s/"$//'
}

# expect_search PATH NEEDLE...: the search's results hold each NEEDLE (part of a result's link).
expect_search() {
  path=$1; shift
  got=$(search_hrefs "$path")
  for needle in "$@"; do
    case "$got" in *"$needle"*) ;; *) fail "GET $path: no result '$needle' in: $(printf '%s' "$got" | head -c 300)" ;; esac
  done
  ok "GET $path has results $*"
}

# expect_no_search PATH NEEDLE...: no result of the search holds any NEEDLE.
expect_no_search() {
  path=$1; shift
  got=$(search_hrefs "$path")
  for needle in "$@"; do
    case "$got" in *"$needle"*) fail "GET $path: result '$needle' (it must not)" ;; esac
  done
  ok "GET $path has no result $*"
}

# expect_search_count PATH N: the search has exactly N results.
expect_search_count() {
  got=$(search_hrefs "$1" | grep -c .)
  if [ "$got" = "$2" ]; then ok "GET $1 -> $2 results"; else fail "GET $1: $got results, wanted $2"; fi
}

# expect_search_inside PATH PREFIX: every result's link starts with PREFIX (a folder of the page,
# as the page encodes it): nothing from outside the mounted folders, whatever the search asked.
expect_search_inside() {
  bad=$(search_hrefs "$1" | awk -v p="$2" 'index($0, p) != 1' | head -3 | tr '\n' ' ')
  if [ -z "$bad" ]; then ok "GET $1: every result under $2"; else fail "GET $1: results outside $2: $bad"; fi
}

# expect_zip [-d DATA] PATH NAME...: a GET (logged in; a POST of DATA, a form, with -d) of a
# valid zip holding exactly those entries (sorted).
expect_zip() {
  data=
  if [ "$1" = -d ]; then data=$2; shift 2; fi
  path=$1; shift
  if [ -n "$data" ]; then got=$(req POST "$path" --data "$data"); else got=$(req GET "$path"); fi
  if python3 -I -c '
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    bad = z.testzip()
    if bad: sys.exit("corrupt entry " + bad)
    names = sorted(z.namelist())
want = sorted(sys.argv[2:])
if names != want: sys.exit("entries " + repr(names) + ", wanted " + repr(want))
' "$BODY" "$@"; then ok "GET $path -> zip of $*"; else fail "GET $path ($got): $(head -c 200 "$BODY" | LC_ALL=C tr -cd '[:print:]')"; fi
}

# expect_dir_empty DIR WHAT: nothing left in DIR (which may be absent).
expect_dir_empty() {
  left=$(find "$1" -mindepth 1 2>/dev/null | tr '\n' ' ')
  if [ -z "$left" ]; then ok "$2: nothing left in $1"; else fail "$2: left in $1: $left"; fi
}

# expect_file / expect_no_file PATH WHAT: the file exists / does not.
expect_file() { if [ -e "$1" ]; then ok "$2: $1 is there"; else fail "$2: $1 is missing"; fi; }
expect_no_file() { if [ ! -e "$1" ]; then ok "$2: no $1"; else fail "$2: $1 exists (it must not)"; fi; }
