#!/bin/sh
set -eu

# Resolve paths relative to this script so it can be called from prepare-web.sh
# or directly from any working directory.
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

VODOZEMAC_TMP="$(mktemp -d "${TMPDIR:-/tmp}/commet-vodozemac.XXXXXX")"
cleanup() {
  rm -rf "$VODOZEMAC_TMP"
}
trap cleanup EXIT INT TERM

echo "Preparing Vodozemac WebAssembly bindings and Matrix push decryption..."

# The Dart probe is compiled against Commet's resolved package dependencies.
if [ ! -f "$PROJECT_DIR/.dart_tool/package_config.json" ]; then
  echo "Dart package configuration is missing. Run 'flutter pub get' before web preparation." >&2
  exit 1
fi

# flutter_rust_bridge_codegen 2.13.0 matches the version used by Commet.
if ! command -v flutter_rust_bridge_codegen >/dev/null 2>&1; then
  cargo install --locked --version 2.13.0 flutter_rust_bridge_codegen
fi

# build-web invokes wasm-pack. Install it when the runner does not provide it.
if ! command -v wasm-pack >/dev/null 2>&1; then
  cargo install --locked wasm-pack
fi

# FRB's web build uses nightly's build-std support on CI.
rustup toolchain install nightly --component rust-src --target wasm32-unknown-unknown

git clone --depth 1 --branch 0.9.0 \
  https://github.com/famedly/dart-vodozemac.git "$VODOZEMAC_TMP/source"

(
  cd "$VODOZEMAC_TMP/source"
  RUSTUP_TOOLCHAIN=nightly flutter_rust_bridge_codegen build-web \
    --dart-root dart \
    --rust-root "$(readlink -f rust)" \
    --release \
    --wasm-pack-rustflags=""
)

PKG_DIR="$VODOZEMAC_TMP/source/dart/web/pkg"
ASSET_DIR="$PROJECT_DIR/assets/vodozemac"
PROBE_DIR="$PROJECT_DIR/web/vodozemac-probe"
WORKER_WASM_DIR="$PROBE_DIR/nonthreaded"

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

# The Service Worker loads the same bindings that Flutter bundles as assets.
cp "$ASSET_DIR/vodozemac_bindings_dart.js" "$WORKER_WASM_DIR/"
cp "$ASSET_DIR/vodozemac_bindings_dart_bg.wasm" "$WORKER_WASM_DIR/"

cat > "$PROBE_DIR/vodozemac_worker_glue.js" <<'EOF'
importScripts("/assets/assets/vodozemac/vodozemac_bindings_dart.js");
EOF

# Compile the Dart decryption probe. Keep generated JavaScript out of source
# control; it is recreated here for every web build.
(
  cd "$PROJECT_DIR"
  dart compile js -O2 tool/matrix_worker_db_probe.dart \
    -o "$PROBE_DIR/matrix_worker_db_probe_deferred.js"
)

# Dart normally runs main() as soon as the script loads. A Service Worker needs
# to invoke it only after the push event and its IndexedDB data are available.
python3 - "$PROBE_DIR/matrix_worker_db_probe_deferred.js" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
original = """v.currentScript=a
var s=A.e0
if(typeof dartMainRunner==="function"){dartMainRunner(s,[])}else{s([])}"""
deferred = """v.currentScript=a
self.__runMatrixWorkerDbProbe=function(){
var s=A.e0
if(typeof dartMainRunner==="function"){dartMainRunner(s,[])}else{s([])}
}"""

if source.count(original) != 1:
    raise SystemExit(
        "Could not find the expected Dart probe entry point exactly once. "
        "The Dart compiler output may have changed."
    )

path.write_text(source.replace(original, deferred, 1))
PY

echo "Vodozemac WASM and Matrix worker probe prepared."
