#!/bin/bash
# Instala la Acción rápida de Finder «Imprimir a doble cara» en ~/Library/Services/.
# Tras instalarla, aparece en Finder: clic derecho en un PDF → Acciones rápidas.
# Si no se ve, actívala en Ajustes del Sistema → Teclado → Funciones rápidas → Finder.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="Imprimir a doble cara.workflow"
DEST="$HOME/Library/Services"

if [ ! -f "$SRC/$NAME/Contents/document.wflow" ]; then
  echo "No encuentro $SRC/$NAME" >&2
  exit 1
fi

mkdir -p "$DEST"
rm -rf "$DEST/$NAME"
cp -R "$SRC/$NAME" "$DEST/"

LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[ -x "$LSREG" ] && "$LSREG" -f "$DEST/$NAME" || true

echo "✔ Acción rápida instalada en $DEST/$NAME"
echo "  Finder → clic derecho en un PDF → Acciones rápidas → «Imprimir a doble cara»"
echo "  Requiere el comando ~/.local/bin/doblecara (instálalo con ./install.sh)"
