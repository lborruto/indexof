#!/bin/sh
# The helper's start: the link secret must be there (32 characters or more; cgi-bin/vlc signs
# the temporary links with it), then busybox's web server on port 8081, serving /www (the
# scripts in /www/cgi-bin).
s=${INDEXOF_LINK_SECRET:-}
[ ${#s} -ge 32 ] || { echo 'indexof-helper: set INDEXOF_LINK_SECRET to 32 characters or more (openssl rand -hex 32), never the password' >&2; exit 1; }
exec httpd -f -p 8081 -h /www
