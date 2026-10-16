#!/bin/bash
# Diagnóstico 2: pasa el documento por el filtro de Samsung (rastertosec) y guarda
# las órdenes PJL que recibiría la impresora. NO imprime nada.
cd "$(dirname "$0")"
OUT="$(pwd)/diagnostico"; mkdir -p "$OUT"
export PPD=/etc/cups/ppd/Samsung_M2020_Series.ppd
F=/Library/Printers/Samsung/UPD/Filters/rastertosec
{
  echo "=== $(date)"
  grep -E '^\*Default(PageSize|PageRegion|SECManual|InputSlot)' "$PPD"
  for opt in None LongEdge; do
    O="media=A4 PageSize=A4 SECManualDuplexOption=$opt"
    cupsfilter -p "$PPD" -m application/vnd.cups-raster -o media=A4 -o PageSize=A4 -o SECManualDuplexOption=$opt \
      "$OUT/texto_2paginas.pdf" > "$OUT/r_$opt.ras" 2> "$OUT/r_$opt.log"
    echo "--- raster $opt: $(wc -c < "$OUT/r_$opt.ras") bytes"
    "$F" 1 "$USER" prueba 1 "$O" "$OUT/r_$opt.ras" > "$OUT/final_$opt.prn" 2> "$OUT/final_$opt.log"
    echo "--- rastertosec $opt: exit=$? $(wc -c < "$OUT/final_$opt.prn") bytes"
    LC_ALL=C grep -a -o '@PJL[^[:cntrl:]]*' "$OUT/final_$opt.prn"
    echo "--- stderr filtro:"; grep -v '^DEBUG2' "$OUT/final_$opt.log" | tail -25
  done
} > "$OUT/diagnostico2.txt" 2>&1
echo FIN >> "$OUT/diagnostico2.txt"
