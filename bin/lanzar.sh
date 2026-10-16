#!/bin/bash
# Lo llama la app «Doble Cara M2022» (y por tanto el menú PDF del diálogo de
# impresión). Copia el PDF enseguida y lanza la impresión en segundo plano, para
# que la app (y Vista Previa) queden libres al instante.
DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$HOME/Library/Logs/DobleCaraM2022.log"
echo "$(date '+%F %T') lanzar: $1" >> "$LOG"
D="$(mktemp -d "${TMPDIR:-/tmp}/doblecara.XXXXXX")"
F="$D/$(basename "$1")"
cp "$1" "$F" >> "$LOG" 2>&1 || exit 0
nohup "$DIR/doblecara.sh" --gui "$F" >> "$LOG" 2>&1 < /dev/null &
exit 0
