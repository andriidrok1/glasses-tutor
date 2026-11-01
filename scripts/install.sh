#!/usr/bin/env bash
# Sign an IPA with a free Apple ID and install it on the iPhone plugged in over USB.
# Usage: scripts/install.sh [devmode|registered] [release-tag]
#   devmode    (default) MetaAppID empty, works with Developer Mode on the glasses
#   registered IDs from the Wearables Developer Center baked in
# Needs: plumesign (from https://github.com/claration/impactor/releases), usbmuxd running.
# First time: `plumesign account login -u you@example.com` (asks password + 2FA code).
#
# plumesign's --udid flag does not match connected devices (v2.7.2), so the device is picked
# through its interactive menu: the script runs it under a pseudo-terminal and sends Enter,
# which selects the first (and normally only) connected iPhone.
set -euo pipefail

PLUMESIGN="${PLUMESIGN:-$HOME/Applications/impactor/plumesign-linux-x86_64}"
REPO="andriidrok1/glasses-tutor"
VARIANT="${1:-devmode}"
TAG="${2:-latest}"
WORK="$(mktemp -d)"

echo "→ downloading GlassesTutor-$VARIANT.ipa ($TAG) from $REPO"
gh release download "$TAG" -R "$REPO" -p "GlassesTutor-$VARIANT.ipa" -D "$WORK" --clobber

echo "→ signing with Apple ID and installing on the first connected iPhone"
export RUST_LOG="${RUST_LOG:-info}"
script -qec "$PLUMESIGN sign -p $WORK/GlassesTutor-$VARIANT.ipa --apple-id --register-and-install -o $WORK/GlassesTutor-$VARIANT-signed.ipa" /dev/null <<< $'\n\n\n' \
  | sed 's/\x1b\[[0-9;]*m//g; s/\x1b\[?25[lh]//g' | grep -E "INFO|WARN|ERROR|Error|Select" || true

test -f "$WORK/GlassesTutor-$VARIANT-signed.ipa" && echo "signed IPA: $WORK/GlassesTutor-$VARIANT-signed.ipa"
echo "done. Profile from a free Apple ID lasts 7 days; rerun this script to refresh."
