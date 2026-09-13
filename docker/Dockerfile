FROM debian:bookworm-slim

ARG UID=2001
ARG GID=2001
ARG VERSION
ARG TARGETPLATFORM

# SHA256 of the upstream release tarball for each platform.
#
# These are NOT trusted inputs typed by hand -- .github/workflows/build.yml
# verifies upstream's SHA256SUMS against its Sigstore bundle (cosign verify-blob,
# pinned to the exact Fulcio cert identity in ./TRUST) and passes the resulting
# digests in. Empty means the caller skipped that step, so refuse to build rather
# than fall back to trust-on-first-use against the very artifact under question.
#
# Zebra publishes no PGP signature, so there is deliberately no KEYS file here --
# see ./TRUST for why the trust root is an identity rather than a key.
ARG ZEBRAD_SHA256_AMD64
ARG ZEBRAD_SHA256_ARM64

LABEL org.opencontainers.image.source="https://github.com/kub0-ai/zebra"
LABEL org.opencontainers.image.description="Zebra (zebrad) Zcash full node v${VERSION}"
LABEL org.opencontainers.image.licenses="MIT"

RUN groupadd --gid ${GID} zebra \
  && useradd --create-home --no-log-init -u ${UID} -g ${GID} zebra \
  && apt-get update -y \
  && apt-get install -y --no-install-recommends curl ca-certificates gosu \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 🔴 THESE MUST NOT USE THE `ZEBRA_` PREFIX. IT IS ZEBRAD'S CONFIG NAMESPACE.
#
# zebrad layers environment variables over the TOML file, mapping any variable
# named ZEBRA_<X> onto the top-level config field <x>. That is a documented
# zebrad feature -- ZEBRA_NETWORK and friends are how a user overrides config
# without editing a file -- and it does not distinguish "a config override" from
# "packaging metadata that happens to share the prefix". An unknown field is
# fatal, not ignored:
#
#   ZEBRA_VERSION=6.3.0    -> Configuration error: unknown field `version`
#   ZEBRA_CACHE_DIR=/...   -> Configuration error: unknown field `cache_dir`
#   ZEBRA_FOO=bar          -> Configuration error: unknown field `foo`
#
# So these three variables, set purely as image metadata, made every container
# built from this image exit 1 on startup before reading a single block. The
# image's own labels poisoned its config parse. Verified in-cluster 2026-09-13:
# with all three unset, the identical binary and identical config start cleanly.
#
# ⛔ Do not "fix" a future recurrence by unsetting ZEBRA_* in the entrypoint.
# That would silently break the override mechanism zebrad users are entitled to.
# Ours move out of the namespace; the namespace stays zebrad's.
#
# `zebrad --version` does NOT load config, which is why the build smoke test
# passed for both published tags. The regression gate that does catch it lives
# in .github/workflows/build.yml ("Smoke test") and runs the real entrypoint.
ENV KUB0_ZEBRA_VERSION=${VERSION}
ENV KUB0_ZEBRA_CACHE_DIR=/var/cache/zebrad
ENV KUB0_ZEBRA_CONF=/etc/zebrad/zebrad.toml

RUN set -ex \
  && case "${TARGETPLATFORM}" in \
       linux/amd64) ARCH=x86_64-unknown-linux-gnu;  EXPECTED="${ZEBRAD_SHA256_AMD64}" ;; \
       linux/arm64) ARCH=aarch64-unknown-linux-gnu; EXPECTED="${ZEBRAD_SHA256_ARM64}" ;; \
       *) echo "Unsupported platform: ${TARGETPLATFORM}" && exit 1 ;; \
     esac \
  && if [ -z "$(echo "${EXPECTED}" | tr -d '[:space:]')" ]; then \
       echo "ERROR: no verified SHA256 supplied for ${TARGETPLATFORM}."; \
       echo "       build.yml must cosign-verify upstream SHA256SUMS first;"; \
       echo "       refusing to trust the tarball on first use."; \
       exit 1; \
     fi \
  && TARBALL="zebrad-${KUB0_ZEBRA_VERSION}-${ARCH}.tar.gz" \
  && curl -sSLfO "https://github.com/ZcashFoundation/zebra/releases/download/v${KUB0_ZEBRA_VERSION}/${TARBALL}" \
  && echo "${EXPECTED}  ${TARBALL}" > /tmp/expected.sha256 \
  && sha256sum -c /tmp/expected.sha256 \
  && tar -xzf "${TARBALL}" zebrad \
  && install -m 0755 zebrad /usr/local/bin/zebrad \
  && rm -f "${TARBALL}" zebrad /tmp/expected.sha256 \
  && mkdir -p "${KUB0_ZEBRA_CACHE_DIR}" /etc/zebrad \
  && chown -R ${UID}:${GID} "${KUB0_ZEBRA_CACHE_DIR}" /etc/zebrad \
  && zebrad --version

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 0755 /usr/local/bin/docker-entrypoint.sh

VOLUME ["/var/cache/zebrad"]

# 8233 mainnet P2P, 8232 JSON-RPC (only bound if the config enables it),
# 9999 Prometheus metrics (likewise).
EXPOSE 8233 8232 9999

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["zebrad", "start"]
