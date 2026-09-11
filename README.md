# zebra

Multi-arch [Zebra](https://github.com/ZcashFoundation/zebra) (`zebrad`) Zcash full-node image.

`ghcr.io/kub0-ai/zebra` — `linux/amd64` + `linux/arm64`.

## Why this exists

`zcashd` reached end of support. Unmodified `zcashd` 6.20.0 halts past block height
**3417100** (reached 2026-07-18) and will not run on current mainnet, so
[`kub0-ai/zcash`](https://github.com/kub0-ai/zcash) is a deliberate tombstone that fails
closed rather than publishing a node that cannot sync. Zebra is upstream's replacement
consensus client, and this repo packages it.

Wallet functionality is **not** covered here. `zcashd`'s embedded wallet is replaced by
[Zallet](https://github.com/zcash/zallet), which is still beta.

## Trust model — an identity, not a key

The sibling packaging repos (`bitcoin-core`, `monero`, `dogecoin-core`) pin PGP fingerprints
in a `KEYS` file and require a `GOODSIG` at build time. **That pattern does not apply here.**
Zebra publishes no PGP signature.

Instead each release carries `SHA256SUMS` plus `SHA256SUMS.sigstore.json` — a Sigstore
bundle. The trust anchor is a short-lived Fulcio certificate bound to the exact GitHub
Actions workflow that produced the release, countersigned into the Rekor transparency log.
So what gets pinned is *who signed*, not *which key*:

```
oidc_issuer = https://token.actions.githubusercontent.com
identity    = .../ZcashFoundation/zebra/.github/workflows/zfnd-release-binaries.yml@refs/tags/v${VERSION}
```

That lives in [`TRUST`](./TRUST) and is pinned to the **exact tag**, not a regexp over tags —
a signature for any other release is therefore unusable here.

### Where verification happens

In CI, not in the `Dockerfile`. `cosign` needs its own trust root, so verifying it inside the
image would only move the chicken-and-egg problem down a layer. `build.yml` runs
`cosign verify-blob` against the pinned identity, extracts the per-platform digests from the
now-trusted `SHA256SUMS`, and passes them as build args. The `Dockerfile` **refuses to build**
if those args are empty, rather than trusting the tarball on first use.

```
release assets ──► cosign verify-blob (identity-pinned) ──► SHA256SUMS trusted
                                                               │
                                        build-arg digests ◄────┘
                                                               │
                          Dockerfile: sha256sum -c, else fail ─┘
```

## Layout

```
VERSION                     — upstream zebrad version; single source of truth
TRUST                       — pinned Sigstore issuer + identity template
docker/Dockerfile           — multi-arch, verified-digest install of zebrad
docker/docker-entrypoint.sh — injects --config, chowns state, drops root via gosu
```

## Release automation

`watch-release.yml` checks upstream daily and preflights the *same* Sigstore gate the build
applies. If the pinned identity already covers the new release, the version bump is
auto-merged and the build dispatched — no human in the loop, because a human would add
latency and no security. If the identity does not match, the PR is held **and the run goes
red**, because a changed release-signing identity is exactly the case worth a person's
attention.

Note that the auto-merge explicitly dispatches `build.yml` rather than relying on its `push`
trigger: events raised by the default `GITHUB_TOKEN` do not create workflow runs, so an
auto-merged bump would otherwise land on `main` and never build. `workflow_dispatch` is a
documented exception to that rule.

## Running

Zebra has **no SOCKS5/proxy support** — `zebra-network`'s config exposes no proxy field — so
unlike the `zcashd` packaging it cannot be placed behind a Tor sidecar. A node needs direct
egress or it will not sync at all.

State lives in `/var/cache/zebrad` (override with `ZEBRA_CACHE_DIR`). A config mounted at
`/etc/zebrad/zebrad.toml` is picked up automatically.

```bash
docker run --rm -v zebra-state:/var/cache/zebrad ghcr.io/kub0-ai/zebra:latest
```
