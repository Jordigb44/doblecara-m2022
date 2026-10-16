#!/bin/bash
# Diagnóstico: genera lo que el driver de Samsung manda a la impresora (NO imprime nada)
cd "$(dirname "$0")"
OUT="$(pwd)/diagnostico"; mkdir -p "$OUT"
PPD=/etc/cups/ppd/Samsung_M2020_Series.ppd
{
  echo "=== $(date)"; sw_vers
  echo "--- estado impresora"; lpstat -l -p Samsung_M2020_Series
  echo "--- opciones de la cola"; lpoptions -p Samsung_M2020_Series -l | grep -i -E 'duplex|manual|blank|slot'
  echo "--- ultimos trabajos"; lpstat -W completed -o Samsung_M2020_Series | tail -5
  printf 'PAGINA 1 - CARA A\n\n^^^ ARRIBA ^^^\n\fPAGINA 2 - CARA B\n\n^^^ ARRIBA ^^^\n' > "$OUT/texto.txt"
  cupsfilter -i text/plain -m application/pdf -o cpi=6 -o lpi=3 "$OUT/texto.txt" > "$OUT/texto_2paginas.pdf" 2>/dev/null
  for f in blanco_2paginas.pdf "$OUT/texto_2paginas.pdf"; do
    b=$(basename "$f" .pdf)
    for opt in None LongEdge; do
      cupsfilter -p "$PPD" -m printer/foo -o SECManualDuplexOption=$opt "$f" > "$OUT/${b}_$opt.prn" 2> "$OUT/${b}_$opt.log"
      echo "--- $b $opt: $(wc -c < "$OUT/${b}_$opt.prn") bytes"
      LC_ALL=C grep -a -o '@PJL[^[:cntrl:]]*' "$OUT/${b}_$opt.prn"
    done
  done
  echo "--- log del sistema (impresión, últimos 10 min)"
  log show --last 10m --predicate 'process == "cupsd" OR process CONTAINS "rastertosec" OR process == "usb"' --style compact 2>/dev/null | tail -60
} > "$OUT/diagnostico.txt" 2>&1
echo FIN >> "$OUT/diagnostico.txt"
