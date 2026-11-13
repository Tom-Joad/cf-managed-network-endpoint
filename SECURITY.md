# Security policy

## Supported versions

Only the latest release receives fixes. Security fixes go into a new
release of the current major version.

## Reporting a vulnerability

Please do **not** open a public issue for security problems. Report them
privately through GitHub instead: on the
[Security tab](https://github.com/Tom-Joad/cf-managed-network-endpoint/security),
choose **Report a vulnerability**. You will get an answer within a few days.

## Scope notes

The container holds a TLS private key. Of particular interest:

- the private key ending up in logs or the image (the fingerprint of the
  certificate is public information and is logged on purpose)
- a way to make the container replace or overwrite the key pair, which
  would silently change the fingerprint
- the key being readable by other users on the host

The container runs nginx as a non-root user and serves one static answer on
port 6443. It has no application logic and no other listening ports. The
image also declares ports 80 and 443, inherited from the base image (`EXPOSE`
can't be removed in a child image); nothing listens there.

## Supply chain

Images are built by GitHub Actions from version tags only. Third-party
actions are pinned to commit SHAs. The repository is scanned with
`gitleaks`, and the container is smoke-tested on every push. Images are
scanned with Trivy and signed keylessly with cosign. To verify an image:

```bash
cosign verify ghcr.io/tom-joad/cf-managed-network-endpoint:latest \
  --certificate-identity-regexp 'https://github.com/Tom-Joad/cf-managed-network-endpoint/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```
