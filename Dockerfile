# linuxserver.io's Alpine 3.24 + nginx base: s6-overlay, PUID/PGID/UMASK/TZ,
# the abc user and docker mods, as in every linuxserver.io container.
# Pinned by digest (a multi-arch index); Dependabot proposes new digests.
FROM ghcr.io/linuxserver/baseimage-alpine-nginx:3.24@sha256:f9380a718d214b10fddfcedf7058c4bbba85ecc1a03c9d98eb4676925d77e7af

# image.source is what makes a GHCR package inherit the repository's
# visibility instead of staying private on its own.
LABEL org.opencontainers.image.source="https://github.com/Tom-Joad/cf-managed-network-endpoint" \
      org.opencontainers.image.title="cf-managed-network-endpoint" \
      org.opencontainers.image.description="TLS endpoint for Cloudflare Zero Trust managed networks: serves a stable self-signed certificate on port 6443" \
      org.opencontainers.image.licenses="MIT"

# openssl: certificate and fingerprint; curl: health check. Don't rely on the
# base image shipping both.
RUN apk add --no-cache openssl curl

# s6 services and the nginx site (see root/).
COPY root/ /
# The base image also starts PHP-FPM and cron; this container needs neither.
RUN chmod +x /etc/s6-overlay/s6-rc.d/init-cfmne-keys/run \
 && rm -f /etc/s6-overlay/s6-rc.d/user/contents.d/svc-php-fpm \
          /etc/s6-overlay/s6-rc.d/user/contents.d/svc-cron

# Stop the container when an init step fails (the default keeps it running).
# The key check relies on it: half a key pair must end in an error, not in a
# container that looks alive and serves nothing.
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2

EXPOSE 6443

# The key pair (/config/keys) and the nginx config (/config/nginx).
# Keep it: a new key pair means a new fingerprint.
VOLUME /config

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsk https://127.0.0.1:6443/ || exit 1

# The entrypoint stays the base image's /init (s6-overlay), which must run as
# PID 1: don't add `--init` to `docker run`.
