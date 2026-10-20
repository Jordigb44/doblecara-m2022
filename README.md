# Doble Cara M2022

[![Build macOS](https://github.com/Jordigb44/doblecara-m2022/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/Jordigb44/doblecara-m2022/actions/workflows/build.yml)

Impresión a **doble cara manual** en macOS para la **Samsung Xpress M2022** (y la serie
M2020), que no tiene dúplex automático y cuyo driver ya no ofrece esta opción en
macOS 27. Sirve también para cualquier otra impresora sin dúplex.

App nativa de macOS (SwiftUI + PDFKit) que:

1. Abre el PDF y te deja elegir impresora, papel, copias e intervalo de páginas.
2. Imprime las páginas impares (**cara A**).
3. Espera a que la impresora termine y te avisa (sonido y notificación) para volver a
   meter las hojas.
4. Imprime las páginas pares (**cara B**) en el orden y la orientación correctos.

Pensada también para quien no se maneja bien con el ordenador: te guía paso a paso,
con una bienvenida la primera vez y un asistente para calibrar la impresora.

No sustituye al driver de la impresora: funciona encima de la cola de impresión
que ya tengas instalada.

## Descarga (lo más fácil)

1. Descarga `DobleCaraM2022-x.y.z-macOS.dmg` de la página de
   [Releases](https://github.com/Jordigb44/doblecara-m2022/releases/latest).
2. Ábrelo y arrastra **Doble Cara M2022** a **Aplicaciones**.
3. La primera vez macOS avisará de que no puede comprobar el desarrollador (la app
   está firmada *ad hoc*, no notarizada por Apple): clic derecho en la app → **Abrir**
   → **Abrir**, o *Ajustes del Sistema → Privacidad y seguridad → Abrir igualmente*.

App universal (Apple Silicon e Intel), macOS 13 o posterior.

Para generar el paquete tú mismo: `./app/package.sh 1.0.0` (o doble clic en
`Empaquetar.command`); deja el `.dmg` y el `.zip` en `dist/`.

Para notarizar (evita el aviso de desarrollador), firma y notariza pasando las
variables `DEVELOPER_ID`, `APPLE_ID`, `APPLE_TEAM_ID` y `APPLE_APP_PASSWORD` a
`package.sh` (requiere una cuenta de Apple Developer).

## Compilar desde el código

### Requisitos

- macOS 13 o posterior (probado en macOS 27.0.1, Apple Silicon).
- Xcode o las Command Line Tools (`xcode-select --install`) para compilar la app.
  Si no están, el instalador crea una versión sencilla con ventanas de AppleScript.
- La impresora ya funcionando en *Ajustes del Sistema → Impresoras y escáneres*.

### Instalación

```bash
git clone https://github.com/Jordigb44/doblecara-m2022.git
cd doblecara-m2022
./install.sh          # o doble clic en Instalar.command
```

Instala la app en `~/Applications/Doble Cara M2022.app` y el comando
`~/.local/bin/doblecara`. No necesita contraseña de administrador.

## Uso

- **Al imprimir desde cualquier app:** *Archivo → Imprimir…* → menú **PDF** (abajo a la
  izquierda) → **Doble cara manual (M2022)**. El documento se abre en la app. Viene
  activado por defecto; se quita en *Preferencias* (⌘,).
- **Finder:** clic derecho en un PDF → *Abrir con* → **Doble Cara M2022**.
- **Arrastrar** el PDF a la ventana de la app o a su icono del Dock.

La ventana te guía en cuatro pasos: **Documento → Cara A → Meter hojas → Cara B**.

1. Elige la impresora y qué imprimir: todas las páginas, un intervalo *desde–hasta*
   (escribiendo los números o con las flechas) o páginas sueltas (`1-3, 5, 8`).
   Abajo se resume el resultado: «8 páginas → 4 hojas».
2. Pulsa **Imprimir cara A** (⌘P).
3. Cuando termine, la app te enseña con una animación cómo volver a meter las hojas.
   Con «Girar cara B 180°» activado (lo normal), se meten **tal cual salen de la
   impresora, sin darles la vuelta ni girarlas**.
4. Pulsa **Imprimir cara B**.

En la vista previa ves en qué página estás («Página 3 de 9») y puedes saltar a otra
escribiendo el número. La vista **Hojas** muestra todas las páginas en miniatura:
las que se imprimen llevan su hoja y cara («Hoja 2 · A»), las que no salen apagadas;
clic en una para quitarla o añadirla.

### Primera vez

- Sale una **bienvenida** que explica cómo funciona (*Ayuda → Ver la bienvenida*).
- **Calibrar la impresora…** imprime 2 hojas de prueba (páginas 1 a 4), te pregunta
  qué página hay detrás de la 1 y si se lee al derecho, y ajusta solo las opciones
  de la cara B. Se puede ocultar en *Funciones avanzadas*.

### Opciones de la cara B

| Opción | Por defecto | Para qué |
|---|---|---|
| Cara B en orden inverso | ✔ | La M2022 deja las hojas boca abajo; la última sale arriba. |
| Girar cara B 180° | ✔ | Con la M2022 el dorso sale cabeza abajo si no se gira. |
| Dorso en blanco si las páginas son impares | ✔ | Así vuelves a meter todas las hojas sin retirar ninguna. |
| Volver a meter las hojas (cara impresa abajo/arriba) | abajo | Solo aparece si se desactiva el giro de 180°. |

Están en **Funciones avanzadas** (en la ventana principal) y en *Preferencias* (⌘,).

### Línea de comandos

```bash
~/.local/bin/doblecara documento.pdf          # ventanas de aviso en Terminal
~/.local/bin/doblecara --copies 2 documento.pdf
```

Configuración en `config.sh` (o `~/.config/doblecara-m2022.conf`).

## Notas técnicas sobre macOS 27

- **Menú «PDF» del diálogo de impresión:** en macOS 27, Vista Previa se bloqueaba
  con el servicio PDF antiguo (un script). Ahora el menú usa un enlace a la propia
  app en `~/Library/PDF Services/Doble cara manual (M2022)`, que el sistema abre
  como cualquier documento. La app lee el PDF en memoria al recibirlo, porque el
  archivo temporal del diálogo de impresión puede borrarse enseguida.
- **Giro de 180°:** el sistema de impresión ignora la marca `/Rotate` de 180°, así
  que la app redibuja la página girada.
- **Tamaño de papel:** el PPD de Samsung tiene *Letter* por defecto; `lp` sin
  `-o media=A4` imprime en Letter.
- **Doble cara manual del driver de Samsung (v3.93):** el PPD incluye
  `SECManualDuplexOption` y el filtro `rastertosec` envía `@PJL SET DUPLEX = MANUAL`.
  La impresora imprime la cara A y espera el botón con la luz roja parpadeando,
  pero al pulsarlo no imprime la cara B. Se deja documentado, sin usar:
  `crear_cola_doble_cara.sh` crea una cola con esa opción activada por si a
  alguien le funciona en otra versión de macOS.

## Estructura

```
app/            App nativa (DobleCara.swift, Info.plist), build.sh (instalar),
                package.sh (.dmg/.zip universal) y make_icon.swift (icono)
bin/            doblecara.sh (versión de línea de comandos) y lanzar.sh
lib/            pdf_tool.js: separa páginas con PDFKit (JavaScript for Automation)
diagnostico/    Scripts usados para investigar el driver de Samsung (no imprimen,
                salvo prueba.command)
install.sh      Instalador · Instalar.command / Empaquetar.command (doble clic) · uninstall.sh
config.sh       Ajustes de la versión de línea de comandos
```

## Ramas y CI

- **`main`**: versión estable. Cada push o pull request hacia `main` ejecuta
  [GitHub Actions](.github/workflows/build.yml) en macOS y genera el `.dmg`, el
  `.zip` y `SHA256SUMS.txt` como artefacto del run.
- **`develop`**: desarrollo; se integra en `main` mediante pull request.
- **Releases:** al subir una etiqueta `vX.Y.Z` (p. ej. `git tag v1.0.1 && git push origin v1.0.1`)
  el CI crea el release de GitHub con los tres archivos adjuntos.

## Desinstalar

```bash
./uninstall.sh
```

## Licencia

MIT. Samsung es una marca de Samsung Electronics; este proyecto no está afiliado
a Samsung ni a HP.
