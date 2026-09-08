#!/usr/bin/env bash
# Builds a submission-ready zip for the Firefox/Chrome store listing:
# points config.js at the production backend (via use-env.sh) and
# strips host_permissions' localhost:8000 entry, which only exists for
# local dev and would otherwise sit in a public listing requesting
# access to every installer's own localhost - meaningless for anyone
# but the developer, and the kind of thing that draws reviewer
# scrutiny for no reason.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/use-env.sh production

VERSION=$(python3 -c "import json; print(json.load(open('manifest.json'))['version'])")
DIST_DIR="dist"
STAGE_DIR="$DIST_DIR/stage"
ZIP_PATH="$DIST_DIR/lwkapply-quick-capture-$VERSION.zip"

rm -rf "$STAGE_DIR" "$ZIP_PATH"
mkdir -p "$STAGE_DIR"

cp -R manifest.json src icons "$STAGE_DIR/"
# Dev-only files that ship alongside the real ones but aren't
# referenced by anything at runtime - only config.js (already pointed
# at production above) is actually imported.
rm -f "$STAGE_DIR/src/background/config.example.js" \
      "$STAGE_DIR/src/background/config.development.js" \
      "$STAGE_DIR/src/background/config.production.js" \
      "$STAGE_DIR/icons/generate.py"

python3 - "$STAGE_DIR/manifest.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path) as f:
    manifest = json.load(f)

manifest["host_permissions"] = [
    origin
    for origin in manifest["host_permissions"]
    if not origin.startswith("http://localhost")
]

with open(path, "w") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")
PY

echo "host_permissions in the package:"
python3 -c "import json; print(json.load(open('$STAGE_DIR/manifest.json'))['host_permissions'])"

(cd "$STAGE_DIR" && zip -qr "../../$ZIP_PATH" .)
rm -rf "$STAGE_DIR"

echo "Built $ZIP_PATH"
