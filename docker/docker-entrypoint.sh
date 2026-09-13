#!/bin/bash
set -euo pipefail

# Mirrors the entrypoint shape used by the sibling packaging repos: inject the
# mounted config, fix ownership of the state directory, then drop root via gosu.

# ─────────────────────────────────────────────────────────────────────────────
# 🔴 NOTHING THIS SCRIPT READS OR SETS MAY BE NAMED `ZEBRA_*`.
#
# zebrad layers env vars over its TOML config, mapping ZEBRA_<X> onto the
# top-level config field <x>, and an unknown field is FATAL -- the process exits
# 1 before opening the database. Verified in-cluster 2026-09-13:
#
#   ZEBRA_VERSION=6.3.0          -> Configuration error: unknown field `version`
#   ZEBRA_CACHE_DIR=/var/...     -> Configuration error: unknown field `cache_dir`
#   ZEBRA_FOO=bar                -> Configuration error: unknown field `foo`
#   (all three unset)            -> starts cleanly, same binary, same config
#
# That applies to variables this script merely *reads* as much as to ones the
# Dockerfile sets: the entrypoint does not consume them, it `exec`s zebrad with
# the environment intact. So ZEBRA_CHOWN_RECURSIVE=1 -- which earlier revisions
# of this file documented as the supported way to re-own a volume -- would have
# killed the node with `unknown field chown_recursive`. Every knob here is
# KUB0_-prefixed for that reason.
#
# ⛔ Do not "fix" a recurrence by unsetting ZEBRA_* before the exec. ZEBRA_NETWORK
# and friends are a documented zebrad feature and users are entitled to them.
# Our variables leave the namespace; the namespace stays zebrad's.
# ─────────────────────────────────────────────────────────────────────────────
CACHE_DIR="${KUB0_ZEBRA_CACHE_DIR:-/var/cache/zebrad}"
CONF_PATH="${KUB0_ZEBRA_CONF:-/etc/zebrad/zebrad.toml}"

# zebrad only reads a config file when told to, so honour a ConfigMap mount by
# adding --config -- unless the caller already passed one.
#
# NOTE: a plain loop, not `printf ... | grep -q --config`. Under `set -o pipefail`
# a `CMD | grep -q PAT` pipeline returns 141 (SIGPIPE) when PAT *matches*, because
# grep exits early and closes the pipe. That inverts the test on exactly the
# inputs it is meant to catch.
if [ -f "${CONF_PATH}" ] && [ "${1:-}" = "zebrad" ]; then
  has_config=0
  for arg in "$@"; do
    [ "${arg}" = "--config" ] && has_config=1
  done
  if [ "${has_config}" -eq 0 ]; then
    shift
    set -- zebrad --config "${CONF_PATH}" "$@"
  fi
fi

if [ "$(id -u)" = "0" ]; then
  # A freshly provisioned PVC arrives owned by root. chown only the top level by
  # default: a recursive chown over a synced Zcash state directory is hundreds of
  # thousands of files and adds minutes to every restart. Set
  # KUB0_ZEBRA_CHOWN_RECURSIVE=1 once after changing UID/GID, then unset it.
  if [ "${KUB0_ZEBRA_CHOWN_RECURSIVE:-0}" = "1" ]; then
    echo "entrypoint: recursive chown of ${CACHE_DIR} (slow, one-off)"
    chown -R zebra:zebra "${CACHE_DIR}"
  else
    chown zebra:zebra "${CACHE_DIR}" 2>/dev/null || true
  fi
  set -- gosu zebra "$@"
fi

exec "$@"
