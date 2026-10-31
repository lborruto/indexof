# Security policy

## Reporting a vulnerability

Please report privately through GitHub: **Security › Report a vulnerability**
(https://github.com/lborruto/indexof/security/advisories/new). Do not open a public issue.
Include the version (the image tag), what an attacker needs (network position, the password, a
signed link) and the steps. indexof is maintained in spare time: reports are handled on a
best-effort basis, with no guaranteed response time.

## Supported versions

The latest release only: `ghcr.io/lborruto/indexof:latest` and the matching
`indexof-helper`. Fixes land on `main` and in the next release; older tags are not patched.

## Security model

Read this before installing. indexof is a plain file server for a home network; it is exactly
as safe as the network it sits on.

- **One shared password.** There are no accounts. Everyone uses the same password
  (`INDEXOF_PASSWORD`), and anyone who has it can do everything the server allows: read every
  mounted folder, and upload, rename and delete in the writable ones. Logging in sets a cookie
  for 30 days that holds the password's value itself, readable by page scripts (it is not
  `HttpOnly`): a script injected into the pages, or anyone who can read the browser's
  cookies, has the password. Use a long random one (`openssl rand -hex 32`) and change it when in
  doubt: there is no rate limiting on the login.
- **Plain HTTP.** indexof encrypts nothing: the password, the cookie and every file travel in
  clear. **Never expose it to the internet**: no port forwarding, no public host name. Reach it
  from the home network or through a VPN (Tailscale, WireGuard…). The example compose file
  publishes it on `127.0.0.1` only; `INDEXOF_BIND` opens it to a LAN address, on purpose. A
  reverse proxy you control can add TLS in front of it.
- **Files are served sandboxed.** Every file comes with `Content-Security-Policy: sandbox` and
  `X-Content-Type-Options: nosniff`, so an uploaded HTML or SVG file cannot run scripts against
  the pages. Dotfiles (`.something`) are never served, symbolic links are not followed and are
  left out of zips, and every path the helper receives must resolve to a real path under a
  mounted folder, without line breaks.
- **Signed VLC links.** "Open in VLC", the `.m3u` playlist and "copy VLC link" carry a link
  signed with `INDEXOF_LINK_SECRET` (its own key, 32 characters or more, never the password). A
  link is valid for one file, read-only (GET and HEAD), for 12 hours. Anyone holding one can
  download that file until it expires, without the password, so share a link as you would the
  file.
- **Read-only mounts are browse-only.** A folder mounted with `:ro` can be listed, searched,
  zipped, played and downloaded, never changed: nginx refuses the write methods on it, and the
  kernel refuses writes to the mount anyway. A mounted folder itself is never renamed, moved or
  deleted, whatever its mode. Mount `:ro` everything that should only be looked at.
- **The helper is not published.** `indexof-helper` (sizes, search, zips, subtitles, remuxing)
  listens on an internal Docker network only; it is reached through nginx, behind the login, and
  never from the outside. Only the web service has a published port.
- **Containers run as you.** Both services run as `PUID`/`PGID` (1000 by default): uploads
  belong to that user and the helper reads with that user's rights. nginx is the unprivileged
  image (no root, port 8080 inside). The containers refuse to start without the two secrets.

### What it does not protect against

- Someone with the password: they can do everything. There is no per-user permission and no
  audit log.
- A compromised machine on your network or VPN: it sees the traffic (plain HTTP) and can use the
  password or a cookie it captures.
- Password guessing from the network: there is no rate limit, so the password must be long and
  random.
- A signed link that was shared or captured: it works for that file until it expires.
- Whatever is inside the files: indexof serves them sandboxed, it does not scan them.

## In scope

The nginx configuration and the pages, the start script that turns mounts into routes, the
helper's CGI scripts (every parameter they take), the signed links, the two images, the example
compose file and the GitHub workflows.

## Out of scope

- Deployments exposed to the internet, against this document's advice.
- Attacks that need a shell on the host, access to the mounted folders, the password or a valid
  cookie.
- Denial of service by request volume from the network.
- VLC itself, opened by the VLC Link helpers: report to VideoLAN.
- Vulnerabilities in nginx, ffmpeg or zip with no indexof-specific way to reach them: report
  them upstream; the images are rebuilt from their current base at every release.
