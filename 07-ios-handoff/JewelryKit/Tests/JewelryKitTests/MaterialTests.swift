import XCTest
@testable import JewelryKit

final class MaterialTests: XCTestCase {
    private func fixtureURL(_ name: String = "sample") throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "mgm"))
    }

    func testDecodesSyntheticMaterial() throws {
        let data = try Data(contentsOf: fixtureURL())
        let material = try MGMaterial.decode(data)
        XCTAssertEqual(material.englishName, "*Test Gold")
        XCTAssertEqual(material.name, "Test Gold 14K Yellow")
        XCTAssertEqual(material.specificGravity ?? 0, 13.1, accuracy: 1e-9)
        XCTAssertEqual(material.metalType, MetalType.gold.rawValue)
        XCTAssertEqual(material.metalSubType, MetalSubType.yellow.rawValue)
        XCTAssertEqual(material.metalQuality, MetalQuality.metal14K.rawValue)
        XCTAssertEqual(material.materialType, MaterialType.metal.rawValue)
        XCTAssertEqual(material.materialOwner, MaterialOwner.stuller)
        XCTAssertEqual(material.materialKind, MaterialType.metal)
        XCTAssertEqual(material.metalColor, MetalSubType.yellow)
        XCTAssertEqual(material.karat, MetalQuality.metal14K)
        XCTAssertTrue(material.isMetalMaterial == true)
        XCTAssertFalse(material.isRenderGemMaterial == true)
    }

    // Real shipped materials with their embedded preview images removed.
    func testDecodesRealGroundPlaneMaterial() throws {
        let data = try Data(contentsOf: fixtureURL("real-groundplane"))
        let material = try MGMaterial.decode(data)
        XCTAssertEqual(material.name, "GrayWhiteStudio")
        XCTAssertEqual(material.materialOwner, MaterialOwner.stuller)
        XCTAssertEqual(material.materialKind, MaterialType.groundPlane)
    }

    func testDecodesRealMetalMaterial() throws {
        let data = try Data(contentsOf: fixtureURL("real-metal"))
        let material = try MGMaterial.decode(data)
        XCTAssertEqual(material.name, "Platinum Ruthenium")
        XCTAssertEqual(material.materialOwner, MaterialOwner.stuller)
        XCTAssertEqual(material.metal, MetalType.platinum)
        XCTAssertEqual(material.metalColor, MetalSubType.ruthenium)
        XCTAssertEqual(material.specificGravity ?? 0, 20.69, accuracy: 1e-9)
    }

    func testDecodesNestedMapData() throws {
        let data = try Data(contentsOf: fixtureURL())
        let material = try MGMaterial.decode(data)
        let map = try XCTUnwrap(material.colorMapData)
        XCTAssertEqual(map.localName, "TestNoise")
        XCTAssertEqual(map.mapType, 3)
        XCTAssertEqual(map.repeatX, 2.5)
        XCTAssertEqual(map.repeatY, 2.5)
        XCTAssertEqual(map.strength, 0.75)
        XCTAssertEqual(map.textureType, RenderTextureType.noiseTexture.rawValue)
        XCTAssertEqual(map.previewData?.count, 4)
    }

    func testRoundTrip() throws {
        let data = try Data(contentsOf: fixtureURL())
        let material = try MGMaterial.decode(data)
        let encoded = try material.encoded()
        let again = try MGMaterial.decode(encoded)
        XCTAssertEqual(material, again)
    }

    func testMissingFieldsRemainDecodable() throws {
        let minimal = Data(#"{"EnglishName":"Minimal"}"#.utf8)
        let material = try MGMaterial.decode(minimal)
        XCTAssertEqual(material.englishName, "Minimal")
        XCTAssertNil(material.specificGravity)
        XCTAssertNil(material.colorMapData)
    }

    func testEnumCoverage() {
        XCTAssertEqual(MaterialOwner.stuller.rawValue, 1)
        XCTAssertEqual(MaterialOwner.publicMaterial.rawValue, 3)
        XCTAssertEqual(MaterialType.renderGem.rawValue, 6)
        XCTAssertEqual(MetalSubType.superWhite.rawValue, 5)
        XCTAssertEqual(RenderTextureType.none.rawValue, 6)
    }
}
