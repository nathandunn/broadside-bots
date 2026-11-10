#!/usr/bin/env bash
##
## build.sh — run the tests, then do a headless web export into dist/.
## Needs Godot 4.7.2 and its web export templates (on the hub:
## hub-orchestrator/scripts/godot-install.sh).
##
## Built without thread support, so no COOP/COEP headers are needed.
## The big artefacts are committed gzipped only; nginx serves them with
## gzip_static (see nginx.conf).
##
set -euo pipefail
cd "$(dirname "$0")"
GODOT="${GODOT:-godot}"
command -v "$GODOT" >/dev/null || { echo "godot not on PATH" >&2; exit 1; }
echo "engine: $($GODOT --headless --version)"

$GODOT --headless --import >/dev/null 2>&1 || true

echo "tests…"
$GODOT --headless --path . -s tests/run_tests.gd
$GODOT --headless --path . -s tests/ui_smoke.gd

rm -rf dist build
mkdir -p dist
$GODOT --headless --export-release "Web" dist/index.html

echo "verifying the exported pack…"
$GODOT --headless --main-pack dist/index.pck --quit-after 150

for f in dist/index.wasm dist/index.js dist/index.pck; do
  [ -f "$f" ] && gzip -9 -f "$f"
done
du -sh dist
