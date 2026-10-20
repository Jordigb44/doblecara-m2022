import XCTest
@testable import PagePlan

final class PagePlanTests: XCTestCase {

    // MARK: parse

    func testParseRangosYSueltas() {
        XCTAssertEqual(PagePlan.parse("1-3, 5, 8", pageCount: 8), [0, 1, 2, 4, 7])
    }

    func testParseRangoAbiertoHastaElFinal() {
        XCTAssertEqual(PagePlan.parse("8-", pageCount: 8), [7])
        XCTAssertEqual(PagePlan.parse("6-", pageCount: 8), [5, 6, 7])
    }

    func testParseRangoInvertido() {
        XCTAssertEqual(PagePlan.parse("3-1", pageCount: 5), [0, 1, 2])
    }

    func testParseFueraDeRangoSeIgnora() {
        XCTAssertEqual(PagePlan.parse("9", pageCount: 5), [])
        XCTAssertEqual(PagePlan.parse("1-99", pageCount: 5), [0, 1, 2, 3, 4])
    }

    func testParseVacio() {
        XCTAssertEqual(PagePlan.parse("", pageCount: 5), [])
        XCTAssertEqual(PagePlan.parse("  ", pageCount: 5), [])
    }

    func testParseSeparadorPuntoYComa() {
        XCTAssertEqual(PagePlan.parse("1; 3", pageCount: 5), [0, 2])
    }

    func testParseRangoIgual() {
        XCTAssertEqual(PagePlan.parse("5-5", pageCount: 5), [4])
    }

    // MARK: format

    func testFormatRangoYSueltas() {
        XCTAssertEqual(PagePlan.format([0, 1, 2, 4]), "1-3, 5")
    }

    func testFormatOrdenaIgualQueOrdenDeEntrada() {
        XCTAssertEqual(PagePlan.format([2, 0, 1]), "1-3")
    }

    func testFormatUnicoYVacio() {
        XCTAssertEqual(PagePlan.format([0]), "1")
        XCTAssertEqual(PagePlan.format([]), "")
    }

    func testFormatParseIdaYVuelta() {
        let original = "1-3, 5, 8"
        let indices = PagePlan.parse(original, pageCount: 8)
        XCTAssertEqual(PagePlan.format(indices), "1-3, 5, 8")
    }

    // MARK: selection

    func testSelectionAll() {
        XCTAssertEqual(PagePlan.selection(mode: .all, pageCount: 5, from: 1, to: 1, custom: ""), [0, 1, 2, 3, 4])
    }

    func testSelectionRange() {
        XCTAssertEqual(PagePlan.selection(mode: .range, pageCount: 5, from: 2, to: 4, custom: ""), [1, 2, 3])
    }

    func testSelectionRangeInvertido() {
        // El modo «desde–hasta» no reordena: si desde > hasta, queda una sola página
        // (la UI ya impide este caso con onChange en SettingsForm).
        XCTAssertEqual(PagePlan.selection(mode: .range, pageCount: 5, from: 4, to: 2, custom: ""), [3])
    }

    func testSelectionCustom() {
        XCTAssertEqual(PagePlan.selection(mode: .custom, pageCount: 5, from: 1, to: 1, custom: "1-2"), [0, 1])
    }

    func testSelectionSinPaginas() {
        XCTAssertEqual(PagePlan.selection(mode: .all, pageCount: 0, from: 1, to: 1, custom: ""), [])
    }

    // MARK: sheetPlan

    func testSheetPlanDuplex() {
        let plan = PagePlan.sheetPlan(selection: [0, 1, 2, 3], duplex: true)
        XCTAssertEqual(plan[0]?.sheet, 1); XCTAssertEqual(plan[0]?.sideB, false)
        XCTAssertEqual(plan[1]?.sheet, 1); XCTAssertEqual(plan[1]?.sideB, true)
        XCTAssertEqual(plan[2]?.sheet, 2); XCTAssertEqual(plan[2]?.sideB, false)
        XCTAssertEqual(plan[3]?.sheet, 2); XCTAssertEqual(plan[3]?.sideB, true)
    }

    func testSheetPlanDuplexImpar() {
        let plan = PagePlan.sheetPlan(selection: [0, 1, 2], duplex: true)
        XCTAssertEqual(plan[2]?.sheet, 2); XCTAssertEqual(plan[2]?.sideB, false)
    }

    func testSheetPlanSinDuplex() {
        let plan = PagePlan.sheetPlan(selection: [0, 1, 2], duplex: false)
        XCTAssertEqual(plan[0]?.sheet, 1); XCTAssertEqual(plan[0]?.sideB, false)
        XCTAssertEqual(plan[1]?.sheet, 2)
        XCTAssertEqual(plan[2]?.sheet, 3)
    }

    // MARK: sequence

    func testSequenceParSinRelleno() {
        XCTAssertEqual(PagePlan.sequence(selection: [0, 1, 2, 3], copies: 1, padBlank: true), [0, 1, 2, 3])
    }

    func testSequenceImparConRelleno() {
        XCTAssertEqual(PagePlan.sequence(selection: [0, 1, 2], copies: 1, padBlank: true), [0, 1, 2, nil])
    }

    func testSequenceImparSinRelleno() {
        XCTAssertEqual(PagePlan.sequence(selection: [0, 1, 2], copies: 1, padBlank: false), [0, 1, 2])
    }

    func testSequenceDosCopiasImparSinRelleno() {
        // Cada copia empieza en hoja nueva: entre copias se inserta una en blanco
        XCTAssertEqual(PagePlan.sequence(selection: [0, 1, 2], copies: 2, padBlank: false),
                       [0, 1, 2, nil, 0, 1, 2])
    }

    func testSequenceDosCopiasImparConRelleno() {
        XCTAssertEqual(PagePlan.sequence(selection: [0, 1, 2], copies: 2, padBlank: true),
                       [0, 1, 2, nil, 0, 1, 2, nil])
    }

    // MARK: plural

    func testPluralSingularYPlural() {
        XCTAssertEqual(PagePlan.plural(1, "página", "páginas"), "1 página")
        XCTAssertEqual(PagePlan.plural(2, "página", "páginas"), "2 páginas")
    }

    // MARK: bookletOrder

    func testBookletOrder4() {
        XCTAssertEqual(PagePlan.bookletOrder(pageCount: 4), [3, 0, 1, 2])
    }

    func testBookletOrderVacio() {
        XCTAssertEqual(PagePlan.bookletOrder(pageCount: 0), [])
    }

    func testBookletOrder1() {
        XCTAssertEqual(PagePlan.bookletOrder(pageCount: 1), [nil, 0, nil, nil])
    }

    func testBookletOrderRellenaAMultiploDe4() {
        XCTAssertEqual(PagePlan.bookletOrder(pageCount: 5).count, 8)
        XCTAssertEqual(PagePlan.bookletOrder(pageCount: 7).count, 8)
    }

    // MARK: nupGrid

    func testNupGrid() {
        XCTAssertEqual(PagePlan.nupGrid(pagesPerSheet: 2).cols, 2)
        XCTAssertEqual(PagePlan.nupGrid(pagesPerSheet: 2).rows, 1)
        XCTAssertEqual(PagePlan.nupGrid(pagesPerSheet: 4).cols, 2)
        XCTAssertEqual(PagePlan.nupGrid(pagesPerSheet: 4).rows, 2)
        XCTAssertEqual(PagePlan.nupGrid(pagesPerSheet: 6).cols, 3)
        XCTAssertEqual(PagePlan.nupGrid(pagesPerSheet: 6).rows, 2)
        XCTAssertEqual(PagePlan.nupGrid(pagesPerSheet: 8).cols, 4)
        XCTAssertEqual(PagePlan.nupGrid(pagesPerSheet: 8).rows, 2)
    }
}
