import XCTest
@testable import PagePlan

final class UpdateCheckerTests: XCTestCase {

    // MARK: isNewer

    func testVersionMasNueva() {
        XCTAssertTrue(UpdateChecker.isNewer("1.3.0", than: "1.2.1"))
        XCTAssertTrue(UpdateChecker.isNewer("2.0.0", than: "1.9.9"))
        XCTAssertTrue(UpdateChecker.isNewer("1.10.0", than: "1.9.9"))
    }

    func testVersionIgualONoMasNueva() {
        XCTAssertFalse(UpdateChecker.isNewer("1.2.1", than: "1.2.1"))
        XCTAssertFalse(UpdateChecker.isNewer("1.2.0", than: "1.2.1"))
        XCTAssertFalse(UpdateChecker.isNewer("1.2", than: "1.2.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.2.0", than: "1.2"))
    }

    func testCamposFaltantesSonCero() {
        XCTAssertTrue(UpdateChecker.isNewer("1.2.1.1", than: "1.2.1"))
        XCTAssertTrue(UpdateChecker.isNewer("1.3", than: "1.2.9"))
        XCTAssertFalse(UpdateChecker.isNewer("1.2.0.0", than: "1.2"))
    }

    func testVersionesMalformadasNoSonMasNuevas() {
        XCTAssertFalse(UpdateChecker.isNewer("abc", than: "1.0.0"))
        XCTAssertFalse(UpdateChecker.isNewer("", than: "1.0.0"))
    }

    // MARK: version del tag

    func testVersionQuitaLaVInicial() {
        let r = GitHubRelease(tag_name: "v1.3.0", name: "1.3.0", body: nil,
                              html_url: URL(string: "https://example.com")!, assets: [])
        XCTAssertEqual(r.version, "1.3.0")
        XCTAssertEqual(r.id, "v1.3.0")
    }

    func testZipAssetEligeElZip() {
        let zip = GitHubRelease.Asset(name: "app-1.3.0-macOS.zip",
                                      browser_download_url: URL(string: "https://example.com/z.zip")!)
        let dmg = GitHubRelease.Asset(name: "app-1.3.0-macOS.dmg",
                                      browser_download_url: URL(string: "https://example.com/d.dmg")!)
        let sums = GitHubRelease.Asset(name: "SHA256SUMS.txt",
                                       browser_download_url: URL(string: "https://example.com/s.txt")!)
        let r = GitHubRelease(tag_name: "v1.3.0", name: "1.3.0", body: nil,
                              html_url: URL(string: "https://example.com")!,
                              assets: [dmg, zip, sums])
        XCTAssertEqual(r.zipAsset, zip)
    }

    func testDecodificacionDesdeJSON() throws {
        let json = """
        {"tag_name":"v1.3.0","name":"1.3.0","body":"- fix",
         "html_url":"https://github.com/x/y/releases/tag/v1.3.0",
         "assets":[{"name":"app-1.3.0-macOS.zip",
                    "browser_download_url":"https://github.com/x/y/releases/download/v1.3.0/app.zip"}]}
        """
        let r = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
        XCTAssertEqual(r.version, "1.3.0")
        XCTAssertEqual(r.assets.count, 1)
        XCTAssertEqual(r.zipAsset?.name, "app-1.3.0-macOS.zip")
    }

    // MARK: SHA256

    func testSha256DeArchivoConocido() throws {
        let f = FileManager.default.temporaryDirectory
            .appendingPathComponent("sha-test-\(UUID().uuidString).txt")
        try "hola".write(to: f, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: f) }
        // sha256("hola")
        XCTAssertEqual(UpdateInstaller.sha256(of: f),
                       "b221d9dbb083a7f33428d7c2a3c3198ae925614d70210e28716ccaa7cd4ddb79")
    }
}
