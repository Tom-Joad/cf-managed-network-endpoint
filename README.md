# cf-managed-network-endpoint

TLS endpoint for **Cloudflare Zero Trust "Managed Networks"**.

The container serves a self-signed TLS certificate on port **6443**. The
Cloudflare WARP client (Cloudflare One client) connects to it and compares the
certificate's SHA-256 fingerprint to detect whether a device is on your home
network. There is no application logic: the HTTP answer (`200`, plain text)
does not matter, only the TLS handshake does.

Built on [linuxserver.io's `baseimage-alpine-nginx`](https://github.com/linuxserver/docker-baseimage-alpine-nginx)
(s6-overlay, non-root `abc` user, docker mods).

## ⚠️ Fingerprint stability (the important part)

Network detection breaks **silently** when the fingerprint changes. Therefore:

- The certificate is **not** baked into the image and **not** regenerated at
  every start.
- On start, an init step looks for `cert.crt` and `cert.key` in `/config/keys`.
  If both exist, they are used. If neither exists, a pair is created **once**
  (RSA 2048, 3650 days, `CN=managed-network.internal`).
- `/config` must be a **persistent volume**. As long as it survives, the
  fingerprint survives restarts, image rebuilds and updates.
- **Never delete the volume.** The next start would create a new certificate
  with a new fingerprint, and Cloudflare would need the new value. Include the
  appdata folder in your backups.
- If only *one* of the two files exists, the container aborts with an error
  instead of silently creating a new pair.

## Parameters

| Parameter | Function |
| --- | --- |
| `-p 6443` | TLS port. With a custom VLAN interface the container listens on its own IP and no port mapping is needed. |
| `-e PUID=1000` | User ID that owns the key pair. |
| `-e PGID=1000` | Group ID that owns the key pair. |
| `-e UMASK=022` | Permissions mask for new files (optional). |
| `-e TZ=Etc/UTC` | Time zone for the log, see the [list of tz names](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones#List) (optional). |
| `-v /config` | Key pair in `keys/` (`cert.crt`, `cert.key`) and nginx config in `nginx/`. **Never delete.** |

The nginx site is `/config/nginx/site-confs/default.conf`; edit it there to
change the answer or the TLS settings.

## Reading the fingerprint

**1. Container log (easiest):** every start prints it prominently. In Unraid:
container icon → *Logs*.

```
==================================================================
 SHA-256 fingerprint of the TLS certificate

   AB:CD:...

 For Cloudflare Zero Trust (managed networks, without colons):

   abcd...
==================================================================
```

**2. In the running container:**

```sh
docker exec cf-managed-network-endpoint \
  openssl x509 -in /config/keys/cert.crt -noout -fingerprint -sha256
```

**3. Over the network:**

```sh
openssl s_client -connect <STATIC-IP>:6443 </dev/null 2>/dev/null \
  | openssl x509 -noout -fingerprint -sha256
```

Cloudflare expects the value **without colons** (the log prints both).

## Deployment on Unraid

Target environment (adapt to your network):

| Parameter | Value |
| --- | --- |
| Network | own VLAN, subnet `<SUBNET>` (e.g. `10.0.0.0/24`) |
| Static IP | `<STATIC-IP>` (outside the DHCP pool) |
| Gateway | `<GATEWAY>` |
| Docker network | custom VLAN interface `br0.<VLAN-ID>` (not bridge) |
| Port | `6443` (TLS) |
| Config | `/mnt/user/appdata/cf-managed-network-endpoint` → `/config` |

**Option A — Unraid template:** copy
[unraid/cf-managed-network-endpoint.xml](unraid/cf-managed-network-endpoint.xml)
to `/boot/config/plugins/dockerMan/templates-user/`, then *Add Container* →
choose the template and set the static IP under "Fixed IP address". Unraid
manages restarts itself; don't add `--restart` to Extra Parameters.

**Option B — docker run:**

```sh
docker run -d \
  --name cf-managed-network-endpoint \
  --network br0.<VLAN-ID> \
  --ip <STATIC-IP> \
  -e PUID=99 -e PGID=100 -e UMASK=002 \
  -v /mnt/user/appdata/cf-managed-network-endpoint:/config \
  --restart unless-stopped \
  ghcr.io/tom-joad/cf-managed-network-endpoint:latest
```

Don't add `--init`: the base image's `/init` (s6-overlay) must be PID 1.

## Upgrading from a version before 1.0.0

Older versions kept the key pair in a `/certs` volume. To keep the fingerprint,
**mount the old folder at `/certs` as well** (read-only is fine) together with
the new `/config` for the first start:

```sh
  -v /mnt/user/appdata/cf-managed-network-endpoint:/config \
  -v /mnt/user/appdata/cf-managed-network-endpoint/certs:/certs:ro \
```

If `/config/keys` is empty, the certificate is copied over once and the log
shows the same fingerprint as before. Compare it with the value in Cloudflare.
Afterwards `/certs` can be removed. The old folder is never modified.

## Configuring Cloudflare Zero Trust

1. Copy the fingerprint from the container log (format without colons).
2. Zero Trust dashboard → **Settings → WARP Client → Network locations →
   Managed networks → Add new managed network**.
3. Type *TLS*, host `<STATIC-IP>`, port `6443`, enter the SHA-256 fingerprint.
4. Use the managed network as a condition in your WARP **device profiles**
   (for example a profile for "home network detected").

The WARP client checks reachability on every network change. To test: bring a
device onto the home network and watch the device profile switch.

## Development

```sh
docker build -t cf-managed-network-endpoint .
tests/smoke.sh cf-managed-network-endpoint   # health, certificate, fingerprint stability
docker run -d --name cfmne-test -p 6443:6443 -v cfmne-config:/config cf-managed-network-endpoint
curl -k https://localhost:6443/              # -> 200 "cf-managed-network-endpoint"
docker logs cfmne-test                       # fingerprint
```

CI ([.github/workflows/build-and-push.yml](.github/workflows/build-and-push.yml))
runs the smoke test and `gitleaks` on every push and pull request. For `v*`
tags it builds a multi-arch image (`linux/amd64`, `linux/arm64`) with SBOM and
provenance, scans it with Trivy, signs it with cosign and pushes it to
`ghcr.io/tom-joad/cf-managed-network-endpoint` (tags: `latest`, `sha-…`,
semver).

See [SECURITY.md](SECURITY.md) to report a vulnerability and
[CHANGELOG.md](CHANGELOG.md) for changes.
