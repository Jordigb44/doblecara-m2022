# Doble Cara M2022

[![Build macOS](https://github.com/Jordigb44/doblecara-m2022/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/Jordigb44/doblecara-m2022/actions/workflows/build.yml)

Impresión a **doble cara manual** en macOS para la **Samsung Xpress M2022** (y la serie
M2020), que no tiene dúplex automático y cuyo driver ya no ofrece esta opción en
macOS 27. Sirve también para cualquier otra impresora sin dúplex.

App nativa de macOS (SwiftUI + PDFKit) que:

1. Abre el PDF y te deja elegir impresora, papel, copias e intervalo de páginas.
2. Imprime las páginas impares (**cara A**).
3. Espera a que la impresora termine y te avisa para dar la vuelta a las hojas.
4. Imprime las páginas pares (**cara B**) en el orden y la orientación correctos.

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

- **Finder:** clic derecho en un PDF → *Abrir con* → **Doble Cara M2022**.
- **Arrastrar** el PDF a la ventana de la app o a su icono del Dock.
- **Desde Vista Previa:** arrastra el icono pequeño del título de la ventana a la app.

Pulsa **Imprimir cara A**. Cuando termine, mete las hojas en la bandeja de entrada
**con la cara impresa hacia abajo y la parte de arriba entrando primero**, sin
cambiar su orden, y pulsa **Imprimir cara B**.

### Opciones de la cara B

| Opción | Por defecto | Para qué |
|---|---|---|
| Cara B en orden inverso | ✔ | La M2022 deja las hojas boca abajo; la última sale arriba. |
| Girar cara B 180° | ✔ | Con la M2022 el dorso sale cabeza abajo si no se gira. |
| Dorso en blanco si las páginas son impares | ✔ | Así vuelves a meter todas las hojas sin retirar ninguna. |

La primera vez usa **Cargar hoja de prueba** y comprueba que las dos caras se leen
en el mismo sentido.

### Línea de comandos

```bash
~/.local/bin/doblecara documento.pdf          # ventanas de aviso en Terminal
~/.local/bin/doblecara --copies 2 documento.pdf
```

Configuración en `config.sh` (o `~/.config/doblecara-m2022.conf`).

## Notas técnicas sobre macOS 27

- **Menú «PDF» del diálogo de impresión:** en macOS 27, Vista Previa se bloquea al
  usar un servicio PDF propio (ni siquiera llega a ejecutarlo), así que la app no
  se instala ahí.
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
