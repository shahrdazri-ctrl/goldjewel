import XCTest
@testable import JewelryKit

final class RingSizingTests: XCTestCase {
    private let catalog = RingSizeCatalog.bundled

    func testCatalogCoverage() {
        XCTAssertEqual(catalog.regions.count, 22)
        XCTAssertEqual(catalog.totalSizeCount, 7005)
        XCTAssertEqual(catalog.table(for: .us)?.count, 65)
        XCTAssertEqual(catalog.table(for: .uk)?.count, 66)
        XCTAssertEqual(catalog.table(for: .eu)?.count, 39)
        XCTAssertEqual(catalog.table(for: .jp)?.count, 37)
        XCTAssertEqual(catalog.table(for: .fr)?.count, 160)
        XCTAssertEqual(catalog.table(for: .de)?.count, 38)
        XCTAssertEqual(catalog.table(for: .ch)?.count, 160)
        XCTAssertEqual(catalog.table(for: .diameterMM)?.kind, .mathematical)
    }

    func testFormulaRegionsMatchCatalogExactly() {
        for region in RingSizeRegion.formulaRegions {
            guard let count = RingSizeMath.count(for: region), let table = catalog.table(for: region) else {
                XCTFail("missing table for \(region)")
                continue
            }
            XCTAssertEqual(table.count, count, "count mismatch for \(region)")
            for index in 0..<count {
                guard let size = table.size(at: index) else {
                    XCTFail("missing size \(index) in \(region)")
                    continue
                }
                XCTAssertEqual(RingSizeMath.name(region: region, index: index), size.name, "\(region) name @\(index)")
                XCTAssertEqual(RingSizeMath.diameterMM(region: region, index: index) ?? .nan, size.diameterMM, accuracy: 1e-9, "\(region) diameter @\(index)")
                XCTAssertEqual(RingSizeMath.radiusMM(region: region, index: index) ?? .nan, size.radiusMM, accuracy: 1e-9, "\(region) radius @\(index)")
            }
        }
    }

    func testNameRoundTrip() {
        let cases: [(RingSizeRegion, String)] = [
            (.us, "7"), (.us, "7 1/2"), (.uk, "N"), (.uk, "Z+2"),
            (.eu, "54"), (.jp, "13"), (.fr, "55"), (.de, "17"), (.ch, "12")
        ]
        for (region, name) in cases {
            let size = catalog.size(region: region, name: name)
            XCTAssertNotNil(size, "\(region) \(name)")
            if let size {
                XCTAssertEqual(RingSizeMath.index(region: region, diameterMM: size.diameterMM), size.index, "\(region) \(name) index")
            }
        }
    }

    func testFractionNormalization() {
        XCTAssertEqual(RingSizeCatalog.normalizeName("7.5"), "7 1/2")
        XCTAssertEqual(RingSizeCatalog.normalizeName("7 1/2"), "7 1/2")
        XCTAssertEqual(RingSizeCatalog.normalizeName("7.25"), "7 1/4")
        XCTAssertEqual(RingSizeCatalog.normalizeName("7.75"), "7 3/4")
        XCTAssertNotNil(catalog.size(region: .us, name: "7.5"))
    }

    func testNearestClamps() {
        let smallest = catalog.nearest(region: .us, diameterMM: 0)
        let largest = catalog.nearest(region: .us, diameterMM: 1_000)
        XCTAssertEqual(smallest?.name, catalog.table(for: .us)?.sizes.first?.name)
        XCTAssertEqual(largest?.name, catalog.table(for: .us)?.sizes.last?.name)
    }

    func testIndexClamping() {
        XCTAssertEqual(RingSizeMath.index(region: .us, diameterMM: 0), 0)
        XCTAssertEqual(RingSizeMath.index(region: .us, diameterMM: 100), 64)
        XCTAssertEqual(RingSizeMath.index(region: .eu, diameterMM: 0), 0)
    }

    func testCircumferenceRelation() {
        let size = catalog.size(region: .eu, index: 13)
        XCTAssertNotNil(size)
        if let size {
            XCTAssertEqual(size.circumferenceMM, size.diameterMM * .pi, accuracy: 1e-9)
        }
    }

    func testDisplayStringShape() {
        let size = RingSize(region: .us, name: "7", diameterMM: 17.35, radiusMM: 8.68, index: 28)
        XCTAssertEqual(size.displayString, "US:7:17.35")
    }

    func testFormulaSizeComposition() throws {
        let size = try XCTUnwrap(RingSizeMath.size(region: .uk, index: 51))
        XCTAssertEqual(size.name, "Z 1/2")
        XCTAssertEqual(size.index, 51)
    }
}
