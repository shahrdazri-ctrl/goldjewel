import XCTest
@testable import JewelryKit

/// The app's head controls expose gem diameter plus the gallery, dome, bezel
/// and halo families. Every combination the sliders can reach must build, and
/// every emitted triangle must index a vertex that exists, because the preview
/// indexes those meshes directly.
final class HeadAssemblyRangeTests: XCTestCase {
    private func parameters(gem: Double) -> HeadShapeParameters {
        let step = 360.0 / 4
        return HeadShapeParameters(
            gemXSizeMM: gem,
            gemYSizeMM: gem,
            headHeightMM: -2.4,
            prongHeightMM: 1.6,
            angleXDegrees: 12,
            angleYDegrees: 10,
            topAngleDegrees: 2,
            baseAngleDegrees: 4,
            baseAnglePosition: 0.5,
            prongs: (0..<4).map { index in
                ProngPlacement(
                    angleDegrees: 45 + step * Double(index),
                    topX: 0.9,
                    topY: 0.6,
                    baseX: 1.0,
                    baseY: 0.7
                )
            }
        )
    }

    func testGemSliderRangeBuildsWithEveryFamily() {
        // The app's gem slider runs 4...12 mm in 0.1 mm steps.
        for tenths in 40...120 {
            let gem = Double(tenths) / 10
            let assembly: HeadAssembly
            do {
                assembly = try HeadAssembly(
                    parameters: parameters(gem: gem),
                    railParameters: [.standard],
                    domeParameters: .standard,
                    bezelParameters: .standard,
                    haloParameters: .standard
                )
            } catch {
                XCTFail("gem \(gem) mm failed to build with every family: \(error)")
                continue
            }

            assertIndices(assembly.combined, label: "combined at \(gem) mm")
            for (index, prong) in assembly.prongs.enumerated() {
                assertIndices(prong, label: "prong \(index) at \(gem) mm")
            }
            for (index, dome) in assembly.domes.enumerated() {
                assertIndices(dome.mesh, label: "dome \(index) at \(gem) mm")
            }
            for (index, rail) in assembly.rails.enumerated() {
                assertIndices(rail.mesh, label: "rail \(index) at \(gem) mm")
            }
            if let bezel = assembly.bezel {
                assertIndices(bezel.mesh, label: "bezel at \(gem) mm")
            }
            if let halo = assembly.halo {
                assertIndices(halo.band, label: "halo band at \(gem) mm")
                assertIndices(halo.gems, label: "halo gems at \(gem) mm")
                assertIndices(halo.mesh, label: "halo mesh at \(gem) mm")
            }
            XCTAssertFalse(assembly.combined.triangles.isEmpty,
                           "gem \(gem) mm produced no triangles")
        }
    }

    private func assertIndices(
        _ mesh: Mesh3D,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for triangle in mesh.triangles {
            for index in [triangle.a, triangle.b, triangle.c] {
                XCTAssertTrue(
                    mesh.vertices.indices.contains(index),
                    "\(label): triangle index \(index) outside \(mesh.vertices.count) vertices",
                    file: file,
                    line: line
                )
            }
        }
    }
}
