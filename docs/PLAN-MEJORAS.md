# Plan de mejoras de Doble Cara M2022

Guía práctica para atacar cada punto de la radiografía. Los puntos están
ordenados por prioridad (impacto / riesgo) y son independientes entre sí: se
pueden abordar de uno en uno, cada uno en su propia rama y PR hacia `develop`.

> Convención: crea una rama por punto desde `develop`, p. ej.
> `git checkout -b mejora/separar-logica develop`.

---

## 0. Preparación previa (una sola vez)

Antes de tocar nada, deja el repo limpio y crea el `.gitignore` base.

```bash
git checkout develop
git pull
```

**Crear/ampliar `.gitignore`** (si no existe):

```gitignore
.DS_Store
*.log
*.prn
*.ras
dist/
*.dmg
*.zip
SHA256SUMS.txt
app/*.bak
```

Comandos de verificación:

```bash
git rm --cached test/.DS_Store            # quitar del índice (si está trackeado)
git rm --cached app/DobleCara-1.0.swift.bak
```

---

## 1. Separar la lógica pura de la UI

**Objetivo:** sacar del `@MainActor Model` las funciones que no dependen de
SwiftUI para poder testearlas sin app.

**Archivos afectados:** `app/DobleCara.swift`.

**Pasos:**

1. Crea `app/PagePlan.swift` con un tipo `struct PagePlan` (sin `@MainActor`) y
   mueve estas funciones tal cual:
   - `parse(_:pageCount:)` — hoy en `DobleCara.swift:337`
   - `format(_:)` — hoy en `DobleCara.swift:354`
   - `selection(for:)` — hoy en `DobleCara.swift:323`
   - `sequence()` — hoy en `DobleCara.swift:387` (necesita `selection`, `copies`,
     `padBlank` como parámetros)
   - `sheetPlan` — hoy en `DobleCara.swift:378`
   - `Slot` — hoy en `DobleCara.swift:376`
   - `plural(_:_:_:)` — hoy en `DobleCara.swift:413`

2. En `Model`, sustituye las llamadas para delegar en `PagePlan`, pasando los
   datos que hagan falta (`doc.pageCount`, `selection`, `copies`, `padBlank`,
   `effectiveDuplex`).

3. Mantén la API externa idéntica (`m.selection`, `m.sheetPlan`, `m.summary`,
   etc.) para no tocar las vistas.

**Criterio de aceptación:** la app compila con `./app/build.sh` y se comporta
igual. La lógica ya no vive en un tipo `@MainActor`.

---

## 2. Tests unitarios de la lógica

**Objetivo:** cubrir la lógica de selección/orden con tests reproducibles.

**Pasos:**

1. Crea un `Package.swift` en `app/` que declare un target de tests, o crea un
   directorio `Tests/` si prefieres `swift test` a nivel de repo.

2. Casos mínimos a cubrir:

| Función | Casos |
|---|---|
| `parse` | `"1-3, 5, 8-"` → `[0,1,2,4,7,8,…]`; rangos invertidos (`"3-1"`); fuera de rango; texto vacío; `";"` como separador |
| `format` | ida y vuelta con `parse`; páginas sueltas vs rangos |
| `sequence` | 1 copia par, 1 copia impar con `padBlank`, 2 copias impares (salto de hoja) |
| `sheetPlan` | `duplex` vs no-duplex; correspondencia hoja/cara |

3. Ejecutar:

```bash
cd app && swift test
```

**Criterio de aceptación:** `swift test` en verde y la lógica extraída pasa los
casos de la tabla.

---

## 3. Robustez: `Shell.run` y estado de los trabajos

**Objetivo:** evitar deadlock de tuberías y detectar trabajos fallidos.

**Archivos:** `app/DobleCara.swift:57-110` y `:543-556`.

**Pasos:**

1. **`Shell.run` (línea 67):** el orden actual
   `readDataToEndOfFile()` → `waitUntilExit()` puede colgarse con salidas largas.
   Cámbialo a leer después de esperar:

   ```swift
   do { try p.run() } catch { return (-1, "\(error.localizedDescription)") }
   p.waitUntilExit()
   let data = pipe.fileHandleForReading.readDataToEndOfFile()
   return (p.terminationStatus, String(decoding: data, as: UTF8.self))
   ```

   (Suficiente para comandos cortos; si un día la salida crece, cambiar a
   `readabilityHandler`.)

2. **`waitForJob` (línea 543):** hoy solo sabe si el job *ya no está* en la cola.
   Añade una consulta al estado real para distinguir éxito de error, p. ej. con
   `lpstat -W completed -o <printer>` o comprobando el `terminationStatus` del
   `lp`. Si el job terminó con error, marca `phase = .failed`.

**Criterio de aceptación:** un job cancelado/fallido muestra un mensaje de error
en lugar de continuar como si hubiera terminado bien.

---

## 4. Higiene del repo y consistencia de versiones

**Objetivo:** limpiar binarios/logs y unificar la versión.

**Pasos:**

1. Borrar y desindexar: `test/.DS_Store`, `app/DobleCara-1.0.swift.bak`,
   logs (`*.log`), y `diagnostico/*.prn` / `*.ras` (deben quedar en `.gitignore`,
   no en el historial). Los PDFs de prueba sí pueden quedarse.

2. **Consolidar `test/` y `diagnostico/`:** `test/` duplica casi todo
   `diagnostico/`. Decide una única carpeta (recomendado: dejar `diagnostico/`
   para la investigación del driver y usar `test/` solo para los tests del punto 2).

3. **Versión única:** hoy `Info.plist` dice `1.1.0`, `dist/` tiene `1.0.0` y
   `package.sh` usa `1.0.0` por defecto. Establece `Info.plist` como fuente de
   verdad: en `package.sh`, si no se pasa versión, léela con

   ```bash
   /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$HERE/Info.plist"
   ```

   y elimina el `dist/` antiguo o regenéralo con la versión correcta.

**Criterio de aceptación:** `git status` limpio de binarios; una sola fuente de
verdad para la versión; `dist/` acorde al `Info.plist`.

---

## 5. CI: lint + build también en develop

**Objetivo:** detectar errores antes del merge y mantener estilo.

**Archivos:** `.github/workflows/build.yml`.

**Pasos:**

1. Añadir un job/paso de lint:

   ```yaml
   - name: ShellCheck
     run: brew install shellcheck && shellcheck bin/*.sh app/*.sh install.sh uninstall.sh crear_cola_doble_cara.sh
   ```

2. Añadir `swiftformat --lint` (o `swiftlint`) sobre `app/*.swift` si lo adoptas.

3. Disparar también en `develop`:

   ```yaml
   on:
     push:
       branches: [main, develop]
   ```

4. Opcional: `actions/checkout@v4` con `fetch-depth: 0` si vas a generar changelog.

**Criterio de aceptación:** el CI corre lint + empaquetado en cada PR hacia
`develop` y hacia `main`.

---

## 6. Notarización de la app

**Objetivo:** eliminar el aviso "no se puede comprobar el desarrollador".

**Requisito:** un certificado Developer ID de Apple (de pago, requiere cuenta).

**Pasos:**

1. En `package.sh`, sustituir la firma ad hoc (`codesign -s -`) por:

   ```bash
   codesign --force --deep --options runtime \
     --timestamp \
     --sign "Developer ID Application: Tu Nombre (TEAMID)" "$APP"
   ```

2. Notarizar y grapar:

   ```bash
   xcrun notarytool submit "$DIST/$BASE.zip" --apple-id ... --team-id ... --password ... --wait
   xcrun stapler staple "$APP"
   ```

3. En CI, usar secretos (`APPLE_ID`, `APPLE_APP_PASSWORD`, `TEAM_ID`,
   `APPLE_CERTIFICATE` + `APPLE_CERT_P12_PASSWORD`) y `notarytool`.

**Criterio de aceptación:** al abrir la app descargada no aparece el aviso de
desarrollador.

> Nota: si no se dispone de cuenta Developer ID, este punto se pospone; el resto
> del plan no depende de él.

---

## 7. Funcionalidad (opcional, menor prioridad)

Ideas con su ubicación actual:

| Mejora | Dónde |
|---|---|
| Reimprimir solo la cara B si falla (guardar los PDFs temporales en `~/Library/Application Support/...` en vez de `temporaryDirectory`) | `makePDF` (`:429`), `send` (`:517`) |
| Recordar el último directorio abierto | `openPanel` (`:303`) |
| Progreso real del trabajo en cola en vez de `ProgressView` indeterminado | `waitForJob` (`:543`), `PrintingPanel` (`:1208`) |
| Atajos de teclado visibles en un menú | `DobleCaraApp.commands` (`:26`) |

---

## Orden sugerido de ejecución

1. **Punto 0 + 4** (base limpia y versionado coherente) — bajo riesgo.
2. **Punto 1 + 2** (extraer lógica + tests) — mayor valor, riesgo contenido.
3. **Punto 5** (CI) — automatiza la verificación de lo anterior.
4. **Punto 3** (robustez) — afecta a impresión real, probar con cuidado.
5. **Punto 7** (funcionalidad) — según demanda.
6. **Punto 6** (notarización) — cuando haya Developer ID.
