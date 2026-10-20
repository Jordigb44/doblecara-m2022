#!/bin/bash
# Empaqueta «Doble Cara M2022» para distribuir: app universal (Apple Silicon + Intel),
# firmada ad hoc, en .dmg y .zip dentro de dist/.
#   Uso: app/package.sh [versión]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# La versión por defecto sale del Info.plist (fuente de verdad); se puede
# sobrescribir pasándola como primer argumento: app/package.sh 1.2.0
VERSION="${1:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$HERE/Info.plist" 2>/dev/null)}"
VERSION="${VERSION:-1.0.0}"
NAME="Doble Cara M2022"
BASE="DobleCaraM2022-${VERSION}-macOS"
DIST="$ROOT/dist"
W="$(mktemp -d "${TMPDIR:-/tmp}/doblecara-pkg.XXXXXX")"
trap 'rm -rf "$W"' EXIT

SDK="$(xcrun --sdk macosx --show-sdk-path)"
SWIFTC="$(xcrun --find swiftc)"
echo "→ Versión ${VERSION} · SDK $SDK"

for arch in arm64 x86_64; do
  echo "→ Compilando $arch"
  "$SWIFTC" -O -swift-version 5 -parse-as-library -sdk "$SDK" \
    -target "$arch-apple-macos13.0" \
    -framework SwiftUI -framework AppKit -framework PDFKit -framework UniformTypeIdentifiers -framework UserNotifications -framework AppIntents \
    "$HERE/DobleCara.swift" "$HERE/PagePlan.swift" "$HERE/PrintDuplexIntent.swift" -o "$W/DobleCara-$arch"
done
lipo -create -output "$W/DobleCara" "$W/DobleCara-arm64" "$W/DobleCara-x86_64"
lipo -info "$W/DobleCara"

echo "→ Icono"
xcrun --sdk macosx swift "$HERE/make_icon.swift" "$W/AppIcon.iconset" >/dev/null
iconutil -c icns "$W/AppIcon.iconset" -o "$W/AppIcon.icns"

echo "→ Bundle"
APP="$W/${NAME}.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$W/DobleCara" "$APP/Contents/MacOS/"
cp "$HERE/Info.plist" "$APP/Contents/"
[ -d "$HERE/Resources" ] && cp -R "$HERE/Resources/." "$APP/Contents/Resources/" || true
plutil -replace CFBundleShortVersionString -string "${VERSION}" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "${VERSION}" "$APP/Contents/Info.plist"
cp "$W/AppIcon.icns" "$APP/Contents/Resources/"

# Firma. Con DEVELOPER_ID se firma con Developer ID + hardened runtime (requisito
# para notarizar); sin él se firma ad hoc (por defecto).
if [ -n "${DEVELOPER_ID:-}" ]; then
  codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
else
  codesign --force --deep -s - "$APP"
fi
codesign --verify --deep "$APP"

# Notarización opcional: solo si hay credenciales de Apple. Se notariza un zip
# temporal de la app y, al validarse, se grapa la app ANTES de empaquetar.
# Variables: APPLE_ID, APPLE_TEAM_ID y APPLE_APP_PASSWORD (para guardar el perfil
# en el llavero) o NOTARY_PROFILE (perfil ya guardado con
# `xcrun notarytool store-credentials`).
if [ -n "${NOTARY_PROFILE:-}" ] || { [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ]; }; then
  echo "→ Notarizando"
  PROFILE="${NOTARY_PROFILE:-doblecara-notary}"
  if [ -z "${NOTARY_PROFILE:-}" ]; then
    # La contraseña solo se pasa aquí, una vez, al guardarla en el llavero.
    xcrun notarytool store-credentials "$PROFILE" \
      --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD"
  fi
  NOTARIZE_ZIP="$W/notarize.zip"
  ditto -c -k --keepParent "$APP" "$NOTARIZE_ZIP"
  xcrun notarytool submit "$NOTARIZE_ZIP" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$APP"
fi

rm -rf "$DIST"; mkdir -p "$DIST"

echo "→ ZIP"
ditto -c -k --keepParent "$APP" "$DIST/$BASE.zip"

echo "→ DMG"
STAGE="$W/dmg"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Aplicaciones"
cat > "$STAGE/LÉEME.txt" <<EOF
Doble Cara M2022 ${VERSION}

1. Arrastra «${NAME}» a la carpeta Aplicaciones.
2. La primera vez, macOS dirá que no puede comprobar el desarrollador
   (la app no está notarizada por Apple). Haz clic derecho en la app → Abrir
   → Abrir. O en Ajustes del Sistema → Privacidad y seguridad → «Abrir igualmente».
3. Abre un PDF con clic derecho → Abrir con → ${NAME}, o arrástralo a la app.

https://github.com/Jordigb44/doblecara-m2022
EOF
# hdiutil a veces falla con «Resource busy» en máquinas de CI: se reintenta
for i in 1 2 3; do
  hdiutil create -quiet -volname "${NAME}" -srcfolder "$STAGE" -ov -format UDZO "$DIST/$BASE.dmg" && break
  echo "  hdiutil falló (intento $i), reintentando…"; sleep 5
  [ "$i" = 3 ] && exit 1
done

(cd "$DIST" && shasum -a 256 "$BASE.dmg" "$BASE.zip" > SHA256SUMS.txt)
echo "✔ Listo:"
ls -lh "$DIST"
cat "$DIST/SHA256SUMS.txt"
