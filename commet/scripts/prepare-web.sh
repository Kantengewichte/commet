#!/bin/sh
set -eu

# Resolve paths relative to this script so it also works when called outside
# the commet/ directory.
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

VODOZEMAC_TMP="$(mktemp -d "${TMPDIR:-/tmp}/commet-vodozemac.XXXXXX")"
LIVEKIT_DIR="$PROJECT_DIR/.livekit"

cleanup() {
  rm -rf "$VODOZEMAC_TMP" "$LIVEKIT_DIR"
}
trap cleanup EXIT INT TERM

echo "Preparing Vodozemac WebAssembly bindings..."

# flutter_rust_bridge_codegen 2.13.0 matches the version used by Commet.
if ! command -v flutter_rust_bridge_codegen >/dev/null 2>&1; then
  cargo install --locked --version 2.13.0 flutter_rust_bridge_codegen
fi

# build-web invokes wasm-pack. Install it when the runner does not provide it.
if ! command -v wasm-pack >/dev/null 2>&1; then
  cargo install --locked wasm-pack
fi

rustup target add wasm32-unknown-unknown

git clone --depth 1 --branch 0.9.0 \
  https://github.com/famedly/dart-vodozemac.git "$VODOZEMAC_TMP/source"

(
  cd "$VODOZEMAC_TMP/source"
  flutter_rust_bridge_codegen build-web \
    --dart-root dart \
    --rust-root "$(readlink -f rust)" \
    --release \
    --wasm-pack-rustflags=""
)

PKG_DIR="$VODOZEMAC_TMP/source/dart/web/pkg"
ASSET_DIR="$PROJECT_DIR/assets/vodozemac"
WORKER_WASM_DIR="$PROJECT_DIR/web/vodozemac-probe/nonthreaded"

if [ ! -s "$PKG_DIR/vodozemac_bindings_dart.js" ] ||
   [ ! -s "$PKG_DIR/vodozemac_bindings_dart_bg.wasm" ]; then
  echo "Vodozemac build did not produce the expected JavaScript and WASM files." >&2
  exit 1
fi

mkdir -p "$ASSET_DIR" "$WORKER_WASM_DIR"
rm -f "$ASSET_DIR"/vodozemac_bindings_dart*
cp "$PKG_DIR"/vodozemac_bindings_dart* "$ASSET_DIR/"

# Make the wasm-bindgen initializer available to a classic Service Worker.
# Keep this patch idempotent so rerunning the preparation script is safe.
python3 - "$ASSET_DIR/vodozemac_bindings_dart.js" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
marker = "self.__vodozemacWasmBindgen = wasm_bindgen;"
if marker not in source:
    source += """

// Expose the generated initializer to classic Service Workers.
if (typeof self.window === 'undefined') {
    self.window = self;
}
self.__vodozemacWasmBindgen = wasm_bindgen;
self.wasm_bindgen = wasm_bindgen;
"""
    path.write_text(source)
PY

# The standalone worker proof loads its WASM from this public web path.
cp "$ASSET_DIR/vodozemac_bindings_dart.js" "$WORKER_WASM_DIR/"
cp "$ASSET_DIR/vodozemac_bindings_dart_bg.wasm" "$WORKER_WASM_DIR/"

# A small loader keeps the Service Worker independent of Flutter's asset URL
# rewriting while loading the same generated bindings used by the app.
cat > "$PROJECT_DIR/web/vodozemac-probe/vodozemac_worker_glue.js" <<'EOF'
importScripts("/assets/assets/vodozemac/vodozemac_bindings_dart.js");
EOF

echo "Vodozemac bindings prepared in assets/vodozemac and web/vodozemac-probe."

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
