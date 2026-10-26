# Changelog

All notable changes to this project are listed here. Versions follow
[semantic versioning](https://semver.org/). A change that needs action when
upgrading (a changed volume, a renamed setting) only comes with a new major
version.

## [1.0.9] - 2026-10-26

### Security
- Security updates of the distribution packages, picked up by rebuilding the image:
  - `curl` 8.23.0-r0 (CVE-2026-92392)
  - `libcurl` 8.23.0-r0 (CVE-2026-92392)

## [1.0.8] - 2026-10-24

### Changed
- Updated dependencies:
  - linuxserver/baseimage-alpine-nginx from `bd4a0c6` to `69428c2`

## [1.0.7] - 2026-10-22

### Security
- nginx 1.30.6, now in Alpine 3.24. It fixes CVE-2026-97629 (session
  forgery with TLS session tickets), CVE-2026-93479, CVE-2026-95101,
  CVE-2026-97205, CVE-2026-15176 and CVE-2026-90439. 1.0.6 already had
  session tickets off and doesn't use the features the others need; the
  tickets stay off.
- musl 1.2.6-r3 (CVE-2026-107891).

## [1.0.6] - 2026-10-22

### Security
- PHP is no longer in the image. The base image ships PHP 8.5 with PHP-FPM,
  but this container never ran it: the PHP-FPM service was already switched
  off and the site is plain nginx. The PHP security release of 2026-10-21
  (remote code execution) therefore never applied here; removing PHP just
  means no future PHP flaw can either.
- TLS session tickets are off (`ssl_session_tickets off`). nginx 1.30.6
  fixes a session forgery with tickets (CVE-2026-97629), and Alpine 3.24
  still ships 1.30.4. The setting is part of the image, not of `/config`,
  so existing installations get it without changes. The other fixes in
  nginx 1.30.6 concern features this container doesn't use (`alias` with
  `rewrite`, variables, HTTP/3, AIO).

## [1.0.5] - 2026-10-19

### Changed
- The log names the version at start
  (`cf-managed-network-endpoint 1.0.5 starting`).
- The Unraid template and the `docker run` example add
  `--security-opt no-new-privileges`. Existing containers keep working
  without it; add it under Extra Parameters if you like.
- A `docker-compose.yml` is in the repository.

## [1.0.4] - 2026-10-17

### Changed
- The image is built on the current `baseimage-alpine-nginx` 3.24 release,
  with the latest Alpine package updates.

## [1.0.3] - 2026-10-12

### Changed
- The image is built on the current `baseimage-alpine-nginx` 3.24 release,
  with the latest Alpine package updates.

## [1.0.2] - 2026-10-04

### Security
- The image installs Alpine's security fixes at build time instead of
  waiting for a new base image. 1.0.1 shipped `pcre2` 10.48 and
  `apache2-utils` 2.4.68 with eight known high-severity issues; the build
  now gets the fixed versions (10.49 and 2.4.69 or newer).

## [1.0.1] - 2026-10-04

### Changed
- The container log starts with a TomJoad Images banner instead of the
  base image's "custom build" one.

## [1.0.0] - 2026-10-03

### Changed
- **Built on linuxserver.io's `baseimage-alpine-nginx`** (s6-overlay, `abc`
  user, docker mods). nginx no longer runs as root.
- **New volume `/config` replaces `/certs`.** The key pair lives in
  `/config/keys` as `cert.crt` and `cert.key`, owned by `abc`; the nginx
  config is in `/config/nginx` and can be edited.
- `PUID`, `PGID`, `UMASK` and `TZ` are supported. The Unraid template uses
  `99`, `100`, `002`.
- The Unraid template no longer sets `--restart` in Extra Parameters; Unraid
  manages restarts itself.

### Upgrading from 0.x
Keep the certificate, and with it the fingerprint: mount a folder at
`/config` **and** leave your old `/certs` volume mounted for the first start.
The certificate is copied to `/config/keys` once, with the same fingerprint.
Afterwards `/certs` can be removed. Check that the log shows the fingerprint
you have in Cloudflare.

### Added
- Smoke test on every push and pull request: health endpoint, certificate
  and fingerprint stability across a restart, plus `gitleaks`.
- Images with SBOM and provenance, scanned with Trivy, signed with cosign.
- `SECURITY.md`, issue templates, Dependabot for Docker and GitHub Actions.

[1.0.9]: https://github.com/Tom-Joad/cf-managed-network-endpoint/compare/v1.0.8...v1.0.9
[1.0.8]: https://github.com/Tom-Joad/cf-managed-network-endpoint/compare/v1.0.7...v1.0.8
[1.0.7]: https://github.com/Tom-Joad/cf-managed-network-endpoint/compare/v1.0.6...v1.0.7
[1.0.6]: https://github.com/Tom-Joad/cf-managed-network-endpoint/compare/v1.0.5...v1.0.6
[1.0.5]: https://github.com/Tom-Joad/cf-managed-network-endpoint/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/Tom-Joad/cf-managed-network-endpoint/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/Tom-Joad/cf-managed-network-endpoint/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/Tom-Joad/cf-managed-network-endpoint/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/Tom-Joad/cf-managed-network-endpoint/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/Tom-Joad/cf-managed-network-endpoint/releases/tag/v1.0.0
