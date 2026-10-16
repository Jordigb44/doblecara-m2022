#!/bin/bash
# Compila la app nativa «Doble Cara M2022» y la instala en ~/Applications
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="${1:-$HOME/Applications/Doble Cara M2022.app}"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/doblecara-build.XXXXXX")"

SWIFTC="$(xcrun --find swiftc 2>/dev/null || true)"
if [ -z "$SWIFTC" ]; then
  echo "✖ No encuentro el compilador de Swift. Instala las herramientas con:  xcode-select --install"
  exit 2
fi
echo "→ Compilando con $SWIFTC"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
"$SWIFTC" -O -swift-version 5 -parse-as-library -sdk "$SDK" \
  -target "$(uname -m)-apple-macos13.0" \
  -framework SwiftUI -framework AppKit -framework PDFKit -framework UniformTypeIdentifiers \
  "$HERE/DobleCara.swift" -o "$BUILD/DobleCara"

echo "→ Creando $APP"
pkill -f "Doble Cara M2022.app/Contents/MacOS" 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/DobleCara" "$APP/Contents/MacOS/"
cp "$HERE/Info.plist" "$APP/Contents/"
if xcrun --sdk macosx swift "$HERE/make_icon.swift" "$BUILD/AppIcon.iconset" >/dev/null 2>&1; then
  iconutil -c icns "$BUILD/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns" || true
fi
codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[ -x "$LSREG" ] && "$LSREG" -f "$APP" || true
rm -rf "$BUILD"
echo "✔ App compilada"
