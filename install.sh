#!/bin/bash
# Instala DobleCaraM2022 para el usuario actual (no necesita contraseña de administrador)
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/Library/Application Support/DobleCaraM2022"
PDFSERV="$HOME/Library/PDF Services"
SERVICE_NAME="Doble cara manual (Samsung M2022)"
APP="$HOME/Applications/Doble Cara M2022.app"

# Cierra intentos anteriores que se hayan quedado colgados
pkill -f "DobleCaraM2022/bin/doblecara.sh" 2>/dev/null || true
mkdir -p "$HOME/Library/Logs"

echo "→ Copiando archivos a: ${DEST}"
mkdir -p "${DEST}/bin" "${DEST}/lib"
cp "$SRC/bin/doblecara.sh" "$SRC/bin/lanzar.sh" "${DEST}/bin/"
cp "$SRC/lib/pdf_tool.js" "${DEST}/lib/"
# Tus ajustes personales van en ~/.config/doblecara-m2022.conf (no se sobrescribe)
cp "$SRC/config.sh" "${DEST}/"
chmod +x "${DEST}/bin/doblecara.sh" "${DEST}/bin/lanzar.sh"

echo "→ Creando la app «Doble Cara M2022» en: ${APP}"
mkdir -p "$HOME/Applications"
if ! "$SRC/app/build.sh" "${APP}"; then
  echo "  (no se pudo compilar la app nativa: creo una versión sencilla con ventanas)"
  rm -rf "${APP}"
  osacompile -o "${APP}" <<EOF
on run
	set f to choose file with prompt "Elige el PDF que quieres imprimir a doble cara:" of type {"com.adobe.pdf"}
	imprimir(f)
end run

on open theFiles
	repeat with f in theFiles
		imprimir(f)
	end repeat
end open

on imprimir(f)
	do shell script quoted form of "${DEST}/bin/lanzar.sh" & " " & quoted form of (POSIX path of f)
end imprimir
EOF
fi

# El servicio antiguo (script) bloqueaba Vista Previa en macOS 27: se quita
rm -rf "${PDFSERV:?}/${SERVICE_NAME}" "${PDFSERV:?}/${SERVICE_NAME}.app"
# En su lugar, el menú PDF abre la app directamente (se puede quitar en Preferencias)
mkdir -p "$PDFSERV"
ln -sfn "${APP}" "$PDFSERV/Doble cara manual (M2022)"

echo "→ Enlazando el comando 'doblecara' en ~/.local/bin"
mkdir -p "$HOME/.local/bin"
ln -sf "${DEST}/bin/doblecara.sh" "$HOME/.local/bin/doblecara"

echo
echo "Impresoras detectadas:"
lpstat -e 2>/dev/null | sed 's/^/   • /' || true
echo
echo "✔ Instalado."
echo "  • Finder: clic derecho en un PDF > Abrir con > Doble Cara M2022"
echo "  • O arrastra un PDF a la ventana de la app o a su icono del Dock"
echo "  • Al imprimir: menú PDF > Doble cara manual (M2022)"
echo "  • Terminal: ~/.local/bin/doblecara archivo.pdf"
echo
echo "Primera vez: en la app, «Cargar hoja de prueba» y luego «Imprimir cara A» para comprobar la orientación"
echo "Configuración:  ${DEST}/config.sh"
