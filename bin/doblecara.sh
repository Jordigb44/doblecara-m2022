#!/bin/bash
# doblecara.sh — impresión a doble cara manual para Samsung Xpress M2022 (macOS)
#
#   doblecara.sh [opciones] archivo.pdf
#
# Opciones:
#   --gui              Usa ventanas de diálogo de macOS (lo usan el menú PDF y la app)
#   --printer NOMBRE   Cola de impresión a usar (ver: lpstat -e)
#   --title TEXTO      Título del trabajo
#   --copies N         Número de copias del documento completo
#   --test             Imprime una hoja de prueba de 2 caras para calibrar
#   -h, --help         Muestra esta ayuda

set -uo pipefail

SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do SELF="$(readlink "$SELF")"; done
BASE="$(cd "$(dirname "$SELF")/.." && pwd)"

# shellcheck source=../config.sh
source "$BASE/config.sh"
USER_CONF="$HOME/.config/doblecara-m2022.conf"
# shellcheck disable=SC1090  # ruta dinámica definida por el usuario, puede no existir
[ -f "$USER_CONF" ] && source "$USER_CONF"

PDFTOOL="$BASE/lib/pdf_tool.js"
APP_TITLE="Doble cara M2022"
GUI=0
TITLE=""
COPIES=1
TEST=0
INPUT=""

# ---------------------------------------------------------------- utilidades

# Los mensajes se pasan a osascript como argumentos (argv), no interpolados en el
# script, para evitar inyección de AppleScript desde nombres de archivo o títulos.

die() {
  if [ "$GUI" = 1 ]; then
    osascript -e 'on run argv' -e 'activate' -e 'display alert (item 2 of argv) message (item 1 of argv) as critical' -e 'end run' "$1" "$APP_TITLE" >/dev/null 2>&1
  fi
  echo "Error: $1" >&2
  exit 1
}

info() {
  echo "$1"
  if [ "$GUI" = 1 ]; then
    osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title (item 2 of argv)' -e 'end run' "$1" "$APP_TITLE" >/dev/null 2>&1 || true
  fi
}

# Pregunta para continuar. Devuelve 0 = continuar, 1 = cancelar
ask_continue() {
  local msg="$1" button="$2"
  if [ "${DOBLECARA_AUTO:-0}" = 1 ]; then   # modo prueba sin preguntas
    echo "[auto] $button"; return 0
  fi
  if [ "$GUI" = 1 ]; then
    local r
    r=$(osascript -e 'on run argv' -e 'activate' -e 'set msg to item 1 of argv' -e 'set btn to item 2 of argv' -e 'set ttl to item 3 of argv' -e 'button returned of (display dialog msg with title ttl buttons {"Cancelar", btn} default button btn cancel button "Cancelar" with icon note)' -e 'end run' "$msg" "$button" "$APP_TITLE" 2>/dev/null)
    [ "$r" = "$button" ]
  else
    printf '\n%s\n\nPulsa INTRO para "%s" o Ctrl+C para cancelar... ' "$msg" "$button"
    read -r _ </dev/tty
  fi
}

usage() { sed -n '2,13p' "$SELF" | sed 's/^# \{0,1\}//'; exit 0; }

find_printer() {
  if [ -n "$PRINTER" ]; then
    lpstat -e 2>/dev/null | grep -qx "$PRINTER" || die "No existe la impresora \"$PRINTER\". Revisa config.sh (lpstat -e)."
    echo "$PRINTER"; return
  fi
  local p
  p=$(lpstat -e 2>/dev/null | grep -i 'm202' | head -n1)
  if [ -z "$p" ]; then
    p=$(lpstat -d 2>/dev/null | sed -n 's/^.*: //p')
  fi
  [ -n "$p" ] || die "No se encontró la Samsung M2022. Añádela en Ajustes > Impresoras y escáneres o indica su nombre en config.sh."
  echo "$p"
}

pdf_count() { osascript -l JavaScript "$PDFTOOL" count "$1" 2>/dev/null; }

pdf_split() { # entrada salida modo orden pad rotar
  osascript -l JavaScript "$PDFTOOL" split "$1" "$2" "$3" "$4" "$5" "$6" 2>/dev/null
}

# Envía a imprimir y devuelve el id del trabajo
send_job() { # archivo titulo
  local out
  local -a opts
  read -r -a opts <<< "$LP_OPTIONS"
  if [ "${#opts[@]}" -gt 0 ]; then
    out=$(lp -d "$PRN" -n "$COPIES_PASS" -t "$2" "${opts[@]}" "$1" 2>&1) || die "lp falló: $out"
  else
    out=$(lp -d "$PRN" -n "$COPIES_PASS" -t "$2" "$1" 2>&1) || die "lp falló: $out"
  fi
  # Vale para "request id is X-12" y para "el id de la petición es X-12"
  echo "$out" | grep -o -E "${PRN}-[0-9]+" | head -n1
}

wait_job() { # id
  local id="$1" t=0
  [ -n "$id" ] || return 0
  while lpstat -o "$PRN" 2>/dev/null | grep -q "^$id "; do
    sleep 2; t=$((t + 2))
    [ "$t" -ge "$WAIT_TIMEOUT" ] && break
  done
}

# ---------------------------------------------------------------- argumentos

while [ $# -gt 0 ]; do
  case "$1" in
    --gui) GUI=1 ;;
    --printer) PRINTER="$2"; shift ;;
    --title) TITLE="$2"; shift ;;
    --copies) COPIES="$2"; shift ;;
    --test) TEST=1 ;;
    -h|--help) usage ;;
    *) INPUT="$1" ;;
  esac
  shift
done

command -v lp >/dev/null || die "No se encuentra el comando lp (CUPS)."
PRN="$(find_printer)" || exit 1
COPIES_PASS=1

TMP="$(mktemp -d "${TMPDIR:-/tmp}/doblecara.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------- hoja de prueba

if [ "$TEST" = 1 ]; then
  printf 'CARA A  -  PAGINA 1\n\n^^^^ ARRIBA ^^^^\n\nSi el dorso sale cabeza abajo,\npon ROTATE_EVEN=180 en config.sh\n\fCARA B  -  PAGINA 2\n\n^^^^ ARRIBA ^^^^\n\nDebe coincidir con la cara A\n(al girar la hoja como un libro)\n' > "$TMP/prueba.txt"
  cupsfilter -i text/plain -m application/pdf -o cpi=6 -o lpi=3 "$TMP/prueba.txt" > "$TMP/prueba.pdf" 2>/dev/null \
    || die "No se pudo generar la hoja de prueba."
  INPUT="$TMP/prueba.pdf"
  TITLE="Prueba doble cara"
fi

# ---------------------------------------------------------------- comprobaciones

[ -n "$INPUT" ] || usage
[ -f "$INPUT" ] || die "No existe el archivo: $INPUT"
[ -n "$TITLE" ] || TITLE="$(basename "$INPUT" .pdf)"

# Copia de trabajo (el diálogo de impresión borra su PDF temporal enseguida)
cp "$INPUT" "$TMP/doc.pdf" || die "No se pudo leer el PDF."
N="$(pdf_count "$TMP/doc.pdf")"
[[ "$N" =~ ^[0-9]+$ ]] && [ "$N" -gt 0 ] || die "El archivo no es un PDF válido."

if [ "$N" -eq 1 ]; then
  info "Solo hay 1 página: se imprime a una cara."
  COPIES_PASS="$COPIES"
  send_job "$TMP/doc.pdf" "$TITLE" >/dev/null
  exit 0
fi

if [ "${MODE:-software}" = native ]; then
  # Doble cara manual del driver Samsung (@PJL SET DUPLEX = MANUAL)
  info "Imprimiendo a doble cara manual: cuando el botón de la impresora parpadee, gira las hojas y púlsalo."
  COPIES_PASS="$COPIES"
  JOB=$(LP_OPTIONS="$LP_OPTIONS -o SECManualDuplexOption=$EDGE" send_job "$TMP/doc.pdf" "$TITLE") || exit 1
  echo "Trabajo $JOB enviado."
  exit 0
fi

SHEETS=$(( (N + 1) / 2 ))
pdf_split "$TMP/doc.pdf" "$TMP/impares.pdf" odd normal 0 0 >/dev/null || die "No se pudieron separar las páginas impares."
pdf_split "$TMP/doc.pdf" "$TMP/pares.pdf" even "$EVEN_ORDER" "$PAD_BLANK" "$ROTATE_EVEN" >/dev/null || die "No se pudieron separar las páginas pares."

# ---------------------------------------------------------------- impresión

for ((c = 1; c <= COPIES; c++)); do
  label=""
  [ "$COPIES" -gt 1 ] && label=" (copia $c de $COPIES)"

  if [ "$c" -eq 1 ]; then
    ask_continue "Se imprimirán $N páginas en $SHEETS hoja(s)${label}.

Comprueba que hay al menos $SHEETS hoja(s) en la bandeja de entrada de la $PRN." "Imprimir cara A" || exit 0
  fi

  info "Imprimiendo cara A (páginas impares)${label}..."
  JOB=$(send_job "$TMP/impares.pdf" "$TITLE - cara A") || exit 1
  wait_job "$JOB"

  extra=""
  if [ $((N % 2)) -eq 1 ] && [ "$PAD_BLANK" != 1 ]; then
    extra="

IMPORTANTE: retira la hoja de ARRIBA del montón (solo lleva la página $N) y apártala; no la vuelvas a meter."
  fi

  ask_continue "Cara A terminada${label}.

1. Recoge la(s) $SHEETS hoja(s) de la bandeja de salida SIN cambiar su orden.
2. Mételas en la bandeja de entrada con la cara impresa hacia ABAJO y la parte de arriba del texto entrando primero en la impresora.${extra}

Cuando estén colocadas, pulsa «Imprimir cara B»." "Imprimir cara B" || exit 0

  info "Imprimiendo cara B (páginas pares)${label}..."
  JOB=$(send_job "$TMP/pares.pdf" "$TITLE - cara B") || exit 1
  wait_job "$JOB"
done

info "Listo: $N páginas impresas a doble cara."
exit 0
