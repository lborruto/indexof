# The page's helper: busybox's web server running the scripts in cgi-bin (free space, search,
# folder sizes, folders as zips, temporary links for VLC, the player's audio and subtitle
# tracks), with zip and ffmpeg (with ffprobe). Reached only by the page's nginx, on an internal
# network; it needs INDEXOF_LINK_SECRET (to sign the links), never the password; it runs as
# nobody (or the user given at run time) and reads the folders under /data.
FROM alpine:3.22@sha256:2e0b81d60597f449baa56dc25d355367869d2dca4cd57e866f1e2b52af3eb55f
# (apk upgrade: the base image's packages brought up to date, fixed CVEs; checked by Trivy in CI.)
RUN apk upgrade --no-cache && apk add --no-cache zip busybox-extras ffmpeg
COPY --chmod=755 cgi-bin/ /www/cgi-bin/
COPY --chmod=755 start.sh /start.sh
RUN chmod 644 /www/cgi-bin/lib.sh # (sourced by the scripts, never run on its own)
USER 65534:65534
EXPOSE 8081
CMD ["/start.sh"]
