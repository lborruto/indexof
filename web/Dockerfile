# The page: nginx (the unprivileged image: runs as any user, listens on 8080, keeps its pid and
# temporary files in /tmp) with its config, the pages and the start script that turns the
# folders mounted under /data into routes. The template is rendered into /tmp at start, with
# the secrets from the environment (INDEXOF_PASSWORD, INDEXOF_LINK_SECRET: it refuses to start
# without them). INDEXOF_VERSION, the version the pages show in their corner: X.Y.Z for a
# release, main for a build of main (both set by release.yml), dev otherwise.
FROM nginxinc/nginx-unprivileged:alpine@sha256:b5047b9b76845eac124358373c6852377c52e4b05834a47647e955dd91cb8f1e
ARG INDEXOF_VERSION=dev
LABEL org.opencontainers.image.version=$INDEXOF_VERSION
ENV NGINX_ENVSUBST_OUTPUT_DIR=/tmp \
    NGINX_ENTRYPOINT_LOCAL_RESOLVERS=true \
    INDEXOF_VERSION=$INDEXOF_VERSION
COPY nginx.conf /etc/nginx/nginx.conf
COPY site.conf.template /etc/nginx/templates/site.conf.template
COPY pages/ /etc/nginx/pages/
COPY --chmod=755 50-indexof-mounts.sh /docker-entrypoint.d/50-indexof-mounts.sh
USER root
# The base image's packages brought up to date (fixed CVEs; checked by Trivy in CI).
RUN apk upgrade --no-cache && mkdir -p /data
USER 101
