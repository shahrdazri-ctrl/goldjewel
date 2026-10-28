import XCTest
@testable import JewelryKit

final class MaterialTests: XCTestCase {
    private func fixtureURL() throws -> URL {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "sample", withExtension: "mgm"))
        return url
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
        XCTAssertEqual(material.materialKind, .metal)
        XCTAssertEqual(material.metalColor, .yellow)
        XCTAssertEqual(material.karat, .metal14K)
        XCTAssertTrue(material.isMetalMaterial == true)
        XCTAssertFalse(material.isRenderGemMaterial == true)
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
        XCTAssertEqual(MaterialType.renderGem.rawValue, 6)
        XCTAssertEqual(MetalSubType.superWhite.rawValue, 5)
        XCTAssertEqual(RenderTextureType.none.rawValue, 6)
    }
}
