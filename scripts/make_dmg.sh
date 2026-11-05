#!/bin/bash
# Gera build/<APP_NAME>.dmg a partir de build/<APP_NAME>.app (rode build_app.sh antes).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-Mixer}"
APP="$ROOT/build/$APP_NAME.app"
DMG="$ROOT/build/$APP_NAME.dmg"

[ -d "$APP" ] || { echo "Falta $APP. Rode scripts/build_app.sh primeiro." >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "OK: $DMG"
