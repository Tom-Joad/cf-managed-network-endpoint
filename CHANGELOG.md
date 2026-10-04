# Changelog

All notable changes to this project are listed here. Versions follow
[semantic versioning](https://semver.org/). A change that needs action when
upgrading (a changed volume, a renamed setting) only comes with a new major
version.

## [Unreleased]

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

[1.0.0]: https://github.com/Tom-Joad/cf-managed-network-endpoint/releases/tag/v1.0.0
