# Configuración de DobleCaraM2022
# Puedes editar este archivo o crear ~/.config/doblecara-m2022.conf con las
# variables que quieras sobrescribir (ese archivo tiene prioridad).

# Nombre de la cola de impresión en macOS. Vacío = detectar automáticamente
# la primera impresora cuyo nombre contenga "M202" (Samsung M2020/M2022...).
# Para ver los nombres exactos:  lpstat -e
PRINTER=""

# Modo de doble cara:
#   software -> el script separa impares/pares y te avisa con ventanas (recomendado,
#               probado en macOS 27)
#   native   -> doble cara manual del driver de Samsung. En macOS 27 la impresora
#               imprime la cara A y se para en rojo, pero al pulsar el botón no
#               imprime la cara B (el driver 3.93 no funciona del todo aquí)
MODE="software"
# Borde de giro en modo native: LongEdge (como un libro) o ShortEdge (como un bloc)
EDGE="LongEdge"

# --- Ajustes solo para MODE="software" ---
# Orden de impresión de las páginas pares (2.ª pasada).
#   reverse -> 2.ª pasada de la última hoja a la primera (lo normal en la M2022,
#              que deja las hojas boca abajo en la bandeja de salida)
#   normal  -> 2, 4, 6...
EVEN_ORDER="reverse"

# Si el documento tiene un número impar de páginas, la última hoja no tiene dorso.
#   1 -> se imprime un dorso en blanco y vuelves a meter TODAS las hojas
#   0 -> se te pide que retires esa última hoja antes de la 2.ª pasada
PAD_BLANK=1

# Giro (grados) aplicado a las páginas pares. Usa 180 si en la prueba
# el dorso sale cabeza abajo y no quieres girar el taco a mano.
ROTATE_EVEN=180

# Opciones extra para lp (por ejemplo: "-o media=A4" o "-o fit-to-page")
LP_OPTIONS=""

# Segundos máximos que se espera a que termine la 1.ª pasada antes de avisarte
WAIT_TIMEOUT=600
