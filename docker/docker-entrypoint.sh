#!/bin/bash
set -euo pipefail

# Mirrors the entrypoint shape used by the sibling packaging repos: inject the
# mounted config, fix ownership of the state directory, then drop root via gosu.

ZEBRA_CACHE_DIR="${ZEBRA_CACHE_DIR:-/var/cache/zebrad}"
ZEBRA_CONF="${ZEBRA_CONF:-/etc/zebrad/zebrad.toml}"

# zebrad only reads a config file when told to, so honour a ConfigMap mount by
# adding --config -- unless the caller already passed one.
#
# NOTE: a plain loop, not `printf ... | grep -q --config`. Under `set -o pipefail`
# a `CMD | grep -q PAT` pipeline returns 141 (SIGPIPE) when PAT *matches*, because
# grep exits early and closes the pipe. That inverts the test on exactly the
# inputs it is meant to catch.
if [ -f "${ZEBRA_CONF}" ] && [ "${1:-}" = "zebrad" ]; then
  has_config=0
  for arg in "$@"; do
    [ "${arg}" = "--config" ] && has_config=1
  done
  if [ "${has_config}" -eq 0 ]; then
    shift
    set -- zebrad --config "${ZEBRA_CONF}" "$@"
  fi
fi

if [ "$(id -u)" = "0" ]; then
  # A freshly provisioned PVC arrives owned by root. chown only the top level by
  # default: a recursive chown over a synced Zcash state directory is hundreds of
  # thousands of files and adds minutes to every restart. Set
  # ZEBRA_CHOWN_RECURSIVE=1 once after changing UID/GID, then unset it.
  if [ "${ZEBRA_CHOWN_RECURSIVE:-0}" = "1" ]; then
    echo "entrypoint: recursive chown of ${ZEBRA_CACHE_DIR} (slow, one-off)"
    chown -R zebra:zebra "${ZEBRA_CACHE_DIR}"
  else
    chown zebra:zebra "${ZEBRA_CACHE_DIR}" 2>/dev/null || true
  fi
  set -- gosu zebra "$@"
fi

exec "$@"
