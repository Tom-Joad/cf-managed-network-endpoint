FROM nginx:alpine

# openssl: Zertifikatserzeugung + Fingerprint; curl: Healthcheck.
# Nicht darauf verlassen, dass das Basisimage beides mitbringt.
RUN apk add --no-cache openssl curl

COPY nginx.conf /etc/nginx/nginx.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 6443

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -fsk https://127.0.0.1:6443/ || exit 1

ENTRYPOINT ["/entrypoint.sh"]
