#!/usr/bin/env bash
# Usage: run-simulator.sh <udid> <path/to/Wardrobe.app> <bundle id> [launch args...]
set -euo pipefail

SIM_ID="$1"; APP_PATH="$2"; BUNDLE_ID="$3"; shift 3

if [[ -z "$SIM_ID" ]]; then
  echo "No iPhone simulator found. Install one in Xcode > Settings > Platforms." >&2
  exit 1
fi

xcrun simctl boot "$SIM_ID" 2>/dev/null || true
open -a Simulator --args -CurrentDeviceUDID "$SIM_ID"
xcrun simctl install "$SIM_ID" "$APP_PATH"
xcrun simctl launch "$SIM_ID" "$BUNDLE_ID" "$@"
echo "Launched $BUNDLE_ID on $SIM_ID"
