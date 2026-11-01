#!/usr/bin/env bash
# Sign an IPA with a free Apple ID and install it on the iPhone plugged in over USB.
# Usage: scripts/install.sh [devmode|registered] [release-tag]
#   devmode    (default) MetaAppID empty, works with Developer Mode on the glasses
#   registered IDs from the Wearables Developer Center baked in
# Needs: plumesign (from https://github.com/claration/impactor/releases), usbmuxd running.
# First time: `plumesign account login -u you@example.com` (asks password + 2FA code).
set -euo pipefail

PLUMESIGN="${PLUMESIGN:-$HOME/Applications/impactor/plumesign-linux-x86_64}"
REPO="andriidrok1/glasses-tutor"
VARIANT="${1:-devmode}"
TAG="${2:-latest}"
WORK="$(mktemp -d)"

echo "→ downloading IPA ($TAG) from $REPO"
gh release download "$TAG" -R "$REPO" -p "GlassesTutor-$VARIANT.ipa" -D "$WORK" --clobber

echo "→ signing with Apple ID and installing (plumesign will ask for the device if needed)"
"$PLUMESIGN" sign -p "$WORK/GlassesTutor-$VARIANT.ipa" --apple-id --register-and-install -o "$WORK/GlassesTutor-$VARIANT-signed.ipa"

echo "done. Profile from a free Apple ID lasts 7 days; rerun this script to refresh."
