#!/bin/bash
# Prueba: imprime un PDF de 2 páginas en blanco con doble cara manual
cd "$(dirname "$0")"
LOG="$(pwd)/prueba.log"
{
  echo "=== $(date) ==="
  echo "--- sw_vers"; sw_vers
  echo "--- lpstat -e"; lpstat -e
  echo "--- lpstat -d"; lpstat -d
  echo "--- lpstat -p"; lpstat -p
  echo "--- conteo de páginas"
  osascript -l JavaScript ../lib/pdf_tool.js count blanco_2paginas.pdf
  echo "--- separación"
  osascript -l JavaScript ../lib/pdf_tool.js split blanco_2paginas.pdf /tmp/dc_odd.pdf odd normal 0 0
  osascript -l JavaScript ../lib/pdf_tool.js split blanco_2paginas.pdf /tmp/dc_even.pdf even reverse 1 0
  ls -l /tmp/dc_odd.pdf /tmp/dc_even.pdf
  echo "--- ejecución doblecara.sh --gui"
  bash -x ../bin/doblecara.sh --gui --title "Prueba blanco" blanco_2paginas.pdf
  echo "exit=$?"
  echo "--- cola tras imprimir"; lpstat -o; lpstat -W completed -o | tail -5
} > "$LOG" 2>&1
echo "Prueba terminada. Log en $LOG"
