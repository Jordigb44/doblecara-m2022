#!/bin/bash
# Diagnóstico 3: cómo usa el filtro de Samsung el archivo com.sec.printer. NO imprime.
cd "$(dirname "$0")"
OUT="$(pwd)/diagnostico"
export PPD=/etc/cups/ppd/Samsung_M2020_Series.ppd
F=/Library/Printers/Samsung/UPD/Filters/rastertosec
C=/Library/Caches/com.sec.printer
O="media=A4 PageSize=A4 SECManualDuplexOption=LongEdge"
{
  echo "=== $(date)"; echo "contenido actual: $(cat $C)"
  echo "--- page_log (últimas líneas)"; tail -8 /var/log/cups/page_log 2>&1
  for pre in "0 0" "5 0" "5 1" "5 2" "6 1"; do
    printf '%s\n' "$pre" > $C
    "$F" 5 "$USER" prueba 1 "$O" "$OUT/r_LongEdge.ras" > "$OUT/t_${pre// /_}.prn" 2> "$OUT/t_${pre// /_}.log"
    rc=$?
    echo "--- antes='$pre' job=5 -> exit=$rc bytes=$(wc -c < "$OUT/t_${pre// /_}.prn") despues='$(cat $C)'"
    LC_ALL=C grep -a -o '@PJL SET DUPLEX[^[:cntrl:]]*' "$OUT/t_${pre// /_}.prn"
    grep -i -E 'flip|duplex|page_log|jobid|error|page [0-9]' "$OUT/t_${pre// /_}.log" | grep -v '% complete' | head -12
  done
  printf '0 0\n' > $C
} > "$OUT/diagnostico3.txt" 2>&1
echo FIN >> "$OUT/diagnostico3.txt"
