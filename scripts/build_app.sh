#!/bin/bash
# Gera build/<APP_NAME>.app (release) com assinatura ad-hoc, ou com SIGN_IDENTITY se definida.
# Uso: scripts/build_app.sh
# Variáveis: APP_NAME (Mixer), BUNDLE_ID (com.glarruda.mixer), VERSION (1.0), SIGN_IDENTITY (- = ad-hoc)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-Mixer}"
BUNDLE_ID="${BUNDLE_ID:-com.glarruda.mixer}"
VERSION="${VERSION:-1.0}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
EXECUTABLE="Mixer"   # nome do produto no Package.swift
APP="$ROOT/build/$APP_NAME.app"

# Valida os valores que entram no sed/Info.plist (evita quebrar com | & < > " etc.).
validate() {
  if [[ ! "$2" =~ ^[A-Za-z0-9._\ -]+$ ]]; then
    echo "ERRO: $1 inválido ('$2'). Use só letras, números, espaço, ponto, hífen e sublinhado." >&2
    exit 1
  fi
}
validate APP_NAME "$APP_NAME"
validate BUNDLE_ID "$BUNDLE_ID"
validate VERSION "$VERSION"

cd "$ROOT"
swift build -c release --product "$EXECUTABLE"
BIN="$(swift build -c release --product "$EXECUTABLE" --show-bin-path)/$EXECUTABLE"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$EXECUTABLE"
cp Resources/*.icns Resources/*.png "$APP/Contents/Resources/"
sed -e "s|@EXECUTABLE@|$EXECUTABLE|g" -e "s|@BUNDLE_ID@|$BUNDLE_ID|g" \
    -e "s|@APP_NAME@|$APP_NAME|g" -e "s|@VERSION@|$VERSION|g" \
    Resources/Info.plist.template > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# --identifier fixa o requisito de assinatura no bundle ID (ajuda a permissão a sobreviver a rebuilds).
codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP"
codesign --verify --verbose=1 "$APP"
echo "OK: $APP"
