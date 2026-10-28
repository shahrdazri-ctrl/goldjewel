import XCTest
@testable import JewelryKit

final class DomainTests: XCTestCase {
    func testDocumentDefaults() {
        let document = JewelryDocument()
        XCTAssertEqual(document.units, .millimeter)
        XCTAssertEqual(document.absoluteToleranceMM, 0.001, accuracy: 1e-12)
        XCTAssertEqual(document.items.count, 0)
    }

    func testGemMeasurements() {
        let gem = Gemstone(shape: .roundBrilliant, lengthMM: 6.5, widthMM: 6.5, carat: 1.0)
        XCTAssertEqual(gem.averageDiameterMM, 6.5, accuracy: 1e-12)
        XCTAssertEqual(gem.position, .zero)
    }

    func testBandBuilderRejectsInvalidDimensions() {
        let size = RingSize(region: .us, name: "7", diameterMM: 17.35, radiusMM: 8.68, index: 28)
        let builder = RingBandBuilder()
        XCTAssertThrowsError(try builder.build(RingBandParameters(ringSize: size, widthMM: 0, thicknessMM: 1.8, profile: .domed)))
    }

    func testBandBuilderProducesRevolve() throws {
        let size = RingSize(region: .us, name: "7", diameterMM: 17.35, radiusMM: 8.68, index: 28)
        let plan = try RingBandBuilder().build(RingBandParameters(ringSize: size, widthMM: 2.0, thicknessMM: 1.8, profile: .domed))
        XCTAssertEqual(plan.operations.count, 2)
        if case let .revolve(profile, axis, angle) = plan.operations[0] {
            XCTAssertEqual(profile.count, 5)
            XCTAssertEqual(axis.z, 1)
            XCTAssertEqual(angle, 2 * Double.pi, accuracy: 1e-12)
        } else {
            XCTFail("expected a revolve operation")
        }
    }

    func testHeadBuilderRejectsTooFewProngs() {
        let gem = Gemstone(shape: .roundBrilliant, lengthMM: 6.5, widthMM: 6.5)
        XCTAssertThrowsError(try HeadBuilder().build(HeadParameters(style: .prong, gem: gem, prongCount: 1)))
    }

    func testHeadBuilderMetadata() throws {
        let gem = Gemstone(shape: .oval, lengthMM: 7.0, widthMM: 5.0)
        let plan = try HeadBuilder().build(HeadParameters(style: .halo, gem: gem, prongCount: 8, milgrain: true))
        XCTAssertEqual(plan.metadata["gemShape"], "oval")
        XCTAssertEqual(plan.metadata["milgrain"], "true")
        XCTAssertEqual(plan.name, "head-halo")
    }

    func testVectorTypesRoundTrip() throws {
        let values: [Vec3] = [Vec3(1, 2, 3), Vec3(-4.5, 0, 6.25)]
        let data = try JSONEncoder().encode(values)
        let decoded = try JSONDecoder().decode([Vec3].self, from: data)
        XCTAssertEqual(values, decoded)
    }
}
