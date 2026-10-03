#!/usr/bin/env bash
# Smoke test: start the image, check the health endpoint and the certificate,
# and that the fingerprint survives a restart, a recreate and the takeover of
# a pre-1.0 /certs volume. Usage: tests/smoke.sh <image>
set -euo pipefail

IMAGE=${1:?usage: smoke.sh <image>}
WORK=$(mktemp -d)
NAME=cfmne-smoke-$$
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $*" >&2; docker logs "$NAME" >&2 || true; exit 1; }

start() { # extra docker args
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    docker run -d --name "$NAME" -p 127.0.0.1:6443:6443 \
        -e PUID=1000 -e PGID=1000 "$@" "$IMAGE" >/dev/null
    for _ in $(seq 1 60); do
        [[ $(docker inspect -f '{{.State.Health.Status}}' "$NAME") == healthy ]] && return 0
        sleep 2
    done
    fail "container did not become healthy"
}

served_fp() {
    openssl s_client -connect 127.0.0.1:6443 </dev/null 2>/dev/null \
        | openssl x509 -noout -fingerprint -sha256 | cut -d= -f2
}

logged_fp() {
    docker logs "$NAME" 2>&1 | grep -E '^   ([0-9A-F]{2}:){31}[0-9A-F]{2}$' | tail -n1 | tr -d ' '
}

mkdir -p "$WORK/config"

echo "== first start: certificate is created"
start -v "$WORK/config:/config"
FP=$(served_fp)
[[ -n $FP ]] || fail "no certificate served"
[[ $(logged_fp) == "$FP" ]] || fail "fingerprint in the log differs from the served one"
[[ $(curl -fsk https://127.0.0.1:6443/) == cf-managed-network-endpoint ]] || fail "unexpected answer"
[[ $(stat -c %u "$WORK/config/keys/cert.key") == 1000 ]] || fail "key not owned by PUID"
[[ $(stat -c %a "$WORK/config/keys/cert.key") == 600 ]] || fail "key is not mode 600"
WORKERS=$(docker exec "$NAME" ps -eo user,args | awk '/nginx: worker/ {print $1}')
[[ -n $WORKERS ]] || fail "no nginx worker found"
[[ $WORKERS != *root* ]] || fail "nginx worker runs as root"
# Only 6443 listens: the base image's default site must be gone.
if curl -sk --max-time 3 https://127.0.0.1:443/ >/dev/null 2>&1; then fail "443 answers"; fi

echo "== restart keeps the fingerprint"
docker restart "$NAME" >/dev/null
for _ in $(seq 1 60); do
    [[ $(docker inspect -f '{{.State.Health.Status}}' "$NAME") == healthy ]] && break
    sleep 2
done
[[ $(served_fp) == "$FP" ]] || fail "fingerprint changed after a restart"

echo "== recreate with the same /config keeps the fingerprint"
start -v "$WORK/config:/config"
[[ $(served_fp) == "$FP" ]] || fail "fingerprint changed after a recreate"

echo "== only one of the two files: the container must not create a new pair"
docker rm -f "$NAME" >/dev/null
rm "$WORK/config/keys/cert.crt"
docker run -d --name "$NAME" -e PUID=1000 -e PGID=1000 -v "$WORK/config:/config" "$IMAGE" >/dev/null
for _ in $(seq 1 60); do
    [[ $(docker inspect -f '{{.State.Status}}' "$NAME") == running ]] || break
    sleep 2
done
[[ $(docker inspect -f '{{.State.Status}}' "$NAME") != running ]] || fail "started with half a key pair"
docker logs "$NAME" 2>&1 | grep -q 'holds only one of' || fail "no error about the missing file"
[[ ! -f $WORK/config/keys/cert.crt ]] || fail "a new certificate was created"

echo "== takeover of a pre-1.0 /certs volume"
mkdir -p "$WORK/old" "$WORK/config2"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj /CN=managed-network.internal \
    -keyout "$WORK/old/key.pem" -out "$WORK/old/cert.pem" 2>/dev/null
OLD_FP=$(openssl x509 -in "$WORK/old/cert.pem" -noout -fingerprint -sha256 | cut -d= -f2)
start -v "$WORK/config2:/config" -v "$WORK/old:/certs:ro"
[[ $(served_fp) == "$OLD_FP" ]] || fail "fingerprint changed when taking over /certs"

echo "OK"
