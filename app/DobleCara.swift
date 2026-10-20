// Doble Cara M2022 — app de macOS para imprimir a doble cara manual
// (pensada para la Samsung Xpress M2022, sirve para cualquier impresora sin dúplex)
//
// Compilar:  ./build.sh   (necesita las Command Line Tools de Xcode)

import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers
import UserNotifications

/// Conjunto de ajustes de impresión guardados con un nombre
struct PrintProfile: Codable, Identifiable, Equatable {
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
    var grayscale: Bool
    var margin: Double
}

// MARK: - App

@main
struct DobleCaraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = Model.shared

    var body: some Scene {
        Window("Doble Cara M2022", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Abrir PDF…") { model.openPanel() }
                    .keyboardShortcut("o")
                    .disabled(model.busy)
                Menu("Abrir recientes") {
                    ForEach(model.recentFiles, id: \.self) { u in
                        Button(u.lastPathComponent) { model.load(u) }
                    }
                }
                .disabled(model.recentFiles.isEmpty)
            }
            CommandGroup(replacing: .help) {
                Button("Ver la bienvenida") { model.presentWelcome() }
                Button("Calibrar la impresora…") { model.presentCalibration() }
                    .disabled(model.busy)
            }
        }

        Settings {
            PreferencesView()
                .environmentObject(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in Model.shared.open(urls) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// MARK: - Utilidades de sistema

enum Shell {
    @discardableResult
    static func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "\(error.localizedDescription)") }
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    static func printers() -> [String] {
        run("/usr/bin/lpstat", ["-e"]).output
            .split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func defaultPrinter() -> String? {
        let out = run("/usr/bin/lpstat", ["-d"]).output
        guard let r = out.range(of: ": ") else { return nil }
        let name = out[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// Envía un PDF a imprimir y devuelve el id del trabajo (p. ej. "Samsung_M2020_Series-321")
    static func lp(file: URL, printer: String, title: String, paper: String,
                   fit: Bool, copies: Int = 1, grayscale: Bool = false) -> (id: String?, error: String?) {
        var args = ["-d", printer, "-t", title, "-o", "media=\(paper)"]
        if fit { args += ["-o", "fit-to-page"] }
        if grayscale { args += ["-o", "ColorModel=Gray"] }
        if copies > 1 { args += ["-n", String(copies)] }
        args.append(file.path)
        let r = run("/usr/bin/lp", args)
        if r.status != 0 { return (nil, r.output.isEmpty ? "lp terminó con error \(r.status)" : r.output) }
        // Vale para "request id is X-12" y "el id de la petición es X-12"
        let pattern = NSRegularExpression.escapedPattern(for: printer) + "-[0-9]+"
        if let re = try? NSRegularExpression(pattern: pattern),
           let m = re.firstMatch(in: r.output, range: NSRange(r.output.startIndex..., in: r.output)),
           let range = Range(m.range, in: r.output) {
            return (String(r.output[range]), nil)
        }
        return (nil, nil)
    }

    static func jobPending(_ id: String, printer: String) -> Bool {
        run("/usr/bin/lpstat", ["-o", printer]).output
            .split(separator: "\n").contains { $0.hasPrefix(id + " ") }
    }

    /// true si el trabajo ya terminó pero quedó abortado/cancelado en la cola
    /// (detección por palabras clave, sin depender de un texto exacto del sistema)
    static func jobAborted(_ id: String, printer: String) -> Bool {
        let out = run("/usr/bin/lpstat", ["-W", "completed", "-o", printer]).output
        let lines = out.split(separator: "\n").filter { $0.hasPrefix(id + " ") }
        let lower = lines.joined(separator: " ").lowercased()
        return lower.contains("aborted") || lower.contains("canceled")
            || lower.contains("abortado") || lower.contains("cancelado")
            || lower.contains("anulado")
    }

    static func cancel(_ id: String) { run("/usr/bin/cancel", [id]) }
}

/// Notificaciones del sistema (solo funcionan cuando la app va dentro de su .app)
enum Notifier {
    static var available: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestPermission() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(_ title: String, _ body: String) {
        guard available else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}

/// Acceso directo en el menú «PDF» de la ventana Imprimir de cualquier app
enum PDFMenu {
    static let name = "Doble cara manual (M2022)"
    static var link: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/PDF Services", isDirectory: true)
            .appendingPathComponent(name)
    }

    static var installed: Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil
            || FileManager.default.fileExists(atPath: link.path)
    }

    /// El acceso directo existe y apunta a esta copia de la app
    static var pointsHere: Bool {
        guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else { return false }
        return URL(fileURLWithPath: dest).standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    static func set(_ on: Bool) {
        let fm = FileManager.default
        try? fm.removeItem(at: link)
        guard on else { return }
        try? fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.createSymbolicLink(at: link, withDestinationURL: Bundle.main.bundleURL)
    }
}

// MARK: - Modelo

enum Phase: Equatable {
    case idle
    case printingA
    case waitingFlip
    case printingB
    case done
    case failed(String)
}

@MainActor
final class Model: ObservableObject {
    static let shared = Model()
    private let defaults = UserDefaults.standard

    @Published var url: URL?
    @Published var doc: PDFDocument?
    @Published var phase: Phase = .idle
    @Published var printers: [String] = []
    @Published var recentFiles: [URL] = [] {
        didSet { defaults.set(recentFiles.map(\.path), forKey: "recentFiles") }
    }
    @Published var queue: [URL] = []

    // Ajustes (se recuerdan)
    @Published var printer: String { didSet { defaults.set(printer, forKey: "printer") } }
    @Published var paper: String { didSet { defaults.set(paper, forKey: "paper") } }
    /// true = al cargar un documento se preselecciona el papel según su tamaño
    @Published var autoPaper = true
    @Published var duplex: Bool { didSet { defaults.set(duplex, forKey: "duplex") } }
    @Published var reverseB: Bool { didSet { defaults.set(reverseB, forKey: "reverseB") } }
    @Published var rotateB: Bool { didSet { defaults.set(rotateB, forKey: "rotateB") } }
    @Published var padBlank: Bool { didSet { defaults.set(padBlank, forKey: "padBlank") } }
    @Published var fitToPage: Bool { didSet { defaults.set(fitToPage, forKey: "fitToPage") } }
    @Published var grayscale: Bool { didSet { defaults.set(grayscale, forKey: "grayscale") } }
    /// Margen en milímetros alrededor del contenido de cada hoja
    @Published var margin: Double { didSet { defaults.set(margin, forKey: "margin") } }
    /// Cómo se vuelven a meter las hojas: cara impresa hacia abajo (true) o hacia arriba
    @Published var faceDown: Bool { didSet { defaults.set(faceDown, forKey: "faceDown") } }
    /// Con el giro de 180° de la cara B, el taco se vuelve a meter tal cual sale de la impresora
    var reinsertAsIs: Bool { rotateB }
    @Published var showFirstTime: Bool { didSet { defaults.set(showFirstTime, forKey: "showFirstTime") } }
    @Published var notify: Bool { didSet { defaults.set(notify, forKey: "notify") } }
    @Published var welcomeShown: Bool { didSet { defaults.set(welcomeShown, forKey: "welcomeShown") } }
    @Published var pdfMenu: Bool {
        didSet {
            defaults.set(pdfMenu, forKey: "pdfMenu")
            PDFMenu.set(pdfMenu)
        }
    }

    // Estadísticas de uso
    @Published var jobsCount: Int { didSet { defaults.set(jobsCount, forKey: "jobsCount") } }
    @Published var sheetsSaved: Int { didSet { defaults.set(sheetsSaved, forKey: "sheetsSaved") } }

    // Perfiles de impresión
    @Published var profiles: [PrintProfile] = [] {
        didSet { if let d = try? JSONEncoder().encode(profiles) { defaults.set(d, forKey: "profiles") } }
    }

    // Ajustes por trabajo
    @Published var copies = 1
    @Published var booklet = false
    @Published var pagesPerSheet = 1
    @Published var pageMode: PageMode = .all {
        didSet {
            // Al pasar a «Elegir» se parte de lo que ya estaba elegido
            if pageMode == .custom && oldValue != .custom {
                customPages = PagePlan.format(PagePlan.selection(mode: oldValue, pageCount: pageCount,
                                                                from: fromPage, to: toPage, custom: customPages))
            }
        }
    }
    @Published var fromPage = 1
    @Published var toPage = 1
    @Published var customPages = ""

    // Ventanas
    @Published var showWelcome = false
    @Published var showCalibration = false
    @Published private(set) var calibrating = false

    private var currentJob: String?
    private var evenFile: URL?
    private var sheetsInfo = ""
    private var thumbs: [Int: NSImage] = [:]
    private var saved: (url: URL?, doc: PDFDocument?)?

    private init() {
        defaults.register(defaults: ["paper": "A4", "duplex": true, "reverseB": true,
                                     "rotateB": true, "padBlank": true, "fitToPage": false,
                                     "grayscale": false, "margin": 0.0,
                                     "faceDown": true, "showFirstTime": true, "notify": true,
                                     "welcomeShown": false, "pdfMenu": true])
        printer = defaults.string(forKey: "printer") ?? ""
        paper = defaults.string(forKey: "paper") ?? "A4"
        recentFiles = (defaults.stringArray(forKey: "recentFiles") ?? []).map { URL(fileURLWithPath: $0) }
        duplex = defaults.bool(forKey: "duplex")
        reverseB = defaults.bool(forKey: "reverseB")
        rotateB = defaults.bool(forKey: "rotateB")
        padBlank = defaults.bool(forKey: "padBlank")
        fitToPage = defaults.bool(forKey: "fitToPage")
        grayscale = defaults.bool(forKey: "grayscale")
        margin = defaults.double(forKey: "margin")
        faceDown = defaults.bool(forKey: "faceDown")
        showFirstTime = defaults.bool(forKey: "showFirstTime")
        notify = defaults.bool(forKey: "notify")
        welcomeShown = defaults.bool(forKey: "welcomeShown")
        jobsCount = defaults.integer(forKey: "jobsCount")
        sheetsSaved = defaults.integer(forKey: "sheetsSaved")
        if let data = defaults.data(forKey: "profiles"),
           let decoded = try? JSONDecoder().decode([PrintProfile].self, from: data) {
            profiles = decoded
        }
        // Activado por defecto: se crea (o se repara si la app cambió de sitio) al abrir la app,
        // salvo que el usuario lo haya quitado en Preferencias
        pdfMenu = defaults.bool(forKey: "pdfMenu")
        if pdfMenu && !PDFMenu.pointsHere { PDFMenu.set(true) }
        refreshPrinters()
    }

    var pageCount: Int { doc?.pageCount ?? 0 }
    var busy: Bool { phase == .printingA || phase == .printingB || phase == .waitingFlip }
    var title: String { url?.deletingPathExtension().lastPathComponent ?? "Documento" }
    /// La calibración siempre se hace a doble cara
    var effectiveDuplex: Bool { duplex || calibrating }
    var canPrint: Bool { doc != nil && !printer.isEmpty && !busy && !selection.isEmpty }
    /// Hay una cara B ya preparada y la impresión falló: se puede reintentar sin repetir la cara A
    var canReprintB: Bool {
        guard evenFile != nil else { return false }
        if case .failed = phase { return true }
        return false
    }

    /// Margen en puntos (72 pt = 25,4 mm)
    var marginPoints: CGFloat { CGFloat(margin) * 72.0 / 25.4 }

    static func displayName(_ printer: String) -> String { printer.replacingOccurrences(of: "_", with: " ") }

    /// Nombre de papel estándar para un tamaño de página (en puntos), tolerando un
    /// pequeño margen de error y el giro de la página.
    static func paperName(for size: CGSize) -> String? {
        let standards: [(String, CGSize)] = [
            ("A4",     CGSize(width: 595.28, height: 841.89)),
            ("Letter", CGSize(width: 612,    height: 792)),
            ("Legal",  CGSize(width: 612,    height: 1008)),
            ("A5",     CGSize(width: 419.53, height: 595.28)),
        ]
        let (w, h) = (size.width, size.height)
        return standards.first { s in
            abs(w - s.1.width) < 3 && abs(h - s.1.height) < 3
                || abs(w - s.1.height) < 3 && abs(h - s.1.width) < 3
        }?.0
    }

    /// Carpeta persistente para los PDFs generados (cara A/B, hoja de prueba).
    /// Se usa en vez de la carpeta temporal para poder reimprimir la cara B.
    static var workDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DobleCaraM2022", isDirectory: true)
    }

    func refreshPrinters() {
        let list = Shell.printers()
        printers = list
        if printer.isEmpty || !list.contains(printer) {
            printer = list.first { $0.lowercased().contains("m202") }
                ?? Shell.defaultPrinter().flatMap { list.contains($0) ? $0 : nil }
                ?? list.first ?? ""
        }
    }

    func load(_ u: URL) {
        guard !busy, !calibrating else {
            queue.append(u)  // hay una impresión en curso: se encola
            return
        }
        // Se lee entero en memoria: el menú PDF de imprimir pasa archivos temporales
        // que el sistema puede borrar en cuanto la app los abre.
        let scoped = u.startAccessingSecurityScopedResource()
        defer { if scoped { u.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: u), let d = PDFDocument(data: data) else {
            phase = .failed("No se pudo abrir «\(u.lastPathComponent)» como PDF.")
            return
        }
        if d.isLocked {
            phase = .failed("«\(u.lastPathComponent)» está protegido con contraseña.")
            return
        }
        setDocument(d, url: u)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Abre varios PDFs: el primero se carga y el resto se encolan
    func open(_ urls: [URL]) {
        let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        guard let first = pdfs.first else { return }
        if busy || calibrating {
            queue.append(contentsOf: pdfs)
        } else {
            load(first)
            queue.append(contentsOf: pdfs.dropFirst())
        }
    }

    /// Pasa al siguiente documento encolado (si lo hay)
    func advanceQueue() {
        guard !queue.isEmpty else { return }
        let u = queue.removeFirst()
        load(u)
    }

    private func setDocument(_ d: PDFDocument?, url u: URL?) {
        url = u
        doc = d
        thumbs = [:]
        pageMode = .all
        fromPage = 1
        toPage = max(1, d?.pageCount ?? 1)
        customPages = ""
        copies = 1
        phase = .idle
        evenFile = nil
        if autoPaper, let first = d?.page(at: 0) {
            let b = first.bounds(for: .mediaBox)
            let size = first.rotation % 180 == 0 ? b.size : CGSize(width: b.height, height: b.width)
            if let name = Self.paperName(for: size) { paper = name }
        }
        if let u, !recentFiles.contains(u) {
            recentFiles.insert(u, at: 0)
            if recentFiles.count > 10 { recentFiles.removeLast(recentFiles.count - 10) }
        }
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        if let dir = defaults.string(forKey: "lastDir"), !dir.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: dir)
        }
        if panel.runModal() == .OK, let u = panel.url {
            defaults.set(u.deletingLastPathComponent().path, forKey: "lastDir")
            load(u)
        }
    }

    /// Quita el documento actual y vacía la cola, dejando la app vacía.
    func clearDocuments() {
        guard !busy, !calibrating else { NSSound.beep(); return }
        setDocument(nil, url: nil)
        queue = []
    }

    func thumbnail(_ i: Int) -> NSImage? {
        if let t = thumbs[i] { return t }
        guard let page = doc?.page(at: i) else { return nil }
        let img = page.thumbnail(of: NSSize(width: 220, height: 300), for: .cropBox)
        thumbs[i] = img
        return img
    }

    // MARK: Páginas

    /// Páginas elegidas (índices desde 0)
    var selection: [Int] {
        PagePlan.selection(mode: pageMode, pageCount: pageCount, from: fromPage, to: toPage, custom: customPages)
    }

    func togglePage(_ i: Int) {
        guard !busy else { return }
        var set = Set(selection)
        if set.contains(i) { set.remove(i) } else { set.insert(i) }
        pageMode = .custom
        customPages = PagePlan.format(Array(set))
    }

    /// Hoja y cara en la que sale cada página (solo la primera copia)
    var sheetPlan: [Int: PagePlan.Slot] {
        PagePlan.sheetPlan(selection: selection, duplex: effectiveDuplex)
    }

    /// Secuencia completa (con copias); nil = página en blanco
    private func sequence() -> [Int?] {
        PagePlan.sequence(selection: selection, copies: copies, padBlank: padBlank)
    }

    var sheetCount: Int {
        if booklet && effectiveDuplex { return (selection.count + 3) / 4 }
        if pagesPerSheet > 1 {
            let sides = (selection.count + pagesPerSheet - 1) / pagesPerSheet
            return effectiveDuplex ? (sides + 1) / 2 : sides
        }
        return effectiveDuplex ? (sequence().count + 1) / 2 : selection.count * max(1, copies)
    }

    /// "8 páginas → 4 hojas"
    var summary: String {
        let n = selection.count
        guard doc != nil else { return "" }
        guard n > 0 else { return "Ninguna página elegida" }
        if booklet && effectiveDuplex {
            let sheets = (n + 3) / 4
            return "Folleto: \(PagePlan.plural(n, "página", "páginas")) → \(PagePlan.plural(sheets, "hoja", "hojas"))"
        }
        if pagesPerSheet > 1 {
            return "\(pagesPerSheet) por hoja: \(PagePlan.plural(n, "página", "páginas")) → \(PagePlan.plural(sheetCount, "hoja", "hojas"))"
        }
        let per = effectiveDuplex ? (n + 1) / 2 : n
        var s = "\(PagePlan.plural(n, "página", "páginas")) → \(PagePlan.plural(per, "hoja", "hojas"))"
        if copies > 1 { s += " × \(copies) copias = \(PagePlan.plural(sheetCount, "hoja", "hojas"))" }
        return s
    }

    /// Paso actual de la barra de pasos
    var currentStep: Int {
        if !effectiveDuplex {
            return phase == .done ? 2 : (doc == nil ? 0 : 1)
        }
        switch phase {
        case .idle, .failed: return doc == nil ? 0 : 1
        case .printingA: return 1
        case .waitingFlip: return 2
        case .printingB: return 3
        case .done: return 4
        }
    }

    private func makePDF(_ indices: [Int?], rotate: Bool, name: String, source: PDFDocument? = nil) -> URL? {
        guard let src = source ?? doc else { return nil }
        let dir = Self.workDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: file)

        // Tamaño de una página tal y como se ve (con su giro aplicado)
        func size(of page: PDFPage?) -> CGSize {
            guard let page else { return CGSize(width: 595, height: 842) }
            let b = page.bounds(for: .mediaBox)
            return page.rotation % 180 == 0 ? b.size : CGSize(width: b.height, height: b.width)
        }
        let refIndex = indices.compactMap { $0 }.last ?? 0
        let refSize = size(of: src.page(at: refIndex))
        var box = CGRect(origin: .zero, size: refSize)
        guard let ctx = CGContext(file as CFURL, mediaBox: &box, nil) else { return nil }

        // Se redibuja cada página en un PDF nuevo. El giro de 180° se dibuja dentro
        // de la página (el sistema de impresión ignora la marca /Rotate de 180°).
        for i in indices {
            let page = i.flatMap { src.page(at: $0) }
            var media = CGRect(origin: .zero, size: page == nil ? refSize : size(of: page))
            let info = [kCGPDFContextMediaBox as String: Data(bytes: &media, count: MemoryLayout<CGRect>.size)] as CFDictionary
            ctx.beginPDFPage(info)
            if let page {
                ctx.saveGState()
                let inset = marginPoints
                if inset > 0 {
                    let scale = min((media.width - 2 * inset) / media.width,
                                    (media.height - 2 * inset) / media.height)
                    if scale > 0 {
                        let dw = (media.width - media.width * scale) / 2
                        let dh = (media.height - media.height * scale) / 2
                        ctx.translateBy(x: dw, y: dh)
                        ctx.scaleBy(x: scale, y: scale)
                    }
                }
                if rotate {
                    ctx.translateBy(x: media.width, y: media.height)
                    ctx.rotate(by: .pi)
                }
                page.draw(with: .mediaBox, to: ctx)
                ctx.restoreGState()
            }
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return file
    }

    /// Genera el PDF del folleto: 2 páginas por cara, en orden de imposición.
    private func makeBookletPDF() -> URL? {
        guard let doc else { return nil }
        let sel = selection
        guard !sel.isEmpty else { return nil }
        let order = PagePlan.bookletOrder(pageCount: sel.count)
        func pageSize(_ slot: Int?) -> CGSize {
            guard let slot, let p = doc.page(at: sel[slot]) else { return CGSize(width: 595, height: 842) }
            let b = p.bounds(for: .mediaBox)
            return p.rotation % 180 == 0 ? b.size : CGSize(width: b.height, height: b.width)
        }
        let ref = pageSize(order.first ?? nil)
        let sideSize = CGSize(width: ref.width * 2, height: ref.height)
        var box = CGRect(origin: .zero, size: sideSize)
        let dir = Self.workDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(title) - folleto.pdf")
        try? FileManager.default.removeItem(at: file)
        guard let ctx = CGContext(file as CFURL, mediaBox: &box, nil) else { return nil }

        var side: [Int?] = []
        for (k, slot) in order.enumerated() {
            side.append(slot)
            if k % 2 == 1 {
                ctx.beginPDFPage(nil)
                for (s, si) in side.enumerated() {
                    let half = CGSize(width: ref.width, height: ref.height)
                    ctx.saveGState()
                    ctx.translateBy(x: CGFloat(s) * half.width, y: 0)
                    if let si, let page = doc.page(at: sel[si]) {
                        let sz = pageSize(si)
                        let scale = min(half.width / sz.width, half.height / sz.height)
                        let dw = (half.width - sz.width * scale) / 2
                        let dh = (half.height - sz.height * scale) / 2
                        ctx.translateBy(x: dw, y: dh)
                        ctx.scaleBy(x: scale, y: scale)
                        page.draw(with: .mediaBox, to: ctx)
                    }
                    ctx.restoreGState()
                }
                ctx.endPDFPage()
                side = []
            }
        }
        ctx.closePDF()
        return file
    }

    /// Genera el PDF con varias páginas por hoja (N-up: 2 o 4).
    private func makeNUpPDF() -> URL? {
        guard let doc else { return nil }
        let sel = selection
        guard !sel.isEmpty else { return nil }
        let n = pagesPerSheet
        let grid = PagePlan.nupGrid(pagesPerSheet: n)
        let cols = grid.cols
        let rows = grid.rows

        func pageSize(_ i: Int) -> CGSize {
            guard let p = doc.page(at: i) else { return CGSize(width: 595, height: 842) }
            let b = p.bounds(for: .mediaBox)
            return p.rotation % 180 == 0 ? b.size : CGSize(width: b.height, height: b.width)
        }
        let ref = pageSize(sel.first ?? 0)
        let sheetSize = CGSize(width: ref.width * CGFloat(cols), height: ref.height * CGFloat(rows))
        var box = CGRect(origin: .zero, size: sheetSize)
        let dir = Self.workDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(title) - \(n)up.pdf")
        try? FileManager.default.removeItem(at: file)
        guard let ctx = CGContext(file as CFURL, mediaBox: &box, nil) else { return nil }

        func drawBatch(_ batch: [Int]) {
            ctx.beginPDFPage(nil)
            for (s, idx) in batch.enumerated() {
                let col = s % cols, row = s / cols
                let cell = CGSize(width: ref.width, height: ref.height)
                ctx.saveGState()
                ctx.translateBy(x: CGFloat(col) * cell.width,
                                y: sheetSize.height - CGFloat(row + 1) * cell.height)
                if let page = doc.page(at: idx) {
                    let sz = pageSize(idx)
                    let scale = min(cell.width / sz.width, cell.height / sz.height)
                    let dw = (cell.width - sz.width * scale) / 2
                    let dh = (cell.height - sz.height * scale) / 2
                    ctx.translateBy(x: dw, y: dh)
                    ctx.scaleBy(x: scale, y: scale)
                    page.draw(with: .mediaBox, to: ctx)
                }
                ctx.restoreGState()
            }
            ctx.endPDFPage()
        }

        var batch: [Int] = []
        for i in sel {
            batch.append(i)
            if batch.count == n { drawBatch(batch); batch = [] }
        }
        if !batch.isEmpty { drawBatch(batch) }
        ctx.closePDF()
        return file
    }

    // MARK: Impresión

    func start() {
        guard canPrint else { return }
        if booklet && effectiveDuplex {
            startBooklet()
            return
        }
        if pagesPerSheet > 1 {
            startNUp()
            return
        }
        if notify { Notifier.requestPermission() }
        let seq = sequence()
        if !effectiveDuplex || seq.count <= 1 {
            printSingle()
            return
        }
        let odd = stride(from: 0, to: seq.count, by: 2).map { seq[$0] }
        var even = stride(from: 1, to: seq.count, by: 2).map { seq[$0] }
        if reverseB { even.reverse() }
        guard let oddURL = makePDF(odd, rotate: false, name: "\(title) - cara A.pdf"),
              let evenURL = makePDF(even, rotate: rotateB, name: "\(title) - cara B.pdf") else {
            phase = .failed("No se pudieron preparar las páginas.")
            return
        }
        evenFile = evenURL
        let removeLast = seq.count % 2 == 1  // sin dorso en blanco: retirar la última hoja
        sheetsInfo = removeLast
            ? "Antes de meterlas, retira la hoja de ARRIBA del montón (solo lleva la última página) y apártala."
            : ""
        send(oddURL, suffix: "cara A", printing: .printingA, next: .waitingFlip)
    }

    func printSideB() {
        guard let evenFile else { return }
        if case .failed = phase {
            phase = .waitingFlip  // reintento desde un fallo
        }
        guard phase == .waitingFlip else { return }
        send(evenFile, suffix: "cara B", printing: .printingB, next: .done)
    }

    private func startBooklet() {
        if notify { Notifier.requestPermission() }
        guard let pdf = makeBookletPDF() else {
            phase = .failed("No se pudo preparar el folleto.")
            return
        }
        printDuplexPDF(pdf)
    }

    private func startNUp() {
        if notify { Notifier.requestPermission() }
        guard let pdf = makeNUpPDF() else {
            phase = .failed("No se pudo preparar el documento.")
            return
        }
        if effectiveDuplex {
            printDuplexPDF(pdf)
        } else {
            sendSingleFile(pdf)
        }
    }

    /// Imprime un PDF ya generado a doble cara (divide en caras A y B)
    private func printDuplexPDF(_ pdf: URL) {
        guard let pd = PDFDocument(url: pdf) else {
            phase = .failed("No se pudo preparar el documento.")
            return
        }
        let sides = pd.pageCount
        let odd = Array(stride(from: 0, to: sides, by: 2)).map { Optional($0) }
        var even = Array(stride(from: 1, to: sides, by: 2)).map { Optional($0) }
        if reverseB { even.reverse() }
        guard let oddURL = makePDF(odd, rotate: false, name: "\(title) - cara A.pdf", source: pd),
              let evenURL = makePDF(even, rotate: rotateB, name: "\(title) - cara B.pdf", source: pd) else {
            phase = .failed("No se pudieron preparar las páginas.")
            return
        }
        evenFile = evenURL
        sheetsInfo = ""
        send(oddURL, suffix: "cara A", printing: .printingA, next: .waitingFlip)
    }

    private func printSingle() {
        guard let file = makePDF(selection.map { Optional($0) }, rotate: false, name: "\(title).pdf") else {
            phase = .failed("No se pudieron preparar las páginas.")
            return
        }
        sendSingleFile(file)
    }

    /// Imprime un PDF ya generado a una sola cara (o sin dúplex)
    private func sendSingleFile(_ file: URL) {
        let p = printer, paper = paper, fit = fitToPage, n = copies, t = title, g = grayscale
        phase = .printingA
        Task {
            let r = await Task.detached { Shell.lp(file: file, printer: p, title: t, paper: paper, fit: fit, copies: n, grayscale: g) }.value
            if let e = r.error { phase = .failed(e); return }
            currentJob = r.id
            let ok = await waitForJob()
            guard phase == .printingA else { return }  // cancelado
            if !ok { phase = .failed("La impresión no terminó a tiempo. Revisa la impresora."); return }
            phase = .done
            if !calibrating { recordJob() }
            if notify { Notifier.post("Impresión terminada", "«\(t)» ya está impreso.") }
        }
    }

    private func send(_ file: URL, suffix: String, printing: Phase, next: Phase) {
        let p = printer, paper = paper, fit = fitToPage, t = "\(title) - \(suffix)", g = grayscale
        phase = printing
        Task {
            let r = await Task.detached { Shell.lp(file: file, printer: p, title: t, paper: paper, fit: fit, grayscale: g) }.value
            if let e = r.error { phase = .failed(e); return }
            currentJob = r.id
            let ok = await waitForJob()
            guard phase == printing else { return }  // cancelado
            if !ok { phase = .failed("La impresión no terminó a tiempo. Revisa la impresora."); return }
            phase = next
            if next == .waitingFlip {
                if notify {
                    Notifier.post("Cara A terminada",
                                  reinsertAsIs
                                      ? "Vuelve a meter \(PagePlan.plural(sheetCount, "la hoja", "las hojas")) tal cual salen, sin darles la vuelta, y pulsa «Imprimir cara B»."
                                      : "Vuelve a meter \(PagePlan.plural(sheetCount, "la hoja", "las hojas")) y pulsa «Imprimir cara B».")
                }
                NSApp.activate(ignoringOtherApps: true)
                NSApp.requestUserAttention(.criticalRequest)
                NSSound(named: "Glass")?.play()
            } else if next == .done {
                if !calibrating { recordJob() }
                if notify && !calibrating {
                    Notifier.post("Impresión terminada", "«\(title)» ya está impreso a doble cara.")
                }
            }
        }
    }

    private func waitForJob() async -> Bool {
        guard let id = currentJob else {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            return true
        }
        let p = printer
        let start = Date()
        while Date().timeIntervalSince(start) < 900 {
            let pending = await Task.detached { Shell.jobPending(id, printer: p) }.value
            if !pending { break }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
        let finished = Date().timeIntervalSince(start) < 900
        currentJob = nil
        if !finished { return false }
        return await !Task.detached { Shell.jobAborted(id, printer: p) }.value
    }

    func cancel() {
        if let id = currentJob {
            Task.detached { Shell.cancel(id) }
        }
        currentJob = nil
        phase = .idle
    }

    func reset() { phase = .idle }

    private func recordJob() {
        jobsCount += 1
        if effectiveDuplex {
            sheetsSaved += max(0, selection.count * max(1, copies) - sheetCount)
        }
    }

    // MARK: Perfiles

    func apply(_ p: PrintProfile) {
        printer = p.printer
        paper = p.paper
        duplex = p.duplex
        reverseB = p.reverseB
        rotateB = p.rotateB
        padBlank = p.padBlank
        fitToPage = p.fitToPage
        faceDown = p.faceDown
        grayscale = p.grayscale
        margin = p.margin
    }

    func saveProfile(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        profiles.append(PrintProfile(name: trimmed, printer: printer, paper: paper,
                                     duplex: duplex, reverseB: reverseB, rotateB: rotateB,
                                     padBlank: padBlank, fitToPage: fitToPage,
                                     faceDown: faceDown, grayscale: grayscale, margin: margin))
    }

    func removeProfile(_ p: PrintProfile) {
        profiles.removeAll { $0.id == p.id }
    }

    var flipSteps: [String] {
        let take = "Espera a que la impresora pare y recoge \(PagePlan.plural(sheetCount, "la hoja", "las hojas")) de la bandeja de salida."
        var s: [String]
        if reinsertAsIs {
            // La cara B ya va girada 180°: no hay que voltear ni girar el taco
            s = [take,
                 "Mételas en la bandeja de entrada TAL CUAL SALEN: sin darles la vuelta y sin girarlas.",
                 "No cambies el orden de las hojas."]
        } else {
            s = [take,
                 "No cambies el orden: mueve el taco entero.",
                 "Mételo en la bandeja de entrada con la cara impresa hacia \(faceDown ? "ABAJO" : "ARRIBA").",
                 "La parte de ARRIBA del texto tiene que entrar primero en la impresora."]
        }
        if !sheetsInfo.isEmpty { s.insert(sheetsInfo, at: 1) }
        return s
    }

    // MARK: Ventanas de ayuda

    func presentWelcome() {
        focusMainWindow()
        showWelcome = true
    }

    func presentCalibration() {
        guard !busy else { NSSound.beep(); return }
        focusMainWindow()
        showCalibration = true
    }

    private func focusMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.title == "Doble Cara M2022" }?.makeKeyAndOrderFront(nil)
    }

    // MARK: Calibración

    /// Guarda el documento abierto y carga la hoja de prueba de 2 hojas
    func beginCalibration() {
        guard !busy else { return }
        if !calibrating { saved = (url, doc) }
        calibrating = true
        loadTestPage(sheets: 2)
    }

    /// Deja la app como estaba antes de calibrar
    func endCalibration() {
        guard calibrating else { return }
        if busy { cancel() }
        calibrating = false
        if let s = saved { setDocument(s.doc, url: s.url) }
        saved = nil
    }

    // MARK: Hoja de prueba

    /// Crea un PDF de prueba. 1 hoja = páginas 1-2; 2 hojas = páginas 1-4 (comprueba también el orden).
    func loadTestPage(sheets: Int = 1) {
        let dir = Self.workDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("Hoja de prueba doble cara.pdf")
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let ctx = CGContext(file as CFURL, mediaBox: &box, nil) else { return }
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        func attrs(_ font: NSFont, _ color: NSColor = .black) -> [NSAttributedString.Key: Any] {
            [.font: font, .foregroundColor: color, .paragraphStyle: center]
        }
        for p in 1...(sheets * 2) {
            let sheet = (p + 1) / 2, side = p % 2 == 1 ? "A" : "B"
            ctx.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            ("↑  ARRIBA  ↑" as NSString).draw(in: CGRect(x: 0, y: 750, width: 595, height: 50),
                                               withAttributes: attrs(.boldSystemFont(ofSize: 30)))
            ("PÁGINA" as NSString).draw(in: CGRect(x: 0, y: 610, width: 595, height: 50),
                                        withAttributes: attrs(.boldSystemFont(ofSize: 36), .darkGray))
            ("\(p)" as NSString).draw(in: CGRect(x: 0, y: 360, width: 595, height: 260),
                                      withAttributes: attrs(.boldSystemFont(ofSize: 220)))
            ("Hoja \(sheet) · cara \(side)" as NSString).draw(in: CGRect(x: 0, y: 300, width: 595, height: 50),
                                                             withAttributes: attrs(.systemFont(ofSize: 30), .darkGray))
            let hint = side == "A"
                ? "Por detrás de esta hoja debe salir la página \(p + 1),\nen el mismo sentido al girarla como un libro."
                : "Esta página debe estar detrás de la página \(p - 1)\ny leerse en el mismo sentido."
            (hint as NSString).draw(in: CGRect(x: 60, y: 90, width: 475, height: 80),
                                    withAttributes: attrs(.systemFont(ofSize: 16), .darkGray))
            NSGraphicsContext.restoreGraphicsState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
        guard let d = PDFDocument(url: file) else { return }
        setDocument(d, url: file)
    }
}

// MARK: - Vista principal

struct ContentView: View {
    @EnvironmentObject var m: Model
    @AppStorage("showPageGrid") private var showPages = false
    @AppStorage("largeUI") private var largeUI = false

    var body: some View {
        HStack(spacing: 0) {
            PreviewPane(showPages: $showPages)
                .frame(minWidth: 360)
            Divider()
            VStack(spacing: 0) {
                StepBar()
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                Divider()
                panel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                ActionBar()
            }
            .frame(width: 400)
        }
        .environment(\.dynamicTypeSize, largeUI ? .xxxLarge : .large)
        .onOpenURL { m.load($0) }
        .onAppear { if !m.welcomeShown { m.showWelcome = true } }
        .onChange(of: m.pageMode) { mode in
            if mode != .all { showPages = true }
        }
        .background(EmptyView().sheet(isPresented: $m.showWelcome) {
            WelcomeSheet().environmentObject(m)
        })
        .background(EmptyView().sheet(isPresented: $m.showCalibration) {
            CalibrationSheet().environmentObject(m)
        })
    }

    @ViewBuilder private var panel: some View {
        switch m.phase {
        case .printingA, .printingB: PrintingPanel()
        case .waitingFlip: FlipPanel()
        case .done: DonePanel()
        case .idle, .failed: SettingsForm()
        }
    }
}

// MARK: Barra de pasos

struct StepBar: View {
    @EnvironmentObject var m: Model

    var body: some View {
        let steps = m.effectiveDuplex
            ? [String(localized: "Documento"), String(localized: "Cara A"), String(localized: "Meter hojas"), String(localized: "Cara B")]
            : [String(localized: "Documento"), String(localized: "Imprimir")]
        let current = m.currentStep
        HStack(alignment: .top, spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, name in
                if i > 0 {
                    Capsule()
                        .fill(i <= current ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 11)
                }
                StepDot(number: i + 1, name: name, state: i < current ? .done : (i == current ? .active : .pending))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct StepDot: View {
    enum State { case done, active, pending }
    let number: Int
    let name: String
    let state: State

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().fill(state == .done ? Color.accentColor
                              : state == .active ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                Circle().strokeBorder(state == .pending ? Color.secondary.opacity(0.4) : Color.accentColor, lineWidth: 1.5)
                if state == .done {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(state == .active ? Color.accentColor : .secondary)
                }
            }
            .frame(width: 24, height: 24)
            Text(name)
                .font(.caption2.weight(state == .active ? .semibold : .regular))
                .foregroundStyle(state == .pending ? .secondary : .primary)
                .fixedSize()
        }
    }
}

// MARK: Vista previa

struct PDFPreview: NSViewRepresentable {
    let doc: PDFDocument?
    /// Página que se ve (desde 1). Cambia al desplazarse y, al cambiarla, la vista salta a ella.
    @Binding var page: Int
    /// Factor de zoom (0 = ajustar al ancho)
    @Binding var zoom: CGFloat
    /// Selección a resaltar (resultado de búsqueda)
    @Binding var highlight: PDFSelection?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displaysPageBreaks = true
        v.backgroundColor = .underPageBackgroundColor
        context.coordinator.view = v
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.pageChanged(_:)),
                                               name: .PDFViewPageChanged, object: v)
        return v
    }

    func updateNSView(_ v: PDFView, context: Context) {
        context.coordinator.parent = self
        if v.document !== doc { v.document = doc }
        if zoom == 0 {
            if !v.autoScales { v.autoScales = true }
        } else {
            if v.autoScales { v.autoScales = false }
            if v.scaleFactor != zoom { v.scaleFactor = zoom }
        }
        if let h = highlight, h !== context.coordinator.appliedSelection {
            context.coordinator.appliedSelection = h
            v.setCurrentSelection(h, animate: true)
            v.go(to: h)
        }
        guard let doc, let current = v.currentPage else { return }
        if doc.index(for: current) + 1 != page, let target = doc.page(at: page - 1) {
            v.go(to: target)
        }
    }

    final class Coordinator: NSObject {
        var parent: PDFPreview
        weak var view: PDFView?
        weak var appliedSelection: PDFSelection?
        init(_ parent: PDFPreview) { self.parent = parent }

        @objc func pageChanged(_ n: Notification) {
            guard let v = view, let doc = v.document, let current = v.currentPage else { return }
            let i = doc.index(for: current) + 1
            if parent.page != i {
                DispatchQueue.main.async { self.parent.page = i }
            }
        }
    }
}

/// Campo numérico pequeño con flechas; escribe el número o usa las flechas
struct NumberField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var width: CGFloat = 44

    var body: some View {
        let clamped = Binding<Int>(
            get: { value },
            set: { value = min(max($0, range.lowerBound), range.upperBound) })
        HStack(spacing: 2) {
            TextField("", value: clamped, format: .number.grouping(.never))
                .labelsHidden()
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
                .fixedSize()
            Stepper("", value: clamped, in: range)
                .labelsHidden()
        }
    }
}

/// Barra inferior de la vista previa: « Página [3] de 9 »
struct PageNavigator: View {
    @Binding var page: Int
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Button { page = max(1, page - 1) } label: { Image(systemName: "chevron.left") }
                .disabled(page <= 1)
                .help("Página anterior")
            Text("Página")
            TextField("", value: Binding(get: { page }, set: { page = min(max($0, 1), max(1, count)) }),
                      format: .number.grouping(.never))
                .labelsHidden()
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .frame(width: 44)
                .fixedSize()
                .help("Escribe un número de página y pulsa Intro")
            Text("de \(count)")
            Button { page = min(count, page + 1) } label: { Image(systemName: "chevron.right") }
                .disabled(page >= count)
                .help("Página siguiente")
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }
}

/// Insignia superpuesta a la vista previa: cara/hoja de la página actual según
/// la configuración (dúplex, giro, folleto o N-up).
struct FaceBadge: View {
    let slot: PagePlan.Slot?
    let duplex: Bool
    let rotateB: Bool
    let pagesPerSheet: Int
    let booklet: Bool

    var body: some View {
        if booklet || pagesPerSheet > 1 {
            Text(pagesPerSheet > 1 ? "\(pagesPerSheet) páginas por hoja" : "Folleto: 2 páginas por hoja")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.orange))
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        } else if let slot {
            let sideB = duplex && slot.sideB
            HStack(spacing: 8) {
                Text(duplex ? "Hoja \(slot.sheet) · Cara \(sideB ? "B" : "A")" : "Hoja \(slot.sheet)")
                    .font(.caption.bold())
                if sideB && rotateB {
                    Label("girada 180°", systemImage: "rotate.right")
                        .font(.caption2)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(sideB ? Color.orange : Color.accentColor))
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        }
    }
}

struct PreviewPane: View {
    @EnvironmentObject var m: Model
    @Binding var showPages: Bool
    @State private var dropTargeted = false
    @State private var page = 1
    @State private var zoom: CGFloat = 0
    @State private var query = ""
    @State private var highlight: PDFSelection?

    var body: some View {
        ZStack {
            if m.doc != nil {
                VStack(spacing: 0) {
                    HStack {
                        Picker("Vista", selection: $showPages) {
                            Text("Vista previa").tag(false)
                            Text("Hojas").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        .help("«Hojas» muestra qué páginas se imprimen y en qué hoja y cara sale cada una")
                        Spacer()
                        Text(m.summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    Divider()
                    if showPages {
                        PagesGrid()
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Buscar en el documento", text: $query)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(doSearch)
                            if !query.isEmpty {
                                Button { query = ""; highlight = nil } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        PDFPreview(doc: m.doc, page: $page, zoom: $zoom, highlight: $highlight)
                            .overlay(alignment: .topTrailing) {
                                FaceBadge(slot: m.sheetPlan[page - 1],
                                          duplex: m.effectiveDuplex,
                                          rotateB: m.rotateB,
                                          pagesPerSheet: m.pagesPerSheet,
                                          booklet: m.booklet)
                                    .padding(10)
                            }
                        Divider()
                        HStack {
                            Button { zoom = max(0.25, (zoom == 0 ? 1 : zoom) / 1.25) } label: {
                                Image(systemName: "minus.magnifyingglass")
                            }
                            .buttonStyle(.borderless)
                            .help("Reducir")
                            Button("Ajustar") { zoom = 0 }
                                .buttonStyle(.borderless)
                                .help("Ajustar al ancho")
                            Button { zoom = min(8, (zoom == 0 ? 1 : zoom) * 1.25) } label: {
                                Image(systemName: "plus.magnifyingglass")
                            }
                            .buttonStyle(.borderless)
                            .help("Ampliar")
                            Spacer()
                            PageNavigator(page: $page, count: m.pageCount)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                    }
                }
            } else {
                EmptyDropView()
            }
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(10)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            m.open(urls)
            return true
        } isTargeted: { dropTargeted = $0 }
        .onReceive(m.$doc) { _ in page = 1 }
    }

    private func doSearch() {
        guard let doc = m.doc, !query.isEmpty else { return }
        let results = doc.findString(query, withOptions: [.caseInsensitive])
        if let first = results.first {
            highlight = first
            if let p = first.pages.first {
                page = doc.index(for: p) + 1
            }
        }
    }
}

struct EmptyDropView: View {
    @EnvironmentObject var m: Model

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.secondary)
            Text("Arrastra aquí un PDF")
                .font(.title2.weight(.semibold))
            Text("o ábrelo desde Finder con clic derecho → Abrir con → Doble Cara M2022")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 280)
            Button("Abrir PDF…") { m.openPanel() }
                .controlSize(.large)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

/// Miniaturas de todas las páginas: las que se imprimen llevan su hoja y cara,
/// las que no, salen apagadas. Clic en una para quitarla o añadirla.
struct PagesGrid: View {
    @EnvironmentObject var m: Model

    @ViewBuilder var body: some View {
        if m.pagesPerSheet > 1 {
            SheetsGrid()
        } else {
            individualPages
        }
    }

    private var individualPages: some View {
        let plan = m.sheetPlan
        return VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 14)], spacing: 18) {
                    ForEach(0..<m.pageCount, id: \.self) { i in
                        PageThumb(index: i, slot: plan[i], duplex: m.effectiveDuplex)
                            .onTapGesture { m.togglePage(i) }
                    }
                }
                .padding(16)
            }
            Divider()
            HStack(spacing: 14) {
                if m.effectiveDuplex {
                    LegendSwatch(color: .accentColor, text: "Cara A")
                    LegendSwatch(color: .orange, text: "Cara B")
                }
                LegendSwatch(color: .secondary.opacity(0.35), text: "No se imprime")
                Spacer()
                Text("Clic en una página para quitarla o añadirla")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

/// Vista de «Hojas» para impresión N-up: muestra cada cara con sus páginas
/// dispuestas en la rejilla en que se imprimirán.
struct SheetsGrid: View {
    @EnvironmentObject var m: Model

    var body: some View {
        let sel = m.selection
        let n = m.pagesPerSheet
        let grid = PagePlan.nupGrid(pagesPerSheet: n)
        let sides = stride(from: 0, to: sel.count, by: n).map { Array(sel[$0..<min($0 + n, sel.count)]) }

        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    ForEach(Array(sides.enumerated()), id: \.offset) { k, pages in
                        SheetCard(side: k, pages: pages, cols: grid.cols, rows: grid.rows, duplex: m.effectiveDuplex)
                    }
                }
                .padding(16)
            }
            Divider()
            HStack(spacing: 14) {
                if m.effectiveDuplex {
                    LegendSwatch(color: .accentColor, text: "Cara A")
                    LegendSwatch(color: .orange, text: "Cara B")
                }
                LegendSwatch(color: .secondary.opacity(0.35), text: "En blanco")
                Spacer()
                Text("Clic en una página para quitarla o añadirla")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

/// Una cara (o hoja) con N páginas en rejilla, tal como se imprimirá.
struct SheetCard: View {
    @EnvironmentObject var m: Model
    let side: Int
    let pages: [Int]
    let cols: Int
    let rows: Int
    let duplex: Bool

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: cols)
        let sheet = side / 2 + 1
        let isBack = duplex && side % 2 == 1

        VStack(spacing: 7) {
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(0..<(cols * rows), id: \.self) { i in
                    if i < pages.count {
                        SheetPageCell(index: pages[i])
                    } else {
                        Rectangle().fill(Color.secondary.opacity(0.15))
                            .aspectRatio(0.707, contentMode: .fit)
                    }
                }
            }
            .padding(10)
            .background(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isBack ? Color.orange : Color.accentColor, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)

            HStack(spacing: 6) {
                Text(duplex ? "Hoja \(sheet) · Cara \(isBack ? "B" : "A")" : "Hoja \(side + 1)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(isBack ? Color.orange : Color.accentColor))
                if isBack && m.rotateB {
                    Label("girada 180°", systemImage: "rotate.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Miniatura de una página dentro de una hoja N-up.
struct SheetPageCell: View {
    @EnvironmentObject var m: Model
    let index: Int

    var body: some View {
        let on = m.selection.contains(index)
        VStack(spacing: 2) {
            Group {
                if let img = m.thumbnail(index) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .rotationEffect(.degrees(m.rotateB && on ? 180 : 0))
                } else {
                    Rectangle().fill(Color.white).aspectRatio(0.707, contentMode: .fit)
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color.white)
            Text("\(index + 1)")
                .font(.caption2)
                .foregroundStyle(on ? .primary : .secondary)
        }
        .opacity(on ? 1 : 0.35)
        .saturation(on && !m.grayscale ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture { m.togglePage(index) }
        .help(on ? "Clic para NO imprimir esta página" : "Clic para imprimir esta página")
    }
}

struct LegendSwatch: View {
    let color: Color
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(text)
        }
    }
}

struct PageThumb: View {
    @EnvironmentObject var m: Model
    let index: Int
    let slot: PagePlan.Slot?
    let duplex: Bool

    private var tint: Color { slot?.sideB == true ? .orange : .accentColor }

    var body: some View {
        let on = slot != nil
        VStack(spacing: 6) {
            Group {
                if let img = m.thumbnail(index) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .rotationEffect(.degrees(slot?.sideB == true && m.rotateB ? 180 : 0))
                } else {
                    Rectangle().fill(Color.white).aspectRatio(0.707, contentMode: .fit)
                }
            }
            .frame(height: 132)
            .background(Color.white)
            .overlay(Rectangle().strokeBorder(on ? tint : Color.secondary.opacity(0.3), lineWidth: on ? 2.5 : 1))
            .shadow(color: .black.opacity(on ? 0.18 : 0.05), radius: 3, y: 1)
            .opacity(on ? 1 : 0.4)
            .saturation(on && !m.grayscale ? 1 : 0)
            .overlay(alignment: .top) {
                if let slot {
                    HStack(spacing: 4) {
                        Text(duplex ? "Hoja \(slot.sheet) · \(slot.sideB ? "B" : "A")" : "Hoja \(slot.sheet)")
                        if slot.sideB && m.rotateB {
                            Image(systemName: "rotate.right")
                        }
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(tint))
                    .offset(y: -8)
                }
            }
            Text(on ? "Página \(index + 1)" : "Página \(index + 1) · no")
                .font(.caption)
                .foregroundStyle(on ? .primary : .secondary)
        }
        .contentShape(Rectangle())
        .help(on ? "Clic para NO imprimir esta página" : "Clic para imprimir esta página")
        .accessibilityLabel("Página \(index + 1), \(on ? "se imprime" : "no se imprime")")
    }
}

// MARK: Ajustes

struct SettingsForm: View {
    @EnvironmentObject var m: Model
    @AppStorage("advancedOpen") private var advancedOpen = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "doc.richtext").foregroundStyle(.secondary)
                    Text(m.doc == nil ? "Ningún documento" : m.title)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if m.doc != nil {
                        Text(PagePlan.plural(m.pageCount, "pág.", "pág.")).foregroundStyle(.secondary)
                    }
                    Button { m.openPanel() } label: { Image(systemName: "folder") }
                        .buttonStyle(.borderless).help("Abrir otro PDF")
                    if m.doc != nil {
                        Button { m.clearDocuments() } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .help("Quitar el documento actual y la cola")
                    }
                }
                if m.printers.isEmpty {
                    HStack {
                        Label("No se encontró ninguna impresora", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button { m.refreshPrinters() } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.borderless).help("Buscar impresoras otra vez")
                    }
                } else {
                    PrinterPicker()
                }
            }

            Section("Qué imprimir") {
                Picker("Páginas", selection: $m.pageMode) {
                    Text("Todas").tag(PageMode.all)
                    Text("Desde–hasta").tag(PageMode.range)
                    Text("Elegir").tag(PageMode.custom)
                }
                .pickerStyle(.segmented)
                .disabled(m.doc == nil)

                if m.pageMode == .range {
                    HStack(spacing: 6) {
                        Text("Desde")
                        NumberField(value: $m.fromPage, range: 1...max(1, m.pageCount))
                        Text("hasta")
                            .padding(.leading, 6)
                        NumberField(value: $m.toPage, range: 1...max(1, m.pageCount))
                        Spacer()
                        Text("de \(m.pageCount)").foregroundStyle(.secondary)
                    }
                    .onChange(of: m.fromPage) { v in if m.toPage < v { m.toPage = v } }
                    .onChange(of: m.toPage) { v in if m.fromPage > v { m.fromPage = v } }
                }
                if m.pageMode == .custom {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Páginas", text: $m.customPages, prompt: Text("p. ej. 1-3, 5, 8"))
                        Text("Escribe las páginas o haz clic en las miniaturas de la izquierda.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Stepper("Copias: \(m.copies)", value: $m.copies, in: 1...99)
                LabeledContent("Resultado") {
                    Text(m.summary)
                        .fontWeight(.semibold)
                        .foregroundStyle(m.selection.isEmpty ? Color.orange : Color.primary)
                }
            }

            if m.showFirstTime {
                Section("¿Es tu primera vez?") {
                    Button {
                        m.presentCalibration()
                    } label: {
                        Label("Calibrar la impresora…", systemImage: "wand.and.stars")
                    }
                    Button {
                        m.loadTestPage()
                    } label: {
                        Label("Cargar hoja de prueba", systemImage: "doc.text.magnifyingglass")
                    }
                    Text("Haz la calibración una vez: imprime 2 hojas de prueba y te dice qué ajustar.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { advancedOpen.toggle() }
                } label: {
                    HStack {
                        Label("Funciones avanzadas", systemImage: "slider.horizontal.3")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(advancedOpen ? 90 : 0))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if advancedOpen {
                    PrinterRows(includePrinter: false)
                    DuplexRows()
                    Toggle("Mostrar «¿Es tu primera vez?»", isOn: $m.showFirstTime)
                }
            }

            if case .failed(let msg) = m.phase {
                Section {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct PrinterPicker: View {
    @EnvironmentObject var m: Model

    var body: some View {
        HStack {
            Picker("Impresora", selection: $m.printer) {
                ForEach(m.printers, id: \.self) { Text(Model.displayName($0)).tag($0) }
            }
            Button { m.refreshPrinters() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).help("Actualizar lista")
        }
    }
}

struct PrinterRows: View {
    @EnvironmentObject var m: Model
    /// En la pantalla principal la impresora ya se elige arriba
    var includePrinter = true

    var body: some View {
        if includePrinter { PrinterPicker() }
        Picker("Papel", selection: $m.paper) {
            Text("A4").tag("A4")
            Text("Carta (Letter)").tag("Letter")
            Text("Legal").tag("Legal")
            Text("A5").tag("A5")
        }
        .onChange(of: m.paper) { _ in m.autoPaper = false }
        Toggle("Ajustar a la página", isOn: $m.fitToPage)
        Toggle("Imprimir en grises", isOn: $m.grayscale)
        Stepper(value: $m.margin, in: 0...50, step: 1) {
            Text("Margen: \(Int(m.margin)) mm")
        }
        Picker("Páginas por hoja", selection: $m.pagesPerSheet) {
            Text("1").tag(1)
            Text("2").tag(2)
            Text("4").tag(4)
            Text("6").tag(6)
            Text("8").tag(8)
        }
    }
}

struct DuplexRows: View {
    @EnvironmentObject var m: Model

    var body: some View {
        Toggle("Doble cara manual", isOn: $m.duplex)
        Toggle("Folleto (2 páginas por hoja)", isOn: $m.booklet)
            .disabled(!m.duplex)
        Group {
            Toggle("Cara B en orden inverso", isOn: $m.reverseB)
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Girar cara B 180°", isOn: $m.rotateB)
                if m.rotateB {
                    Text("Las hojas se vuelven a meter tal cual salen, sin darles la vuelta.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !m.rotateB {
                Picker("Volver a meter las hojas", selection: $m.faceDown) {
                    Text("Cara impresa abajo").tag(true)
                    Text("Cara impresa arriba").tag(false)
                }
            }
            Toggle("Dorso en blanco si las páginas son impares", isOn: $m.padBlank)
        }
        .disabled(!m.duplex || m.booklet)
    }
}

// MARK: Paneles de cada paso

struct PrintingPanel: View {
    @EnvironmentObject var m: Model

    var body: some View {
        let sideB = m.phase == .printingB
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text(!m.effectiveDuplex ? String(localized: "Imprimiendo…") : sideB ? String(localized: "Imprimiendo la cara B…") : String(localized: "Imprimiendo la cara A…"))
                .font(.title3.weight(.semibold))
            Text(sideB ? "Ya casi está. Deja que la impresora termine."
                 : m.effectiveDuplex ? "No toques las hojas hasta que la impresora pare.\nTe avisaré cuando haya que darles la vuelta."
                 : "Deja que la impresora termine.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

struct FlipPanel: View {
    @EnvironmentObject var m: Model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.uturn.down.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Cara A terminada")).font(.title2.bold())
                        Text(m.reinsertAsIs ? "Vuelve a meter las hojas tal cual salen" : "Ahora vuelve a meter las hojas").foregroundStyle(.secondary)
                    }
                }
                FlipIllustration(asIs: m.reinsertAsIs, faceDown: m.faceDown)
                FlipStepsList(steps: m.flipSteps)
            }
            .padding(20)
        }
    }
}

struct FlipStepsList: View {
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, text in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(i + 1)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.accentColor))
                    Text(text).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct DonePanel: View {
    @EnvironmentObject var m: Model

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(.green)
            Text(String(localized: "¡Listo!")).font(.title.bold())
            Text("«\(m.title)» ya está impreso\(m.effectiveDuplex ? " a doble cara" : "").\n\(m.summary)")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack {
                Button(String(localized: "Abrir otro PDF…")) { m.openPanel() }
                Button(String(localized: "Imprimir otra vez")) { m.reset() }
            }
            .padding(.top, 6)
            if !m.queue.isEmpty {
                Button { m.advanceQueue() } label: {
                    Label("Siguiente documento (\(m.queue.count) en cola)", systemImage: "tray.full")
                }
                .padding(.top, 4)
            }
        }
        .padding(24)
    }
}

// MARK: Barra inferior

struct ActionBar: View {
    @EnvironmentObject var m: Model

    var body: some View {
        HStack(spacing: 12) {
            if m.phase == .idle, m.doc != nil {
                Label(m.summary, systemImage: "doc.on.doc")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            switch m.phase {
            case .waitingFlip:
                Button(String(localized: "Cancelar"), role: .cancel) { m.cancel() }
                    .keyboardShortcut(.cancelAction)
                Button { m.printSideB() } label: {
                    Text(String(localized: "Imprimir cara B")).frame(minWidth: 120)
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            case .printingA, .printingB:
                Button(String(localized: "Cancelar"), role: .cancel) { m.cancel() }
                    .keyboardShortcut(.cancelAction)
            case .done:
                Button { m.reset() } label: {
                    Text(String(localized: "Hecho")).frame(minWidth: 110)
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            case .idle, .failed:
                if m.canReprintB {
                    Button { m.printSideB() } label: {
                        Label(String(localized: "Reimprimir cara B"), systemImage: "arrow.clockwise")
                    }
                }
                // Sin atajo de Intro: así pulsar Intro en un campo nunca manda a imprimir
                Button { m.start() } label: {
                    Text(m.effectiveDuplex ? String(localized: "Imprimir cara A") : String(localized: "Imprimir")).frame(minWidth: 110)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("p")
                .controlSize(.large)
                .disabled(!m.canPrint)
                .help("Imprimir (⌘P)")
            }
        }
        .padding(14)
    }
}

// MARK: - Ilustración: cómo volver a meter las hojas

struct FlipIllustration: View {
    /// true: el taco se mete tal cual sale (cara B girada 180°)
    let asIs: Bool
    let faceDown: Bool
    @State private var feeding = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            Group {
                if asIs { asIsScene } else { feedScene }
            }
            .frame(maxWidth: .infinity)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: false)) { feeding = true }
            }
            HStack(spacing: 16) {
                if asIs {
                    Label("Sin darles la vuelta", systemImage: "nosign")
                    Label("Sin girarlas", systemImage: "nosign")
                } else {
                    Label("Cara impresa hacia \(faceDown ? "abajo" : "arriba")",
                          systemImage: faceDown ? "arrow.down.to.line" : "arrow.up.to.line")
                    Label("Lo de arriba entra primero", systemImage: "arrow.right.to.line")
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(asIs
            ? "Mete las hojas en la bandeja de entrada tal cual salen, sin darles la vuelta ni girarlas"
            : "Mete las hojas con la cara impresa hacia \(faceDown ? "abajo" : "arriba") y la parte de arriba entrando primero")
    }

    /// Bandeja de salida → bandeja de entrada, el taco se mueve sin cambiar
    private var asIsScene: some View {
        HStack(spacing: 0) {
            TrayBox(title: "Bandeja de salida", icon: "tray.and.arrow.up")
            Image(systemName: "arrow.right").font(.title2.weight(.semibold)).foregroundStyle(Color.accentColor)
                .padding(.horizontal, 4)
            TrayBox(title: "Bandeja de entrada", icon: "tray.and.arrow.down")
        }
        .overlay {
            StackGlyph()
                .offset(x: feeding ? 92 : -92, y: -8)
                .opacity(feeding ? 0.2 : 1)
        }
        .frame(height: 110)
    }

    private var feedScene: some View {
        HStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.08))
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4]))
                PaperGlyph(faceDown: faceDown)
                    .rotationEffect(.degrees(90))   // la parte de arriba mira a la impresora
                    .offset(x: feeding ? 52 : -18)
                    .opacity(feeding ? 0 : 1)
            }
            .frame(width: 170, height: 110)
            .clipped()
            Image(systemName: "printer.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
        }
    }
}

struct TrayBox: View {
    let title: String
    let icon: String
    var body: some View {
        VStack(spacing: 6) {
            Spacer()
            Label(title, systemImage: icon)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(width: 140, height: 110)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4])))
    }
}

/// Un taco de hojas tal cual sale de la impresora
struct StackGlyph: View {
    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.black.opacity(0.15)))
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                    .frame(width: 46, height: 62)
                    .offset(x: CGFloat(i) * 3, y: CGFloat(-i) * 3)
            }
        }
    }
}

/// Una hoja vista desde arriba. Si la cara impresa va abajo, se ve el dorso en blanco.
struct PaperGlyph: View {
    let faceDown: Bool

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            VStack(spacing: 4) {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up")
                    Text("ARRIBA")
                }
                .font(.system(size: 7, weight: .heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .background(Color.accentColor)
                if faceDown {
                    Spacer()
                    Text("dorso\nen blanco")
                        .font(.system(size: 7))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.gray)
                    Spacer()
                } else {
                    Text("A").font(.system(size: 16, weight: .bold)).foregroundStyle(.black.opacity(0.7))
                    ForEach(0..<5, id: \.self) { _ in
                        Capsule().fill(Color.black.opacity(0.18)).frame(height: 2).padding(.horizontal, 7)
                    }
                    Spacer()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(width: 58, height: 80)
    }
}

// MARK: - Bienvenida

struct WelcomeSheet: View {
    @EnvironmentObject var m: Model
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    private let lastPage = 4

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0:
                    WelcomePage(icon: "hand.wave.fill", title: "¡Bienvenido a Doble Cara M2022!",
                                text: "Tu impresora no puede imprimir sola por las dos caras. Esta app te guía paso a paso para hacerlo a mano, sin equivocarte.")
                case 1:
                    WelcomePage(icon: "doc.badge.plus", title: "1. Abre un PDF",
                                text: "Puedes hacerlo de tres maneras:") {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Arrastra el PDF a la ventana de la app.", systemImage: "hand.draw")
                            Label("En Finder: clic derecho → Abrir con → Doble Cara M2022.", systemImage: "folder")
                            Label("Desde cualquier app: Archivo → Imprimir → menú «PDF» → «\(PDFMenu.name)».", systemImage: "printer")
                        }
                    }
                case 2:
                    WelcomePage(icon: "printer.fill", title: "2. Imprime la cara A",
                                text: "Elige qué páginas quieres y pulsa «Imprimir cara A». Se imprimen las páginas 1, 3, 5… En la vista «Hojas» ves en qué hoja y cara saldrá cada página.")
                case 3:
                    WelcomePage(icon: "arrow.uturn.down.circle.fill", title: "3. Vuelve a meter las hojas",
                                text: m.reinsertAsIs
                                    ? "Cuando termine, la app te avisa. Recoge el taco y vuelve a meterlo tal cual sale: sin darle la vuelta ni girarlo."
                                    : "Cuando termine, la app te avisa. Recoge el taco sin desordenarlo y vuelve a meterlo así:") {
                        FlipIllustration(asIs: m.reinsertAsIs, faceDown: m.faceDown)
                    }
                default:
                    WelcomePage(icon: "wand.and.stars", title: "4. Imprime la cara B… y listo",
                                text: "Pulsa «Imprimir cara B» y se imprimen las páginas 2, 4, 6… por detrás.\n\nAntes de empezar te recomendamos calibrar la impresora: imprime 2 hojas de prueba y la app ajusta lo necesario.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 36)
            .padding(.top, 28)

            HStack(spacing: 6) {
                ForEach(0...lastPage, id: \.self) { i in
                    Circle()
                        .fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.bottom, 14)

            Divider()
            HStack {
                if page == 0 {
                    Button("Saltar") { dismiss() }
                } else {
                    Button("Atrás") { page -= 1 }
                }
                Spacer()
                if page < lastPage {
                    Button("Siguiente") { page += 1 }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Más tarde") { dismiss() }
                    Button("Calibrar ahora") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { m.presentCalibration() }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(width: 540, height: 440)
        .onDisappear { m.welcomeShown = true }
    }
}

struct WelcomePage<Extra: View>: View {
    let icon: String
    let title: String
    let text: String
    @ViewBuilder var extra: () -> Extra

    init(icon: String, title: String, text: String, @ViewBuilder extra: @escaping () -> Extra) {
        self.icon = icon
        self.title = title
        self.text = text
        self.extra = extra
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            Text(title).font(.title2.bold()).multilineTextAlignment(.center)
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            extra()
            Spacer(minLength: 0)
        }
    }
}

extension WelcomePage where Extra == EmptyView {
    init(icon: String, title: String, text: String) {
        self.init(icon: icon, title: title, text: text) { EmptyView() }
    }
}

// MARK: - Calibración

struct CalibrationSheet: View {
    @EnvironmentObject var m: Model
    @Environment(\.dismiss) private var dismiss

    enum Step { case intro, printing, behind, direction, result }
    @State private var step: Step = .intro
    @State private var changes: [String] = []
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars").font(.title2).foregroundStyle(Color.accentColor)
                Text("Calibrar la impresora").font(.title3.bold())
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 12)
            Divider()
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
            }
            Divider()
            buttons.padding(16)
        }
        .frame(width: 540, height: 500)
        .onChange(of: m.phase) { p in
            if step == .printing && p == .done { step = .behind }
        }
        .onDisappear { m.endCalibration() }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .intro:
            VStack(alignment: .leading, spacing: 14) {
                Text("Vamos a imprimir 2 hojas de prueba (páginas 1 a 4) para comprobar que la cara B sale bien: en el orden correcto y en el mismo sentido que la cara A.")
                    .fixedSize(horizontal: false, vertical: true)
                Label("Pon al menos 2 hojas de papel en la bandeja.", systemImage: "doc.on.doc")
                Form { PrinterRows() }
                    .formStyle(.grouped)
                    .frame(height: 150)
                    .scrollDisabled(true)
            }
        case .printing:
            switch m.phase {
            case .waitingFlip:
                VStack(alignment: .leading, spacing: 14) {
                    Text("Cara A de prueba terminada").font(.headline)
                    FlipIllustration(asIs: m.reinsertAsIs, faceDown: m.faceDown)
                    FlipStepsList(steps: m.flipSteps)
                }
            case .failed(let msg):
                Label(msg, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            default:
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text(m.phase == .printingB ? "Imprimiendo la cara B de prueba…" : "Imprimiendo la cara A de prueba…")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            }
        case .behind:
            VStack(alignment: .leading, spacing: 10) {
                Text("Coge la hoja que tiene la PÁGINA 1. ¿Qué hay por detrás?").font(.headline)
                ChoiceButton(icon: "checkmark.circle", text: "La página 2") { step = .direction }
                ChoiceButton(icon: "arrow.up.arrow.down", text: "La página 4") {
                    m.reverseB.toggle()
                    changes.append("Orden de la cara B: \(m.reverseB ? "inverso" : "normal").")
                    step = .direction
                }
                ChoiceButton(icon: "square.on.square", text: "Nada: la cara B se imprimió encima de la cara A") {
                    if m.reinsertAsIs {
                        problem = "La cara B se imprimió por el mismo lado. Repite la prueba metiendo el taco exactamente como sale de la impresora, sin darle la vuelta ni girarlo."
                    } else {
                        m.faceDown.toggle()
                        changes.append("Las hojas se meten con la cara impresa hacia \(m.faceDown ? "abajo" : "arriba").")
                    }
                    step = .result
                }
                ChoiceButton(icon: "xmark.circle", text: "La cara B no se imprimió") {
                    problem = "La cara B no llegó a imprimirse. Comprueba que la impresora tiene papel y está encendida, y repite la prueba."
                    step = .result
                }
            }
        case .direction:
            VStack(alignment: .leading, spacing: 10) {
                Text("Gira la hoja como la página de un libro. ¿El número de detrás se lee bien, con «ARRIBA» en el mismo lado?")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                ChoiceButton(icon: "checkmark.circle", text: "Sí, se lee bien") { step = .result }
                ChoiceButton(icon: "arrow.uturn.down", text: "No, sale cabeza abajo") {
                    m.rotateB.toggle()
                    changes.append("Giro de la cara B: \(m.rotateB ? "180°" : "sin girar").")
                    step = .result
                }
            }
        case .result:
            VStack(alignment: .leading, spacing: 12) {
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                } else if changes.isEmpty {
                    Label("¡Todo correcto! Tu impresora ya está lista para imprimir a doble cara.",
                          systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                } else {
                    Text("He cambiado estos ajustes:").font(.headline)
                    ForEach(changes, id: \.self) { Label($0, systemImage: "slider.horizontal.3") }
                    Text("Te recomendamos repetir la prueba para confirmarlo.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        HStack {
            Button("Cancelar", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            switch step {
            case .intro:
                Button("Imprimir prueba") {
                    m.beginCalibration()
                    m.start()
                    step = .printing
                }
                .keyboardShortcut(.defaultAction)
                .disabled(m.printer.isEmpty)
            case .printing:
                if m.phase == .waitingFlip {
                    Button("Imprimir cara B") { m.printSideB() }
                        .keyboardShortcut(.defaultAction)
                } else if case .failed = m.phase {
                    Button("Reintentar") { m.reset(); step = .intro }
                        .keyboardShortcut(.defaultAction)
                }
            case .behind, .direction:
                EmptyView()
            case .result:
                if problem != nil || !changes.isEmpty {
                    Button("Repetir prueba") {
                        changes = []
                        problem = nil
                        m.reset()
                        step = .intro
                    }
                }
                Button("Terminar") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

struct ChoiceButton: View {
    let icon: String
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 20).foregroundStyle(Color.accentColor)
                Text(text).multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preferencias (⌘,)

struct PreferencesView: View {
    @EnvironmentObject var m: Model
    @State private var showingSaveAlert = false
    @State private var newProfileName = ""
    @AppStorage("largeUI") private var largeUI = false

    var body: some View {
        Form {
            Section("Impresora") { PrinterRows() }
            Section("Doble cara") { DuplexRows() }
            Section("Avisos e integración") {
                Toggle("Avisarme con una notificación", isOn: $m.notify)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Mostrar en el menú «PDF» al imprimir", isOn: $m.pdfMenu)
                    Text("En cualquier app: Archivo → Imprimir → menú «PDF» (abajo a la izquierda) → «\(PDFMenu.name)». El documento se abre aquí, listo para imprimir.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section("Perfiles") {
                if m.profiles.isEmpty {
                    Text("No hay perfiles guardados.").foregroundStyle(.secondary)
                } else {
                    ForEach(m.profiles) { p in
                        HStack {
                            Text(p.name).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Usar") { m.apply(p) }
                            Button { m.removeProfile(p) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                Button("Guardar ajustes actuales…") { showingSaveAlert = true }
            }
            Section("Ayuda") {
                Toggle("Mostrar «¿Es tu primera vez?»", isOn: $m.showFirstTime)
                Toggle("Letra grande", isOn: $largeUI)
                HStack {
                    Button("Calibrar la impresora…") { m.presentCalibration() }
                        .disabled(m.busy)
                    Button("Ver la bienvenida") { m.presentWelcome() }
                }
            }
            Section("Estadísticas") {
                LabeledContent("Trabajos impresos", value: "\(m.jobsCount)")
                LabeledContent("Hojas ahorradas a doble cara", value: "\(m.sheetsSaved)")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .frame(minHeight: 560)
        .alert("Nombre del perfil", isPresented: $showingSaveAlert) {
            TextField("Nombre", text: $newProfileName)
            Button("Guardar") {
                m.saveProfile(newProfileName)
                newProfileName = ""
            }
            Button("Cancelar", role: .cancel) { newProfileName = "" }
        }
    }
}
