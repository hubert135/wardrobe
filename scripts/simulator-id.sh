#!/usr/bin/env bash
# Prints the UDID of an available iPhone simulator (prefers a booted one, then the newest iPhone).
# Override with SIMULATOR_ID=<udid>.
set -euo pipefail

if [[ -n "${SIMULATOR_ID:-}" ]]; then
  echo "$SIMULATOR_ID"
  exit 0
fi

command -v xcrun >/dev/null 2>&1 || exit 0

booted=$(xcrun simctl list devices booted available | grep -E "iPhone" | head -1 | grep -oE "[0-9A-F-]{36}" || true)
if [[ -n "$booted" ]]; then
  echo "$booted"
  exit 0
fi

xcrun simctl list devices available | grep -E "^\s+iPhone" | tail -1 | grep -oE "[0-9A-F-]{36}" || true
