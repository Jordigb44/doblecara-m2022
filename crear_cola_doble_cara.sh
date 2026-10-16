#!/bin/bash
# Crea una segunda impresora "Samsung M2022 (doble cara manual)" que usa la misma
# M2022 y el mismo driver de Samsung, pero con la doble cara manual del driver
# activada por defecto. Al imprimir en ella, la impresora hace la cara A, se para
# con el botón parpadeando y, al pulsarlo, imprime la cara B.
#
# Uso:  ./crear_cola_doble_cara.sh [LongEdge|ShortEdge]     (pide tu contraseña)
set -euo pipefail

ORIG="${ORIG:-Samsung_M2020_Series}"
NEW="Samsung_M2022_DobleCara"
EDGE="${1:-LongEdge}"

lpstat -e | grep -qx "$ORIG" || { echo "No existe la cola $ORIG (lpstat -e)"; exit 1; }
URI="$(lpstat -v "$ORIG" | sed 's/^[^:]*: //')"
PPD="/etc/cups/ppd/$ORIG.ppd"
[ -f "$PPD" ] || PPD="/Library/Printers/PPDs/Contents/Resources/Samsung M2020 Series.gz"

echo "Impresora: $URI"
echo "Driver:    $PPD"
sudo lpadmin -p "$NEW" -E -v "$URI" -P "$PPD" \
  -D "Samsung M2022 (doble cara manual)" -L "USB" \
  -o SECManualDuplexOption-default="$EDGE" \
  -o printer-is-shared=false
sudo cupsenable "$NEW"; sudo cupsaccept "$NEW"
echo "✔ Creada «Samsung M2022 (doble cara manual)». Elígela en el diálogo de impresión."
echo "  Para borrarla:  sudo lpadmin -x $NEW"
