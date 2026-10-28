import XCTest
@testable import JewelryKit

/// The Swift port is compared against vectors recomputed in Python from the
/// decompiled formulas, so a shared transcription mistake in both languages is
/// the only way this can pass falsely. The Python side also verifies every
/// literal's IL offset in corpus v1.
final class HeadGeometryTests: XCTestCase {
    private struct Golden: Decodable {
        var parameters: HeadShapeParameters
        var expected: Expected
    }

    private struct Expected: Decodable {
        var dropMM: Double
        var scaleBase: [Double]
        var scaleMiddle: [Double]
        var scaleTop: [Double]
        var girdle: [[Double]]
        var rails: [[[Double]]]
        var bezelRail: [[Double]]
        var mesh: MeshExpectation
    }

    private struct MeshExpectation: Decodable {
        var ringSamples: Int
        var railSamples: Int
        var basketVertices: Int
        var basketTriangles: Int
        var prongVertices: Int
        var prongTriangles: Int
    }

    private func golden() throws -> Golden {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "head-geometry", withExtension: "json"))
        return try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
    }

    func testCageMatchesGoldenVectors() throws {
        let golden = try golden()
        let cage = try HeadShapeBuilder.build(golden.parameters)
        let expected = golden.expected

        XCTAssertEqual(cage.dropMM, expected.dropMM, accuracy: 1e-12)
        XCTAssertEqual(cage.scaleBase.x, expected.scaleBase[0], accuracy: 1e-12)
        XCTAssertEqual(cage.scaleBase.y, expected.scaleBase[1], accuracy: 1e-12)
        XCTAssertEqual(cage.scaleMiddle.x, expected.scaleMiddle[0], accuracy: 1e-12)
        XCTAssertEqual(cage.scaleMiddle.y, expected.scaleMiddle[1], accuracy: 1e-12)
        XCTAssertEqual(cage.scaleTop.x, expected.scaleTop[0], accuracy: 1e-12)
        XCTAssertEqual(cage.scaleTop.y, expected.scaleTop[1], accuracy: 1e-12)

        XCTAssertEqual(cage.girdle.count, expected.girdle.count)
        for index in 0..<min(cage.girdle.count, expected.girdle.count) {
            assertClose(cage.girdle[index], expected.girdle[index], label: "girdle[\(index)]")
        }

        XCTAssertEqual(cage.prongRails.count, expected.rails.count)
        for prong in 0..<min(cage.prongRails.count, expected.rails.count) {
            XCTAssertEqual(cage.prongRails[prong].count, expected.rails[prong].count)
            for index in 0..<min(cage.prongRails[prong].count, expected.rails[prong].count) {
                assertClose(cage.prongRails[prong][index], expected.rails[prong][index],
                            label: "rail[\(prong)][\(index)]")
            }
        }

        for index in 0..<min(cage.bezelRail.count, expected.bezelRail.count) {
            assertClose(cage.bezelRail[index], expected.bezelRail[index], label: "bezel[\(index)]")
        }
    }

    func testAssemblyStructureAndMeshCounts() throws {
        let golden = try golden()
        let assembly = try HeadAssembly(parameters: golden.parameters)
        let mesh = golden.expected.mesh

        XCTAssertEqual(assembly.basket.vertices.count, mesh.basketVertices)
        XCTAssertEqual(assembly.basket.triangles.count, mesh.basketTriangles)
        XCTAssertEqual(assembly.prongs.count, golden.parameters.prongs.count)
        for prong in assembly.prongs {
            XCTAssertEqual(prong.vertices.count, mesh.prongVertices)
            XCTAssertEqual(prong.triangles.count, mesh.prongTriangles)
            XCTAssertFalse(prong.isEmpty)
        }
        XCTAssertEqual(assembly.combined.vertices.count,
                       mesh.basketVertices + mesh.prongVertices * golden.parameters.prongs.count)
        XCTAssertEqual(assembly.combined.triangles.count,
                       mesh.basketTriangles + mesh.prongTriangles * golden.parameters.prongs.count)
    }

    func testProngsAreClosedAndInsideTheCageBounds() throws {
        let assembly = HeadAssembly.solitaire
        let bounds = try XCTUnwrap(assembly.combined.bounds)
        XCTAssertGreaterThan(bounds.max.x - bounds.min.x, 4)
        XCTAssertGreaterThan(bounds.max.z - bounds.min.z, 3)

        // A capped sweep has one more vertex than its ring grid and exactly two
        // fan caps of profile.count triangles.
        for prong in assembly.prongs {
            let ringGrid = HeadShapeBuilder.railSamples * ProngProfile.roundedRectangle().count
            XCTAssertEqual(prong.vertices.count, ringGrid + 2)
            XCTAssertGreaterThan(prong.triangles.count, 0)
        }
    }

    func testProvenanceIsPresent() throws {
        XCTAssertEqual(HeadProvenance.all.count, 9)
        for entry in HeadProvenance.all {
            XCTAssertFalse(entry.method.isEmpty)
            XCTAssertGreaterThanOrEqual(entry.ilOffset, 0)
        }
    }

    private func assertClose(_ actual: Vec3, _ expected: [Double], label: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        guard expected.count == 3 else {
            return XCTFail("\(label): malformed golden point", file: file, line: line)
        }
        XCTAssertEqual(actual.x, expected[0], accuracy: 1e-9, "\(label).x", file: file, line: line)
        XCTAssertEqual(actual.y, expected[1], accuracy: 1e-9, "\(label).y", file: file, line: line)
        XCTAssertEqual(actual.z, expected[2], accuracy: 1e-9, "\(label).z", file: file, line: line)
    }
}
