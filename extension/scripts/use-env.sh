#!/usr/bin/env bash
# Selects which backend the extension talks to, mirroring the
# webapp's VITE_API_BASE_URL / mobile's --dart-define=ENV switch: one
# source of truth per environment (config.development.js /
# config.production.js), copied into the fixed path auth.js actually
# imports. A plain copy, because unlike Vite/dart-define there's no
# build step here to swap an import target - background.js is loaded
# by the browser straight from disk.
set -euo pipefail
cd "$(dirname "$0")/.."

ENV="${1:-}"
if [[ "$ENV" != "development" && "$ENV" != "production" ]]; then
  echo "Usage: $0 development|production" >&2
  exit 1
fi

cp "src/background/config.$ENV.js" src/background/config.js
echo "extension/src/background/config.js -> $ENV"
