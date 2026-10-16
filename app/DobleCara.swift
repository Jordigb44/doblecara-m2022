// Doble Cara M2022 — app de macOS para imprimir a doble cara manual
// (pensada para la Samsung Xpress M2022, sirve para cualquier impresora sin dúplex)
//
// Compilar:  ./build.sh   (necesita las Command Line Tools de Xcode)

import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

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
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        if let u = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) ?? urls.first {
            Task { @MainActor in Model.shared.load(u) }
        }
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
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
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
                   fit: Bool, copies: Int = 1) -> (id: String?, error: String?) {
        var args = ["-d", printer, "-t", title, "-o", "media=\(paper)"]
        if fit { args += ["-o", "fit-to-page"] }
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

    static func cancel(_ id: String) { run("/usr/bin/cancel", [id]) }
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

    // Ajustes (se recuerdan)
    @Published var printer: String { didSet { defaults.set(printer, forKey: "printer") } }
    @Published var paper: String { didSet { defaults.set(paper, forKey: "paper") } }
    @Published var duplex: Bool { didSet { defaults.set(duplex, forKey: "duplex") } }
    @Published var reverseB: Bool { didSet { defaults.set(reverseB, forKey: "reverseB") } }
    @Published var rotateB: Bool { didSet { defaults.set(rotateB, forKey: "rotateB") } }
    @Published var padBlank: Bool { didSet { defaults.set(padBlank, forKey: "padBlank") } }
    @Published var fitToPage: Bool { didSet { defaults.set(fitToPage, forKey: "fitToPage") } }

    // Ajustes por trabajo
    @Published var copies = 1
    @Published var allPages = true
    @Published var fromPage = 1
    @Published var toPage = 1

    private var currentJob: String?
    private var evenFile: URL?
    private var sheetsInfo = ""

    private init() {
        defaults.register(defaults: ["paper": "A4", "duplex": true, "reverseB": true,
                                     "rotateB": true, "padBlank": true, "fitToPage": false])
        printer = defaults.string(forKey: "printer") ?? ""
        paper = defaults.string(forKey: "paper") ?? "A4"
        duplex = defaults.bool(forKey: "duplex")
        reverseB = defaults.bool(forKey: "reverseB")
        rotateB = defaults.bool(forKey: "rotateB")
        padBlank = defaults.bool(forKey: "padBlank")
        fitToPage = defaults.bool(forKey: "fitToPage")
        refreshPrinters()
    }

    var pageCount: Int { doc?.pageCount ?? 0 }
    var busy: Bool { phase == .printingA || phase == .printingB || phase == .waitingFlip }
    var title: String { url?.deletingPathExtension().lastPathComponent ?? "Documento" }

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
        guard !busy else { NSSound.beep(); return }
        guard let d = PDFDocument(url: u) else {
            phase = .failed("No se pudo abrir «\(u.lastPathComponent)» como PDF.")
            return
        }
        url = u
        doc = d
        allPages = true
        fromPage = 1
        toPage = d.pageCount
        copies = 1
        phase = .idle
        NSApp.activate(ignoringOtherApps: true)
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let u = panel.url { load(u) }
    }

    /// Páginas elegidas (índices desde 0)
    var selection: [Int] {
        guard pageCount > 0 else { return [] }
        if allPages { return Array(0..<pageCount) }
        let a = max(1, min(fromPage, pageCount)), b = max(a, min(toPage, pageCount))
        return Array((a - 1)...(b - 1))
    }

    /// Secuencia completa (con copias); nil = página en blanco
    private func sequence() -> [Int?] {
        let sel = selection
        var seq: [Int?] = []
        for c in 0..<max(1, copies) {
            seq += sel.map { Optional($0) }
            // Cada copia empieza en hoja nueva
            if sel.count % 2 == 1 && (c < copies - 1 || padBlank) { seq.append(nil) }
        }
        return seq
    }

    var sheetCount: Int { (sequence().count + 1) / 2 }

    private func makePDF(_ indices: [Int?], rotate: Bool, name: String) -> URL? {
        guard let doc else { return nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("DobleCaraM2022", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: file)

        // Tamaño de una página tal y como se ve (con su giro aplicado)
        func size(of page: PDFPage?) -> CGSize {
            guard let page else { return CGSize(width: 595, height: 842) }
            let b = page.bounds(for: .mediaBox)
            return page.rotation % 180 == 0 ? b.size : CGSize(width: b.height, height: b.width)
        }
        let refSize = size(of: doc.page(at: selection.last ?? 0))
        var box = CGRect(origin: .zero, size: refSize)
        guard let ctx = CGContext(file as CFURL, mediaBox: &box, nil) else { return nil }

        // Se redibuja cada página en un PDF nuevo. El giro de 180° se dibuja dentro
        // de la página (el sistema de impresión ignora la marca /Rotate de 180°).
        for i in indices {
            let page = i.flatMap { doc.page(at: $0) }
            var media = CGRect(origin: .zero, size: page == nil ? refSize : size(of: page))
            let info = [kCGPDFContextMediaBox as String: Data(bytes: &media, count: MemoryLayout<CGRect>.size)] as CFDictionary
            ctx.beginPDFPage(info)
            if let page {
                ctx.saveGState()
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

    // MARK: Impresión

    func start() {
        guard doc != nil, !printer.isEmpty, !busy else { return }
        let seq = sequence()
        if !duplex || seq.count <= 1 {
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
        guard phase == .waitingFlip, let evenFile else { return }
        send(evenFile, suffix: "cara B", printing: .printingB, next: .done)
    }

    private func printSingle() {
        guard let file = makePDF(selection.map { Optional($0) }, rotate: false, name: "\(title).pdf") else {
            phase = .failed("No se pudieron preparar las páginas.")
            return
        }
        let p = printer, paper = paper, fit = fitToPage, n = copies, t = title
        phase = .printingA
        Task {
            let r = await Task.detached { Shell.lp(file: file, printer: p, title: t, paper: paper, fit: fit, copies: n) }.value
            if let e = r.error { phase = .failed(e); return }
            currentJob = r.id
            await waitForJob()
            phase = .done
        }
    }

    private func send(_ file: URL, suffix: String, printing: Phase, next: Phase) {
        let p = printer, paper = paper, fit = fitToPage, t = "\(title) - \(suffix)"
        phase = printing
        Task {
            let r = await Task.detached { Shell.lp(file: file, printer: p, title: t, paper: paper, fit: fit) }.value
            if let e = r.error { phase = .failed(e); return }
            currentJob = r.id
            await waitForJob()
            guard phase == printing else { return }  // cancelado
            phase = next
            if next == .waitingFlip {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.requestUserAttention(.criticalRequest)
                NSSound(named: "Glass")?.play()
            }
        }
    }

    private func waitForJob() async {
        guard let id = currentJob else {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            return
        }
        let p = printer
        let start = Date()
        while Date().timeIntervalSince(start) < 900 {
            let pending = await Task.detached { Shell.jobPending(id, printer: p) }.value
            if !pending { break }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
        currentJob = nil
    }

    func cancel() {
        if let id = currentJob {
            Task.detached { Shell.cancel(id) }
        }
        currentJob = nil
        phase = .idle
    }

    var flipInstructions: String {
        var s = "1. Recoge las \(sheetCount) hoja(s) de la bandeja de salida SIN cambiar su orden.\n" +
                "2. Mételas en la bandeja de entrada con la cara impresa hacia ABAJO y la parte de arriba del texto entrando primero en la impresora."
        if !sheetsInfo.isEmpty { s += "\n3. " + sheetsInfo }
        return s
    }

    // MARK: Hoja de prueba

    func loadTestPage() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("DobleCaraM2022", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("Hoja de prueba doble cara.pdf")
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let ctx = CGContext(file as CFURL, mediaBox: &box, nil) else { return }
        let big: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 44)]
        let mid: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 30)]
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16)]
        let pages = [("CARA A · PÁGINA 1", "Esta es la primera cara."),
                     ("CARA B · PÁGINA 2", "Al girar la hoja como un libro, esta cara debe leerse\nen el mismo sentido que la cara A.")]
        for (t, sub) in pages {
            ctx.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            ("↑  ARRIBA  ↑" as NSString).draw(at: CGPoint(x: 150, y: 760), withAttributes: mid)
            (t as NSString).draw(at: CGPoint(x: 60, y: 620), withAttributes: big)
            (sub as NSString).draw(in: CGRect(x: 60, y: 480, width: 480, height: 100), withAttributes: small)
            ("Si la cara B sale cabeza abajo, activa «Girar cara B 180°».\nSi en documentos largos el orden sale al revés, desactiva «Cara B en orden inverso»." as NSString)
                .draw(in: CGRect(x: 60, y: 80, width: 480, height: 80), withAttributes: small)
            NSGraphicsContext.restoreGraphicsState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
        load(file)
    }
}

// MARK: - Vistas

struct PDFPreview: NSViewRepresentable {
    let doc: PDFDocument?
    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displaysPageBreaks = true
        v.backgroundColor = .underPageBackgroundColor
        return v
    }
    func updateNSView(_ v: PDFView, context: Context) {
        if v.document !== doc { v.document = doc }
    }
}

struct ContentView: View {
    @EnvironmentObject var m: Model
    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            preview
                .frame(minWidth: 360)
            Divider()
            VStack(spacing: 0) {
                settings
                Divider()
                actionBar
            }
            .frame(width: 400)
        }
        .onOpenURL { m.load($0) }
        .sheet(isPresented: Binding(get: { m.phase == .waitingFlip }, set: { _ in })) {
            FlipSheet().environmentObject(m)
        }
    }

    private var preview: some View {
        ZStack {
            if m.doc != nil {
                PDFPreview(doc: m.doc)
            } else {
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
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(10)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let u = urls.first else { return false }
            m.load(u)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    private var settings: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "doc.richtext").foregroundStyle(.secondary)
                    Text(m.doc == nil ? "Ningún documento" : m.title)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if m.doc != nil {
                        Text("\(m.pageCount) pág.").foregroundStyle(.secondary)
                    }
                    Button { m.openPanel() } label: { Image(systemName: "folder") }
                        .buttonStyle(.borderless).help("Abrir otro PDF")
                }
            }

            Section("Impresora") {
                HStack {
                    Picker("Impresora", selection: $m.printer) {
                        ForEach(m.printers, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
                    }
                    Button { m.refreshPrinters() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless).help("Actualizar lista")
                }
                Picker("Papel", selection: $m.paper) {
                    Text("A4").tag("A4")
                    Text("Carta (Letter)").tag("Letter")
                }
                Toggle("Ajustar a la página", isOn: $m.fitToPage)
            }

            Section("Trabajo") {
                Stepper("Copias: \(m.copies)", value: $m.copies, in: 1...99)
                Picker("Páginas", selection: $m.allPages) {
                    Text("Todas").tag(true)
                    Text("Intervalo").tag(false)
                }
                .pickerStyle(.segmented)
                if !m.allPages {
                    HStack {
                        Stepper("Desde \(m.fromPage)", value: $m.fromPage, in: 1...max(1, m.pageCount))
                        Stepper("hasta \(m.toPage)", value: $m.toPage, in: 1...max(1, m.pageCount))
                    }
                }
                Toggle("Doble cara manual", isOn: $m.duplex)
            }

            if m.duplex {
                Section("Cara B") {
                    Toggle("Cara B en orden inverso", isOn: $m.reverseB)
                    Toggle("Girar cara B 180°", isOn: $m.rotateB)
                    Toggle("Dorso en blanco si las páginas son impares", isOn: $m.padBlank)
                    Button("Cargar hoja de prueba") { m.loadTestPage() }
                        .disabled(m.busy)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(m.busy)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            status
            Spacer()
            if m.busy {
                Button("Cancelar", role: .cancel) { m.cancel() }
            }
            Button {
                m.start()
            } label: {
                Text(m.duplex ? "Imprimir cara A" : "Imprimir")
                    .frame(minWidth: 110)
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .disabled(m.doc == nil || m.printer.isEmpty || m.busy)
        }
        .padding(14)
    }

    @ViewBuilder private var status: some View {
        switch m.phase {
        case .idle:
            if m.doc != nil && m.duplex {
                Label("\(m.sheetCount) hoja(s)", systemImage: "doc.on.doc").foregroundStyle(.secondary)
            }
        case .printingA:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(m.duplex ? "Imprimiendo cara A…" : "Imprimiendo…") }
        case .waitingFlip:
            Label("Da la vuelta a las hojas", systemImage: "arrow.uturn.down")
        case .printingB:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Imprimiendo cara B…") }
        case .done:
            Label("Listo", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red).lineLimit(2).help(msg)
        }
    }
}

struct FlipSheet: View {
    @EnvironmentObject var m: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "arrow.triangle.2.circlepath.doc.on.clipboard")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cara A terminada").font(.title2.bold())
                    Text("Ahora da la vuelta a las hojas").foregroundStyle(.secondary)
                }
            }
            Text(m.flipInstructions)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)
            HStack {
                Button("Cancelar", role: .cancel) { m.cancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    m.printSideB()
                } label: {
                    Text("Imprimir cara B").frame(minWidth: 140)
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
