## What and why

## How it was checked

- [ ] `sh tests/lint.sh`
- [ ] `sh tests/integration.sh` (Docker, Compose v2, Python 3)
- [ ] pages or player changed: tried in a browser on the demo data (`tests/make-demo.sh`)
- [ ] VLC Link changed: the installer tried on that system

## Checklist

- [ ] No password, key, host name, IP address, user name or real file name in code, tests, docs or screenshots
- [ ] The listing still looks like nginx's "Index of /"; nothing is transcoded
- [ ] No existing check weakened (paths, dotfiles, symbolic links, line breaks, option-like names, numbers, CSP sandbox, internal network); a fix comes with its test
- [ ] `CHANGELOG.md` has a line under `## [Unreleased]` if users will notice the change
