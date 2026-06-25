#!/usr/bin/env bash
# Avvia l'app in debug per confrontare gli stili del tasto record in locale.
set -euo pipefail
cd "$(dirname "$0")/.."
DEFINES="${1:-dart_defines.json}"
if [[ ! -f "$DEFINES" ]]; then
  echo "Missing $DEFINES — copy from dart_defines.example.json"
  exit 1
fi

DEVICE="${DROP_DEVICE:-}"
EXTRA=()
if [[ -n "$DEVICE" ]]; then
  EXTRA+=(-d "$DEVICE")
fi

echo "→ Avvio in debug. In app: Impostazioni → Sviluppo → Anteprima tasto record"
echo "→ Oppure tieni premuto il tasto record nella tab File."
echo ""
echo "Solo anteprima orb (Chrome/web):"
echo "  flutter run -t lib/preview_main.dart -d chrome --dart-define-from-file=$DEFINES"
exec flutter run --dart-define-from-file="$DEFINES" "${EXTRA[@]}" "${@:2}"
