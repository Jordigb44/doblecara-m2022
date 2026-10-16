// Genera el icono de la app (dos hojas «A» y «B») como .iconset
// Uso: xcrun --sdk macosx swift make_icon.swift <carpeta.iconset>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
    ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
    ("512x512", 512), ("512x512@2x", 1024),
]

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // Fondo: cuadrado redondeado con degradado azul
    let inset = s * 0.09
    let bg = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: bg, cornerWidth: bg.width * 0.225, cornerHeight: bg.width * 0.225, transform: nil))
    ctx.clip()
    let colors = [NSColor(calibratedRed: 0.20, green: 0.52, blue: 0.98, alpha: 1).cgColor,
                  NSColor(calibratedRed: 0.06, green: 0.27, blue: 0.70, alpha: 1).cgColor] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

    func sheet(_ r: CGRect, fill: NSColor, ink: NSColor, label: String) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.035,
                      color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.setFillColor(fill.cgColor)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: s * 0.025, cornerHeight: s * 0.025, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: r.height * 0.45, weight: .heavy),
            .foregroundColor: ink,
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        let sz = str.size()
        str.draw(at: CGPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2))
    }

    let blue = NSColor(calibratedRed: 0.10, green: 0.36, blue: 0.86, alpha: 1)
    sheet(CGRect(x: s * 0.42, y: s * 0.30, width: s * 0.33, height: s * 0.44),
          fill: NSColor(white: 0.86, alpha: 1), ink: blue.withAlphaComponent(0.55), label: "B")
    sheet(CGRect(x: s * 0.25, y: s * 0.23, width: s * 0.33, height: s * 0.44),
          fill: .white, ink: blue, label: "A")
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in sizes {
    try! render(px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
print("Icono generado en \(out)")
