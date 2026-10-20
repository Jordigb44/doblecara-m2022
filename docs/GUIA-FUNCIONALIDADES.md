# Guía de desarrollo de funcionalidades — Doble Cara M2022

Guía paso a paso para implementar cada funcionalidad propuesta. Cada sección
indica los archivos y líneas concretas a tocar, el código de referencia, los
casos límite y cómo verificarlo.

## Cómo usar esta guía

Flujo de trabajo (igual para todas):

```bash
git checkout develop
git pull
git checkout -b feat/<nombre-de-la-funcion>
# ... implementa y comprueba ...
./app/build.sh && swift test          # compilar la app y pasar los tests
shellcheck -S warning bin/*.sh app/*.sh install.sh uninstall.sh crear_cola_doble_cara.sh
git add -A && git commit -m "feat: <resumen>"
git checkout develop && git merge --no-ff feat/<nombre> 
```

Anclajes clave en `app/DobleCara.swift` (líneas actuales):

| Elemento | Línea |
|---|---|
| `enum Phase` (estados de impresión) | 174 |
| `@Published var doc / printer / paper` | 189 / 194 / 195 |
| `defaults.register(...)` (valores por defecto) | 242 |
| `func load(_:)` (carga un PDF) | 283 |
| `func openPanel()` | 313 |
| `func togglePage(_:)` | 341 |
| `func makePDF(_:rotate:name:)` | 388 |
| `func start()` | 429 |
| `func printSideB()` | 453 |
| `private func printSingle()` | 458 |
| `private func send(_:suffix:printing:next:)` | 477 |
| `func loadTestPage(sheets:)` | 590 |
| `struct ContentView` | 630 |
| `struct PDFPreview` | 728 |
| `struct SettingsForm` | 995 |
| `struct PrinterRows` | 1127 |
| `struct ActionBar` | 1257 |

---

## 1. Reimprimir solo la cara B si falla

**Objetivo:** si la cara B falla (o se cancela), poder volver a imprimirla sin
repetir la cara A. Hoy los PDFs se generan en `temporaryDirectory` (se borran
solos) y `printSideB()` solo funciona en estado `.waitingFlip`.

### 1.1 Guardar los PDFs en una carpeta persistente

En `makePDF` (línea 390) cambia el directorio temporal por uno persistente:

```swift
let dir = FileManager.default.temporaryDirectory.appendingPathComponent("DobleCaraM2022", isDirectory: true)
```

por

```swift
let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("DobleCaraM2022", isDirectory: true)
```

> Nota: en una app compilada de forma ad hoc (sin bundle), usa
> `~/.local/share/DobleCaraM2022` o `~/Library/Application Support/DobleCaraM2022`.
> Puedes reutilizar la ruta de `install.sh` (`~/Library/Application Support/DobleCaraM2022`).

### 1.2 Exponer el estado "se puede reimprimir la B"

Añade al `Model` una propiedad computada (junto a `evenFile`, línea 236):

```swift
var canReprintB: Bool { evenFile != nil && phase == .failed }
```

Asegúrate de limpiar `evenFile` cuando cargas un documento nuevo. En
`setDocument` (justo después de `doc = d`) añade:

```swift
evenFile = nil
```

### 1.3 Permitir reimprimir

Sustituye `printSideB()` (línea 453) por una versión que también acepte el
reintento desde un fallo:

```swift
func printSideB() {
    guard let evenFile else { return }
    if phase == .failed {
        // Reintento: se restaura el estado y se reenvía
        phase = .waitingFlip
    }
    guard phase == .waitingFlip else { return }
    send(evenFile, suffix: "cara B", printing: .printingB, next: .done)
}
```

### 1.4 Añadir el botón en la interfaz

En `ActionBar` (línea 1286), dentro de `case .idle, .failed`, añade antes del
botón "Imprimir cara A" un botón secundario:

```swift
if m.canReprintB {
    Button { m.printSideB() } label: {
        Label("Reimprimir cara B", systemImage: "arrow.clockwise")
    }
}
```

### Casos límite
- Cancelar la B y reintentar varias veces (debe regenerar el mismo `evenFile`, no otro).
- Cargar un PDF nuevo tras un fallo: `evenFile` debe quedar a `nil` (paso 1.2).
- `copies > 1`: el `evenFile` ya contiene todas las copias; el reintento es correcto sin cambios.

### Verificación
- `./app/build.sh` compila; `swift test` sigue en verde.
- Prueba manual (con impresora): cancela la B y pulsa "Reimprimir cara B".

---

## 2. Detectar el tamaño de papel automáticamente

**Objetivo:** preseleccionar A4/Letter/Legal/A5 según el `mediaBox` del PDF, en
vez de dejar A4 fijo (el PPD de Samsung usa Letter por defecto).

### 2.1 Añadir un detector

Añade a `Model` un método que mapee el tamaño de la primera página:

```swift
static func paperName(for size: CGSize) -> String? {
    let pt: [(String, CGSize)] = [
        ("A4",     CGSize(width: 595.28, height: 841.89)),
        ("Letter", CGSize(width: 612,    height: 792)),
        ("Legal",  CGSize(width: 612,    height: 1008)),
        ("A5",     CGSize(width: 419.53, height: 595.28)),
    ]
    let (w, h) = (size.width, size.height)
    return pt.first { pair in
        let s = pair.1
        return (abs(w - s.width) < 3 && abs(h - s.height) < 3)
            || (abs(w - s.height) < 3 && abs(h - s.width) < 3)
    }?.0
}
```

Para leer el tamaño con el giro ya aplicado, reutiliza la lógica de `size(of:)`
que hay dentro de `makePDF` (línea 396).

### 2.2 Aplicarlo al cargar (sin pisar al usuario)

Añade un flag `@Published var autoPaper = true`. En `setDocument`, tras fijar
`doc`, si `autoPaper` es `true`:

```swift
if autoPaper, let page = d?.page(at: 0) {
    let b = page.bounds(for: .mediaBox)
    let size = page.rotation % 180 == 0 ? b.size : CGSize(width: b.height, height: b.width)
    if let name = Self.paperName(for: size) { paper = name }
}
```

En `PrinterRows` (línea 1127), el `Picker("Papel", ...)` debe poner `autoPaper = false`
cuando el usuario elige manualmente (usa `.onChange(of: m.paper)`).

### Casos límite
- Documento mixto con varias medidas: se decide por la primera página (documentado).
- PDF con `mediaBox` no estándar (p. ej. recibos 80×200 mm): no se cambia el papel.

### Verificación
- Cargar un PDF Letter → el picker muestra "Carta"; uno A4 → "A4".
- Elegir papel a mano y cargar otro PDF → no se sobrescribe la elección.

---

## 3. Archivos recientes

**Objetivo:** menú "Abrir recientes" con los últimos PDFs.

### 3.1 Persistir la lista

Añade al `Model`:

```swift
@Published var recentFiles: [URL] = [] {
    didSet { defaults.set(recentFiles.map(\.path), forKey: "recentFiles") }
}
```

Inicialízalo en `init` (junto a los otros `@Published`, cerca de línea 194):

```swift
recentFiles = (defaults.stringArray(forKey: "recentFiles") ?? []).map { URL(fileURLWithPath: $0) }
```

### 3.2 Registrar al abrir

En `setDocument` (o al final de `load`), añade:

```swift
if let u, !recentFiles.contains(u) {
    recentFiles.insert(u, at: 0)
    if recentFiles.count > 10 { recentFiles.removeLast(recentFiles.count - 10) }
}
```

### 3.3 Menú

En `DobleCaraApp.commands` (junto a "Abrir PDF…", ~línea 26), añade un submenú:

```swift
CommandMenu("Archivo") {
    Button("Abrir PDF…") { model.openPanel() }.keyboardShortcut("o")
    Menu("Abrir recientes") {
        ForEach(model.recentFiles, id: \.self) { u in
            Button(u.lastPathComponent) { model.load(u) }
        }
    }
    .disabled(model.recentFiles.isEmpty)
}
```

### Verificación
- Abrir varios PDFs y comprobar que aparecen; se ordenan por más recientes y se
  limita a 10.

---

## 4. Cola de varios documentos

**Objetivo:** encolar varios PDFs y procesarlos uno tras otro sin intervención
entre documentos.

### 4.1 Modelo de cola

Añade al `Model`:

```swift
@Published var queue: [URL] = []
@Published var queuedIndex = 0
```

Modifica `load(_:)` para que, si ya hay una impresión en curso, encolar en vez de
rechazar con `NSSound.beep()` (línea 283). Al terminar el documento actual
(`phase == .done` o `.failed`), avanzar al siguiente de la cola:

```swift
func advanceQueue() {
    guard queuedIndex < queue.count else { queue = []; queuedIndex = 0; return }
    let u = queue[queuedIndex]
    queuedIndex += 1
    load(u)
}
```

### 4.2 Enganchar el avance

En `send` (línea 477) y `printSingle` (línea 458), cuando `phase = next` es
`.done`, si `!queue.isEmpty`, llama a `advanceQueue()` tras una pequeña pausa.

### 4.3 Interfaz

Añade un indicador "Cola: 2 restantes" y un botón para vaciar la cola en
`SettingsForm` o `ActionBar`.

### Casos límite
- El usuario arrastra varios PDFs a la vez (`AppDelegate`/`dropDestination`).
- Cancelar un documento de la cola: se salta o se para toda la cola (decidir y
  documentarlo).

> Esta es la funcionalidad más invasiva (toca la máquina de estados). Hazla en
> pasos pequeños y con pruebas de la transición.

---

## 5. Perfiles de impresión

**Objetivo:** guardar conjuntos impresora+papel+ajustes de cara B con nombre.

### 5.1 Modelo

```swift
struct PrintProfile: Codable, Identifiable {
    var id = UUID()
    var name: String
    var printer: String
    var paper: String
    var duplex: Bool
    var reverseB: Bool
    var rotateB: Bool
    var padBlank: Bool
    var fitToPage: Bool
    var faceDown: Bool
}
```

En `Model`, persiste `[PrintProfile]` como JSON en `defaults`:

```swift
@Published var profiles: [PrintProfile] = [] {
    didSet { if let d = try? JSONEncoder().encode(profiles) { defaults.set(d, forKey: "profiles") } }
}
```

### 5.2 Aplicar y guardar

```swift
func apply(_ p: PrintProfile) {
    printer = p.printer; paper = p.paper; duplex = p.duplex
    reverseB = p.reverseB; rotateB = p.rotateB; padBlank = p.padBlank
    fitToPage = p.fitToPage; faceDown = p.faceDown
}
func saveProfile(_ name: String) {
    profiles.append(PrintProfile(name: name, printer: printer, paper: paper,
        duplex: duplex, reverseB: reverseB, rotateB: rotateB, padBlank: padBlank,
        fitToPage: fitToPage, faceDown: faceDown))
}
```

### 5.3 Interfaz

Añade una sección "Perfiles" en `SettingsForm` con `Picker` para elegir, botones
"Guardar actual" (pide nombre con `NSAlert`/`alert` de SwiftUI) y "Eliminar".

---

## 6. Búsqueda dentro del PDF

**Objetivo:** localizar texto antes de imprimir.

### 6.1 Buscar

`PDFDocument` ya expone búsqueda. Añade a `PreviewPane` un campo de texto y,
al pulsar Intro:

```swift
let sel = m.doc?.findString(query, withOptions: [.caseInsensitive])
if let sel, let page = sel.pages.first {
    m.doc?.beginFindString(query, withOptions: [.caseInsensitive])
    // y saltar a la página encontrada
}
```

Para saltar de página: reutiliza el `@State page` de `PreviewPane` (línea ~862)
fijándolo al índice de la página hallada. Un `PDFView` con find bar requiere
envolver `PDFView` (NSViewRepresentable, línea 728) para exponer
`performFind`/`goToNextResult`.

### 6.2 Alternativa sencilla

Si prefieres no tocar `PDFPreview`, usa un `NSTextField` + `PDFSelection` y muestra
la página con el texto resaltado mediante `setCurrentSelection(_:animate:)`.

---

## 7. Controles de zoom y vista previa

**Objetivo:** zoom manual y ajuste a ancho.

### 7.1 Exponer el factor de escala

En `PDFPreview` (línea 728) añade un `@Binding var scale: CGFloat` (o un modo
"fit/width/actual"). En `updateNSView`:

```swift
if v.scaleFactor != scale { v.scaleFactor = scale }
```

### 7.2 Controles

En `PreviewPane`, junto a `PageNavigator`, añade `Stepper` o botones
`magnifyingglass.plus/minus` y un botón "Ajustar" que vuelve a `autoScales = true`.

> Mantén separado este "zoom de vista" del "Girar cara B 180°" de impresión
> (`rotateB`), que afecta al PDF generado, no a la vista.

---

## 8. Impresión de folleto (booklet)

**Objetivo:** 2 páginas por hoja reordenadas para grapar por el centro.

### 8.1 Algoritmo

Pad a múltiplo de 4 y genera la secuencia de pares (anverso, reverso) por hoja:

```swift
static func bookletOrder(pageCount n: Int) -> [Int?] {
    let total = (n + 3) / 4 * 4
    var pages: [Int?] = Array(0..<n) + Array(repeating: nil, count: total - n)
    var out: [Int?] = []
    var front = 0, back = total - 1
    while front <= back {
        out += [pages[back], pages[front], pages[front + 1], pages[back - 1]]
        front += 2; back -= 2
    }
    return out
}
```

Este orden se alimenta a `makePDF`, dibujando **dos** páginas por hoja (una
rotada 180° en el reverso) y generando un único PDF de impresión a dos caras.

### 8.2 Integración

Añade un modo a `PageMode` (p. ej. `.booklet`) o un `Toggle` en `DuplexRows`, y
usa `bookletOrder` en `start()` en lugar de la separación impar/par.

> Impactante pero con más superficie de error. Empieza por un botón "Imprimir
> folleto" independiente para no romper el flujo actual.

---

## 9. N-up (2/4 páginas por hoja)

**Objetivo:** imprimir varias páginas reducidas por hoja.

### 9.1 Dibujar N por hoja

En `makePDF`, agrupa las páginas de `indices` en lotes de N y dibuja cada una
dentro de un cuadrante del `mediaBox` usando `ctx.translateBy` + `scaleBy`:

```swift
let cols = 2, rows = 2          // 4-up
let cell = CGSize(width: media.width / CGFloat(cols), height: media.height / CGFloat(rows))
for (slot, i) in batch.enumerated() {
    let x = CGFloat(slot % cols) * cell.width
    let y = CGFloat(slot / cols) * cell.height
    ctx.saveGState()
    ctx.translateBy(x: x, y: y)
    ctx.scaleBy(x: cell.width / media.width, y: cell.height / media.height)
    page.draw(with: .mediaBox, to: ctx)
    ctx.restoreGState()
}
```

### 9.2 Interfaz

Añade `@Published var pagesPerSheet = 1` y un `Picker` en `PrinterRows`.

---

## 10. Modo "letra grande" / accesibilidad

**Objetivo:** interfaz más clara para personas mayores.

### 10.1 Flag global

```swift
@AppStorage("largeUI") private var largeUI = false
```

### 10.2 Aplicar escala

Envuelve la raíz de `ContentView` con `.environment(\.dynamicTypeSize, largeUI ? .xxxLarge : .large)`
o define un `CGFloat` de escala y multiplica los tamaños de fuente clave
(`StepBar`, `ActionBar`, `FlipStepsList`). Añade un `Toggle("Letra grande")` en
`PreferencesView` y en la bienvenida.

> SwiftUI respeta `dynamicTypeSize` de forma automática si las fuentes usan
> `.font(.body)` etc. en vez de tamaños fijos.

---

## 11. Acción en Shortcuts (AppIntents)

**Objetivo:** imprimir desde Shortcuts/Automator.

### 11.1 Intent

```swift
import AppIntents

struct PrintDuplexIntent: AppIntent {
    static var title: LocalizedStringResource = "Imprimir a doble cara"
    @Parameter(title: "PDF") var file: IntentFile

    func perform() async throws -> some IntentResult {
        // Abre la app con el archivo (o llama a una rutina compartida)
        return .result()
    }
}
```

> Para reutilizar la lógica de impresión fuera de `Model.shared`, habría que
> extraerla a un servicio; lo más simple es abrir la app con `openURL` del
> archivo y que el flujo normal se encargue.

---

## 12. Acción rápida en Finder (Quick Action)

**Objetivo:** clic derecho → "Imprimir a doble cara" sobre un PDF en Finder.

### 12.1 Automator Quick Action

Crea un `.workflow` con un paso "Ejecutar script de shell":

```bash
for f in "$@"; do "$HOME/.local/bin/doblecara" --gui "$f"; done
```

Se instala en `~/Library/Services/` (aparece en el menú contextual y en
Servicios). Documenta en el README cómo activarlo en *Ajustes → Teclado →
Funciones rápidas*.

---

## 13. Internacionalización (i18n)

**Objetivo:** traducir los textos (hoy hardcodeados en español).

### 13.1 String Catalog

1. Añade `String(localized:)` a los literales de las vistas (p. ej. en `SettingsForm`,
   `FlipPanel`, `WelcomeSheet`).
2. Crea `Localizable.xcstrings` (Xcode → New File → String Catalog).
3. Compila con el flag `-enable-experimental-string-catalog` o con Xcode.
4. Añade inglés y catalán en el catálogo.

> Con `swiftc` manual (sin Xcode), la ruta más sencilla es un `Localizable.strings`
> por idioma y `String(localized:)`. Los plurales ya usan `plural(_:_:_:)` de
> `PagePlan`; conviene migrarlos a `.stringsdict` si se internacionaliza.

---

## 14. Estadísticas de uso

**Objetivo:** mostrar nº de trabajos y hojas ahorradas.

### 14.1 Contadores

En `defaults` guarda `jobsCount` y `sheetsSaved`. Incrementa en `send` cuando
`next == .done`:

```swift
defaults.set(jobsCount + 1, forKey: "jobsCount")
defaults.set(sheetsSaved + max(0, selection.count - sheetCount), forKey: "sheetsSaved")
```

### 14.2 Mostrar

Añade una sección "Estadísticas" en `PreferencesView` con los totales y un botón
para reiniciarlos.

---

## 15. Modo borrador / grises

**Objetivo:** ahorrar tóner imprimiendo en escala de grises.

### 15.1 Opción de `lp`

Añade `@Published var grayscale = false` (con `didSet` persistiendo) y un
`Toggle("Imprimir en grises")` en `PrinterRows`. En `Shell.lp` (línea ~86),
añade el argumento cuando esté activo:

```swift
if grayscale { args += ["-o", "ColorModel=Gray"] }
```

> El nombre exacto de la opción depende del PPD (`ColorModel=Gray` en Samsung;
> en otras puede ser `print-color-mode=monochrome`). Verifícalo con
> `lpoptions -p <printer> -l`.

---

## Orden recomendado

1. **#3 Archivos recientes** (menor riesgo, resultado inmediato)
2. **#2 Auto-detectar papel** (quita error frecuente)
3. **#1 Reimprimir cara B** (mayor valor, requiere la carpeta persistente)
4. **#15 Borrador/grises** (una línea)
5. **#5 Perfiles** y **#14 Estadísticas** (guardado/config)
6. **#7 Zoom** y **#6 Búsqueda** (vista previa)
7. **#10 Letra grande** (accesibilidad)
8. **#8 Folleto / #9 N-up** (cambios grandes en `makePDF`)
9. **#11 Shortcuts / #12 Quick Action / #13 i18n** (integración/distribución)
