#!/bin/sh
set -eu

# Resolve paths relative to this script so it also works when called outside
# the commet/ directory.
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

LIVEKIT_DIR="$PROJECT_DIR/.livekit"

cleanup() {
  rm -rf "$LIVEKIT_DIR"
}
trap cleanup EXIT INT TERM

# Keep Vodozemac-specific build logic isolated from this shared script.
sh "$SCRIPT_DIR/prepare-vodozemac-web.sh"

# Setup the LiveKit web worker.
echo "Preparing LiveKit web worker..."
git clone https://github.com/livekit/client-sdk-flutter.git "$LIVEKIT_DIR"
(
  cd "$LIVEKIT_DIR"
  git checkout ac9d3906eefc8eea91338651b53f4f2d0d2a37cb

  SED="$(command -v gsed || command -v sed)"
  "$SED" -i "s/{'name': 'PBKDF2'.toJS}/{'name': 'HKDF'.toJS}/g" web/e2ee.keyhandler.dart
  "$SED" -i "s/getAlgoOptions('PBKDF2', salt)/getAlgoOptions('HKDF', salt)/g" web/e2ee.keyhandler.dart
  "$SED" -i "s/{'name': 'PBKDF2'}/{'name': 'HKDF'}/g" web/e2ee.utils.dart

  dart compile js web/e2ee.worker.dart -o "$PROJECT_DIR/web/e2ee.worker.dart.js" -m
)

echo "Web preparation complete."
