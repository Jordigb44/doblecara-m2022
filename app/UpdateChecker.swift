// Actualizador: comprueba la última release pública en GitHub y la instala.
// Lógica pura (comparación de versiones y decodificación) separada de la UI
// para poder testearla.

import CryptoKit
import Foundation

/// Una release de GitHub con sus archivos adjuntos
struct GitHubRelease: Decodable, Equatable, Identifiable {
    struct Asset: Decodable, Equatable {
        let name: String
        let browser_download_url: URL
    }
    let tag_name: String
    let name: String
    let body: String?
    let html_url: URL
    let assets: [Asset]

    var id: String { tag_name }
    /// Versión sin la «v» inicial del tag (p. ej. «1.3.0»)
    var version: String { String(tag_name.drop { $0 == "v" }) }
    var zipAsset: Asset? { assets.first { $0.name.hasSuffix(".zip") } }
}

enum UpdateChecker {
    static let repo = "Jordigb44/doblecara-m2022"
    static var latestURL: URL {
        URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    }

    /// Versión actual de la app (del Info.plist del bundle)
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// Compara versiones tipo «1.2.3» (faltan campos = 0). true si `a` es más nueva que `b`.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").compactMap { Int($0) }
        let pb = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Última release publicada, o nil si no hay ninguna más nueva que la actual
    static func fetchLatest() async throws -> GitHubRelease? {
        var req = URLRequest(url: latestURL)
        req.setValue("doblecara-m2022", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        return isNewer(release.version, than: currentVersion) ? release : nil
    }
}

// MARK: - Instalación

enum UpdateInstallError: LocalizedError {
    case noZipAsset
    case checksumMismatch(expected: String, got: String)
    case extractFailed(String)
    case noAppInArchive
    case notWritable(String)

    var errorDescription: String? {
        switch self {
        case .noZipAsset:
            return "La release no incluye un archivo .zip."
        case let .checksumMismatch(expected, got):
            return "El archivo descargado no coincide con el checksum publicado (esperado \(expected), obtenido \(got))."
        case let .extractFailed(out):
            return "No se pudo descomprimir la actualización: \(out)"
        case .noAppInArchive:
            return "El archivo descargado no contiene la app."
        case let .notWritable(p):
            return "No hay permisos de escritura en \(p). Mueve la app a Aplicaciones o actualízala a mano."
        }
    }
}

enum UpdateInstaller {
    /// Descarga el .zip de la release, verifica su SHA256 si la release lo publica,
    /// descomprime la app y deja un script de instalación. Devuelve la ruta del script.
    static func stage(_ release: GitHubRelease) async throws -> String {
        guard let zip = release.zipAsset else { throw UpdateInstallError.noZipAsset }
        let fm = FileManager.default
        let work = fm.temporaryDirectory
            .appendingPathComponent("doblecara-update-\(release.version)", isDirectory: true)
        try? fm.removeItem(at: work)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)

        // Descargar el .zip
        let zipURL = work.appendingPathComponent(zip.name)
        let (tmp, resp) = try await URLSession.shared.download(from: zip.browser_download_url)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        try fm.moveItem(at: tmp, to: zipURL)

        // Verificar SHA256 si la release publica SHA256SUMS.txt
        if let sums = release.assets.first(where: { $0.name == "SHA256SUMS.txt" }),
           let expected = try? await expectedChecksum(for: zip.name, sums: sums) {
            let got = sha256(of: zipURL)
            guard got == expected else {
                throw UpdateInstallError.checksumMismatch(expected: expected, got: got)
            }
        }

        // Descomprimir
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zipURL.path, work.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard p.terminationStatus == 0 else { throw UpdateInstallError.extractFailed(out) }
        guard let newApp = try? fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" })
        else { throw UpdateInstallError.noAppInArchive }

        // Destino: la app en ejecución si vive dentro de un .app, si no ~/Applications
        let bundle = Bundle.main.bundleURL
        let dest = bundle.pathExtension == "app"
            ? bundle
            : fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Doble Cara M2022.app")
        guard fm.isWritableFile(atPath: dest.deletingLastPathComponent().path) else {
            throw UpdateInstallError.notWritable(dest.deletingLastPathComponent().path)
        }

        // Script que espera a que esta app salga, sustituye el bundle y relanza
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/sh
        while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.3; done
        /bin/sleep 0.5
        DEST=\(q(dest.path))
        NEW=\(q(newApp.path))
        rm -rf "$DEST.old"
        if [ -e "$DEST" ]; then
          mv "$DEST" "$DEST.old" || exit 1
        fi
        mv "$NEW" "$DEST" || { mv "$DEST.old" "$DEST" 2>/dev/null; exit 1; }
        rm -rf "$DEST.old"
        /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
        /usr/bin/open "$DEST"
        exit 0
        """
        let scriptURL = work.appendingPathComponent("instalar-actualizacion.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL.path
    }

    /// Lanza el script de instalación desprendido (no espera; la app se cierra sola).
    static func launch(_ scriptPath: String) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [scriptPath]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
    }

    /// SHA256 en hex de un archivo, en streaming.
    static func sha256(of url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Busca el hash publicado para `name` dentro de un SHA256SUMS.txt.
    private static func expectedChecksum(for name: String, sums: GitHubRelease.Asset) async throws -> String? {
        var req = URLRequest(url: sums.browser_download_url)
        req.setValue("doblecara-m2022", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            let file = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "* "))
            if file.hasSuffix(name) { return String(parts[0]).lowercased() }
        }
        return nil
    }

    /// Escapa una ruta para usarla entre comillas simples en sh.
    private static func q(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
