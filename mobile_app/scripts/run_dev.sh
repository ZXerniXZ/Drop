#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
DEFINES="${1:-dart_defines.json}"
if [[ ! -f "$DEFINES" ]]; then
  echo "Missing $DEFINES — copy from dart_defines.example.json"
  exit 1
fi
exec flutter run --dart-define-from-file="$DEFINES" "${@:2}"
