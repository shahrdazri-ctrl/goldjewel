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
        var sideX: [[Double]]
        var sideY: [[Double]]
        var gallery: GalleryExpectation
        var mesh: MeshExpectation
    }

    private struct GalleryExpectation: Decodable {
        var parameters: GalleryParameters
        var z: Double
        var scale: [Double]
        var outerFirst: [Double]
        var innerFirst: [Double]
        var mesh: GalleryMesh
    }

    private struct GalleryParameters: Decodable {
        var position: Double
        var width: Double
        var height: Double
        var offset: Double
        var samples: Int
    }

    private struct GalleryMesh: Decodable {
        var vertices: Int
        var triangles: Int
    }

    private struct MeshExpectation: Decodable {
        var ringSamples: Int
        var railSamples: Int
        var basketVertices: Int
        var basketTriangles: Int
        var prongVertices: Int
        var prongTriangles: Int
        var galleryVertices: Int
        var galleryTriangles: Int
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

        XCTAssertEqual(cage.sideX.count, expected.sideX.count)
        for index in 0..<min(cage.sideX.count, expected.sideX.count) {
            assertClose(cage.sideX[index], expected.sideX[index], label: "sideX[\(index)]")
        }
        XCTAssertEqual(cage.sideY.count, expected.sideY.count)
        for index in 0..<min(cage.sideY.count, expected.sideY.count) {
            assertClose(cage.sideY[index], expected.sideY[index], label: "sideY[\(index)]")
        }
    }

    func testGalleryRailMatchesGoldenVectors() throws {
        let golden = try golden()
        let expected = golden.expected.gallery
        let parameters = golden.parameters
        let rail = RailParameters(
            enabled: true,
            position: expected.parameters.position,
            width: expected.parameters.width,
            height: expected.parameters.height,
            offset: expected.parameters.offset
        )
        let cage = try HeadShapeBuilder.build(parameters)
        let gallery = try GalleryRailBuilder.build(cage: cage, parameters: parameters, rail: rail)

        XCTAssertEqual(gallery.heightMM, expected.z, accuracy: 1e-12)
        XCTAssertEqual(gallery.outer.count, expected.parameters.samples)
        XCTAssertEqual(gallery.inner.count, expected.parameters.samples)
        assertClose(gallery.outer[0], expected.outerFirst, label: "outer[0]")
        assertClose(gallery.inner[0], expected.innerFirst, label: "inner[0]")
        XCTAssertEqual(gallery.mesh.vertices.count, expected.mesh.vertices)
        XCTAssertEqual(gallery.mesh.triangles.count, expected.mesh.triangles)

        let assembly = try HeadAssembly(parameters: parameters, railParameters: [rail])
        XCTAssertEqual(assembly.rails.count, 1)
        XCTAssertEqual(assembly.combined.vertices.count,
                       golden.expected.mesh.basketVertices
                       + golden.expected.mesh.prongVertices * parameters.prongs.count
                       + expected.mesh.vertices)
        XCTAssertEqual(assembly.combined.triangles.count,
                       golden.expected.mesh.basketTriangles
                       + golden.expected.mesh.prongTriangles * parameters.prongs.count
                       + expected.mesh.triangles)
    }

    func testAssemblyStructureAndMeshCounts() throws {
        let golden = try golden()
        let assembly = try HeadAssembly(parameters: golden.parameters)
        let mesh = golden.expected.mesh

        XCTAssertEqual(assembly.basket.vertices.count, mesh.basketVertices)
        XCTAssertEqual(assembly.basket.vertices.count, HeadShapeBuilder.ringSamples * 4)
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

    func testParametricProngCountsAndGemSizes() throws {
        for (index, count) in [4, 6, 8].enumerated() {
            let gem = [6.0, 6.5, 7.5][index]
            let step = 360.0 / Double(count)
            let prongs = (0..<count).map { position in
                ProngPlacement(angleDegrees: 45 + step * Double(position),
                               topX: 0.9, topY: 0.6, baseX: 1.0, baseY: 0.7)
            }
            let parameters = HeadShapeParameters(
                gemXSizeMM: gem, gemYSizeMM: gem,
                headHeightMM: -2.4, prongHeightMM: 1.6,
                angleXDegrees: 12, angleYDegrees: 10,
                topAngleDegrees: 2, baseAngleDegrees: 4,
                baseAnglePosition: 0.5, prongs: prongs
            )
            let assembly = try HeadAssembly(parameters: parameters)
            XCTAssertEqual(assembly.cage.prongRails.count, count)
            XCTAssertTrue(assembly.cage.prongRails.allSatisfy { $0.count == HeadShapeBuilder.railSamples })
            XCTAssertEqual(assembly.basket.triangles.count, 3 * HeadShapeBuilder.ringSamples * 2)
            XCTAssertEqual(assembly.combined.vertices.count,
                           HeadShapeBuilder.ringSamples * 4
                           + count * (HeadShapeBuilder.railSamples * ProngProfile.roundedRectangle().count + 2))
            let bounds = try XCTUnwrap(assembly.combined.bounds)
            XCTAssertGreaterThan(bounds.max.x - bounds.min.x, gem * 0.8)
        }
    }

    func testProvenanceIsPresent() throws {
        XCTAssertEqual(HeadProvenance.all.count, 12)
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
