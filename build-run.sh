#!/usr/bin/env bash
# Build the LNO iOS app for the Simulator, install and launch it.
# Usage:
#   ./build-run.sh                 # build + launch on default device
#   LNO_DEVICE="iPhone 16" ./build-run.sh
set -euo pipefail

DEV="${LNO_DEVICE:-iPhone 16 Pro}"
PROJ="$(cd "$(dirname "$0")" && pwd)"
APP="$PROJ/build/Debug-iphonesimulator/LNO.app"
BUNDLE="company.lno.controlcenter"

# Keep the Xcode project in sync with the sources on disk.
python3 "$PROJ/gen_pbxproj.py" >/dev/null

# Real signing (free Apple Development identity, DEVELOPMENT_TEAM in
# gen_pbxproj.py) — required for Keychain to work at all in the Simulator.
# Ad-hoc ("-") signing was tried first: unsigned/ad-hoc builds fail Keychain
# reads/writes with errSecMissingEntitlement (-34018), and adding an explicit
# keychain-access-groups entitlement to an ad-hoc-signed app makes SpringBoard
# refuse to even launch it (no team to validate the group against). A real
# identity resolves both — no App Store Connect / profile fetch needed for
# iphonesimulator SDK builds.
echo "▶︎ Building…"
xcodebuild -project "$PROJ/LNO.xcodeproj" -target LNO \
  -sdk iphonesimulator -configuration Debug \
  SYMROOT="$PROJ/build" build \
  | grep -E "error:|warning: [A-Z]|BUILD (SUCCEEDED|FAILED)" || true

echo "▶︎ Booting $DEV…"
xcrun simctl boot "$DEV" 2>/dev/null || true
xcrun simctl bootstatus "$DEV" >/dev/null 2>&1 || true
open -a Simulator || true

echo "▶︎ Installing…"
xcrun simctl install "$DEV" "$APP"
xcrun simctl terminate "$DEV" "$BUNDLE" 2>/dev/null || true

echo "▶︎ Launching…"
xcrun simctl launch "$DEV" "$BUNDLE" "$@"
