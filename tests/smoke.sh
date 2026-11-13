#!/usr/bin/env bash
# Smoke test: start the image, check the health endpoint and the certificate,
# and that the fingerprint survives a restart, a recreate and the takeover of
# a pre-1.0 /certs volume. Usage: tests/smoke.sh <image>
set -euo pipefail

IMAGE=${1:?usage: smoke.sh <image>}
# Files in the mounted /config belong to PUID/PGID. Use the caller's IDs so the
# test can edit and clean them up; root can't be PUID (abc must not be root).
PUID=$(id -u); PGID=$(id -g)
[[ $PUID != 0 ]] || { PUID=1000; PGID=1000; }
WORK=$(mktemp -d)
NAME=cfmne-smoke-$$
# A start that fails early leaves root-owned files in /config: remove them
# through a container (the runner's user can't).
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true
      docker run --rm --entrypoint sh -v "$WORK:/w" "$IMAGE" -c "rm -rf /w/*" >/dev/null 2>&1 || true
      rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $*" >&2; docker logs "$NAME" >&2 || true; exit 1; }

# Docker picks a free host port; PORT is read back after the start.
start() { # extra docker args
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    docker run -d --name "$NAME" -p 127.0.0.1::6443 \
        -e PUID="$PUID" -e PGID="$PGID" "$@" "$IMAGE" >/dev/null \
        || fail "docker run failed"
    read_port
    wait_healthy
}

# A restart gives the container a new random host port.
read_port() {
    PORT=$(docker port "$NAME" 6443/tcp | sed -n '1s/.*://p')
    [[ -n $PORT ]] || fail "no host port for 6443"
}

# Prints the served fingerprint; on failure it prints nothing and returns 0, so
# the callers' comparisons fail through fail() (with the container log) and
# not through set -e before fail() runs.
# It retries for a few seconds: after `docker restart` the health status still
# says "healthy" from before until the first new check.
served_fp() {
    local fp
    for _ in $(seq 1 15); do
        fp=$(openssl s_client -connect "127.0.0.1:$PORT" </dev/null 2>/dev/null \
            | openssl x509 -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2) || true
        [[ -z $fp ]] || break
        sleep 1
    done
    echo "$fp"
}

# Waits until the container is healthy; fails on timeout.
wait_healthy() {
    for _ in $(seq 1 60); do
        [[ $(docker inspect -f '{{.State.Health.Status}}' "$NAME") == healthy ]] && return 0
        sleep 2
    done
    fail "container did not become healthy"
}

# Waits until the container has stopped (the start is expected to fail).
wait_exited() {
    for _ in $(seq 1 60); do
        [[ $(docker inspect -f '{{.State.Status}}' "$NAME") == running ]] || return 0
        sleep 2
    done
}

logged_fp() {
    docker logs "$NAME" 2>&1 | grep -E '^   ([0-9A-F]{2}:){31}[0-9A-F]{2}$' | tail -n1 | tr -d ' ' || true
}

in_log() { local out; out=$(docker logs "$NAME" 2>&1); grep -qE -- "$1" <<<"$out"; }

mkdir -p "$WORK/config"

echo "== first start: certificate is created"
start -v "$WORK/config:/config"
FP=$(served_fp)
[[ -n $FP ]] || fail "no certificate served"
BANNER=$(docker logs "$NAME" 2>&1)
grep -q 'BASED ON IMAGES FROM LINUXSERVER\.IO' <<<"$BANNER" || fail "the start banner is not ours"
grep -qE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8}\] cf-managed-network-endpoint [^ ]+ starting$' <<<"$BANNER" || fail "no start line with the version"
if grep -q 'Based on images from linuxserver\.io' <<<"$BANNER"; then fail "the base image's banner is still shown"; fi
[[ $(logged_fp) == "$FP" ]] || fail "fingerprint in the log differs from the served one"
[[ $(curl -fsk "https://127.0.0.1:$PORT/") == cf-managed-network-endpoint ]] || fail "unexpected answer"
[[ $(stat -c %u "$WORK/config/keys/cert.key") == "$PUID" ]] || fail "key not owned by PUID"
[[ $(stat -c %a "$WORK/config/keys/cert.key") == 600 ]] || fail "key is not mode 600"
WORKERS=$(docker exec "$NAME" ps -eo user,args | awk '/nginx: worker/ {print $1}')
[[ -n $WORKERS ]] || fail "no nginx worker found"
[[ $WORKERS != *root* ]] || fail "nginx worker runs as root"
# Only 6443 listens: the base image's default site must be gone. Probe inside
# the container: 443 on the host says nothing about the image.
if docker exec "$NAME" curl -sk --max-time 3 https://127.0.0.1:443/ >/dev/null 2>&1; then fail "443 answers"; fi
# nginx logs errors to the container log, not to files in /config that nothing
# rotates; the access log (only the health check's requests) is dropped. This is
# set in nginx.conf: links to /dev/null made the base image's lsiown hand
# /dev/null to abc.
docker exec "$NAME" grep -qE '^\s*error_log\s+stderr;' /config/nginx/nginx.conf || fail "nginx.conf does not log errors to stderr"
docker exec "$NAME" grep -qE '^\s*access_log\s+off;' /config/nginx/nginx.conf || fail "nginx.conf still has an access log"
[[ -z $(docker exec "$NAME" find /config/log/nginx -type l) ]] || fail "links in /config/log/nginx"
[[ $(docker exec "$NAME" stat -c '%U %a' /dev/null) == "root 666" ]] || fail "/dev/null ownership or mode changed"
# Only 6443 listens (the image declares 80/443 as inherited EXPOSE metadata).
if docker exec "$NAME" curl -sk --max-time 3 https://127.0.0.1:80/ >/dev/null 2>&1; then fail "80 answers"; fi
# No PHP leftovers from the base image's init step.
[[ -z $(docker exec "$NAME" find /config/php -type f 2>/dev/null) ]] || fail "PHP files were created in /config/php"
# The init messages carry timestamps and the certificate's end date is logged.
in_log '^\[[0-9-]{10} [0-9:]{8}\] The certificate is valid until ' || fail "no expiry line"
if in_log '^\.+[+*]*$'; then fail "openssl progress dots in the log"; fi
if in_log 'WARNING:'; then fail "unexpected warning in the log of a fresh start"; fi
if in_log '"GET / HTTP/[0-9.]+" 200'; then fail "the health check's requests are in the container log"; fi

echo "== health check: ok now, fails when the served certificate no longer matches the files"
docker exec "$NAME" /usr/local/bin/cfmne-healthcheck || fail "health check fails on a healthy container"
docker exec "$NAME" cp /config/keys/cert.crt /tmp/cert.orig
docker exec "$NAME" sh -c 'openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=other -keyout /dev/null -out /config/keys/cert.crt 2>/dev/null'
if docker exec "$NAME" /usr/local/bin/cfmne-healthcheck 2>/dev/null; then fail "health check ignores a certificate that differs from the one served"; fi
docker exec "$NAME" cp /tmp/cert.orig /config/keys/cert.crt
docker exec "$NAME" /usr/local/bin/cfmne-healthcheck || fail "health check fails after restoring the certificate"
echo "== restart keeps the fingerprint"
docker restart "$NAME" >/dev/null
read_port
wait_healthy
[[ $(served_fp) == "$FP" ]] || fail "fingerprint changed after a restart"

echo "== recreate with the same /config keeps the fingerprint"
start -v "$WORK/config:/config"
[[ $(served_fp) == "$FP" ]] || fail "fingerprint changed after a recreate"

echo "== only one of the two files: the container must not create a new pair"
docker rm -f "$NAME" >/dev/null
rm "$WORK/config/keys/cert.crt"
docker run -d --name "$NAME" -e PUID="$PUID" -e PGID="$PGID" -v "$WORK/config:/config" "$IMAGE" >/dev/null \
    || fail "docker run failed"
wait_exited
[[ $(docker inspect -f '{{.State.Status}}' "$NAME") != running ]] || fail "started with half a key pair"
# Read the log first: with pipefail, `docker logs | grep -q` fails at random
# when grep exits on the first match and docker logs gets SIGPIPE.
LOG=$(docker logs "$NAME" 2>&1)
grep -q 'holds only one of' <<<"$LOG" || fail "no error about the missing file"
[[ ! -f $WORK/config/keys/cert.crt ]] || fail "a new certificate was created"

echo "== key pair can't be created: the key step must stop with its own error"
docker rm -f "$NAME" >/dev/null
mkdir -p "$WORK/config3" "$WORK/emptykeys"
docker run -d --name "$NAME" -e PUID="$PUID" -e PGID="$PGID" \
    -v "$WORK/config3:/config" -v "$WORK/emptykeys:/config/keys:ro" "$IMAGE" >/dev/null \
    || fail "docker run failed"
wait_exited
[[ $(docker inspect -f '{{.State.Status}}' "$NAME") != running ]] || fail "started without a key pair"
in_log 'ERROR: could not create the key pair in /config/keys' || fail "no error from the key step"
if in_log 'SHA-256 fingerprint of the TLS certificate'; then fail "a fingerprint was printed without a key pair"; fi

echo "== takeover of a pre-1.0 /certs volume"
mkdir -p "$WORK/old" "$WORK/config2"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj /CN=managed-network.internal \
    -keyout "$WORK/old/key.pem" -out "$WORK/old/cert.pem" 2>/dev/null
OLD_FP=$(openssl x509 -in "$WORK/old/cert.pem" -noout -fingerprint -sha256 | cut -d= -f2)
start -v "$WORK/config2:/config" -v "$WORK/old:/certs:ro"
[[ $(served_fp) == "$OLD_FP" ]] || fail "fingerprint changed when taking over /certs"

[[ $(stat -c %u "$WORK/config2/keys/cert.key") == "$PUID" ]] || fail "key not owned by PUID after the takeover"
[[ $(stat -c %a "$WORK/config2/keys/cert.key") == 600 ]] || fail "key is not mode 600 after the takeover"
[[ $(stat -c %a "$WORK/config2/keys/cert.crt") == 644 ]] || fail "certificate is not mode 644 after the takeover"
[[ -z $(find "$WORK/config2/keys" -name '.cfmne-new.*') ]] || fail "temporary key files left behind"
# IPv6: the [::] listener answers when the host has IPv6 (otherwise it is removed).
if docker exec "$NAME" test -s /proc/net/if_inet6; then
    docker exec "$NAME" curl -fsk "https://[::1]:6443/" >/dev/null || fail "no answer on [::1]:6443"
fi

echo "== a different pair in /certs while /config/keys has one: warning with both fingerprints, no change"
mkdir -p "$WORK/other"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj /CN=other \
    -keyout "$WORK/other/key.pem" -out "$WORK/other/cert.pem" 2>/dev/null
OTHER_FP=$(openssl x509 -in "$WORK/other/cert.pem" -noout -fingerprint -sha256 | cut -d= -f2)
start -v "$WORK/config2:/config" -v "$WORK/other:/certs:ro"
[[ $(served_fp) == "$OLD_FP" ]] || fail "the certificate in /config/keys was replaced"
in_log 'WARNING: /certs holds a different certificate' || fail "no warning about the ignored /certs"
in_log "ignored .*$OTHER_FP" || fail "the warning lacks the fingerprint of /certs"
in_log "in use .*$OLD_FP" || fail "the warning lacks the fingerprint in use"

echo "== only one of the two files in /certs: the container must not create a new pair"
docker rm -f "$NAME" >/dev/null
mkdir -p "$WORK/config4" "$WORK/halfold"
cp "$WORK/old/cert.pem" "$WORK/halfold/cert.pem"
docker run -d --name "$NAME" -e PUID="$PUID" -e PGID="$PGID" -v "$WORK/config4:/config" -v "$WORK/halfold:/certs:ro" "$IMAGE" >/dev/null \
    || fail "docker run failed"
wait_exited
[[ $(docker inspect -f '{{.State.Status}}' "$NAME") != running ]] || fail "started with half a key pair in /certs"
in_log '/certs holds only one of' || fail "no error about the half pair in /certs"
[[ ! -e $WORK/config4/keys/cert.key ]] || fail "a key was created"

echo "== a start aborted between the two moves is finished on the next start"
docker rm -f "$NAME" >/dev/null
mkdir -p "$WORK/config5/keys" "$WORK/config5/log/nginx"
# Links as 1.0.13 left them: they are removed, and nginx.conf takes over.
ln -s /dev/null "$WORK/config5/log/nginx/access.log"
ln -s /dev/stderr "$WORK/config5/log/nginx/error.log"
cp "$WORK/old/key.pem" "$WORK/config5/keys/cert.key"
cp "$WORK/old/cert.pem" "$WORK/config5/keys/.cfmne-new.crt"
start -v "$WORK/config5:/config"
[[ $(served_fp) == "$OLD_FP" ]] || fail "the interrupted takeover was not finished"
in_log 'Finishing an interrupted start' || fail "no message about the interrupted start"
[[ -z $(find "$WORK/config5/log/nginx" -type l) ]] || fail "the links of 1.0.13 were not removed"
[[ $(docker exec "$NAME" stat -c '%U %a' /dev/null) == "root 666" ]] || fail "/dev/null ownership or mode changed after an upgrade"

echo "OK"
