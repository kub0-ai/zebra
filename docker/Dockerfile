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

ENV ZEBRA_VERSION=${VERSION}
ENV ZEBRA_CACHE_DIR=/var/cache/zebrad
ENV ZEBRA_CONF=/etc/zebrad/zebrad.toml

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
  && TARBALL="zebrad-${ZEBRA_VERSION}-${ARCH}.tar.gz" \
  && curl -sSLfO "https://github.com/ZcashFoundation/zebra/releases/download/v${ZEBRA_VERSION}/${TARBALL}" \
  && echo "${EXPECTED}  ${TARBALL}" > /tmp/expected.sha256 \
  && sha256sum -c /tmp/expected.sha256 \
  && tar -xzf "${TARBALL}" zebrad \
  && install -m 0755 zebrad /usr/local/bin/zebrad \
  && rm -f "${TARBALL}" zebrad /tmp/expected.sha256 \
  && mkdir -p "${ZEBRA_CACHE_DIR}" /etc/zebrad \
  && chown -R ${UID}:${GID} "${ZEBRA_CACHE_DIR}" /etc/zebrad \
  && zebrad --version

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 0755 /usr/local/bin/docker-entrypoint.sh

VOLUME ["/var/cache/zebrad"]

# 8233 mainnet P2P, 8232 JSON-RPC (only bound if the config enables it),
# 9999 Prometheus metrics (likewise).
EXPOSE 8233 8232 9999

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["zebrad", "start"]
