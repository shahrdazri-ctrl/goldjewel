import Foundation

/// `.mgm` material document (MatrixGold `Common.CyclesModels.MGMaterial`).
///
/// Every field is optional so partially written files from older versions still decode.
/// The JSON uses PascalCase keys; `CodingKeys` preserve that contract exactly.
public struct MGMaterial: Codable, Sendable, Equatable {
    public var bumpMapData: MaterialMapData?
    public var bumpTextureType: Int?
    public var colorMapData: MaterialMapData?
    public var colorTextureType: Int?
    public var descriptionText: String?
    public var diffuse: Int?
    public var hasOnlyDiffuse: Bool?
    public var englishName: String?
    public var environmentMapData: MaterialMapData?
    public var flamingoLibraryGuid: String?
    public var guidToReplace: String?
    public var hasBumpMap: Bool?
    public var hasColorMap: Bool?
    public var hue: Double?
    public var id: String?
    public var ior: Double?
    public var isAlphaMaterial: Bool?
    public var isFavoriteMaterial: Bool?
    public var isGemMaterial: Bool?
    public var isGroundPlaneMaterial: Bool?
    public var isMetalMaterial: Bool?
    public var isMiscellaneousMaterial: Bool?
    public var isRenderMetalMaterial: Bool?
    public var isRenderGemMaterial: Bool?
    public var isModified: Bool?
    public var isUserMaterial: Bool?
    public var luminance: Double?
    public var materialOwner: MaterialOwner?
    public var materialSubType: Int?
    public var materialType: Int?
    public var materialXml: String?
    public var metalQuality: Int?
    public var metalSubType: Int?
    public var metalType: Int?
    public var name: String?
    public var previewBase64: String?
    public var quality: String?
    public var qualityType: String?
    public var reflectionColor: Int?
    public var reflectiveColor: Int?
    public var reflectivity: Double?
    public var saturation: Double?
    public var shine: Double?
    public var specificGravity: Double?
    public var stockSpecificGravity: Double?
    public var hasCustomSpecificGravity: Bool?
    public var specular: Int?
    public var stullerColor: String?
    public var stullerFamily: String?
    public var stullerName: String?
    public var transparency: Double?
    public var transparencyColor: Int?
    public var displayPreviewRender: Bool?
    public var filePath: String?
    public var csMaterialName: String?

    public init() {}

    /// Typed views over the raw integer enum fields.
    public var materialKind: MaterialType? { materialType.flatMap(MaterialType.init(rawValue:)) }
    public var metal: MetalType? { metalType.flatMap(MetalType.init(rawValue:)) }
    public var metalColor: MetalSubType? { metalSubType.flatMap(MetalSubType.init(rawValue:)) }
    public var karat: MetalQuality? { metalQuality.flatMap(MetalQuality.init(rawValue:)) }
    public var textureKind: RenderTextureType? { bumpTextureType.flatMap(RenderTextureType.init(rawValue:)) }

    public static func decode(_ data: Data) throws -> MGMaterial {
        try JSONDecoder().decode(MGMaterial.self, from: data)
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    enum CodingKeys: String, CodingKey {
        case bumpMapData = "BumpMapData"
        case bumpTextureType = "BumpTextureType"
        case colorMapData = "ColorMapData"
        case colorTextureType = "ColorTextureType"
        case descriptionText = "Description"
        case diffuse = "Diffuse"
        case hasOnlyDiffuse = "HasOnlyDiffuse"
        case englishName = "EnglishName"
        case environmentMapData = "EnvironmentMapData"
        case flamingoLibraryGuid = "FlamingoLibraryGuid"
        case guidToReplace = "GuidToReplace"
        case hasBumpMap = "HasBumpMap"
        case hasColorMap = "HasColorMap"
        case hue = "Hue"
        case id = "Id"
        case ior = "Ior"
        case isAlphaMaterial = "IsAlphaMaterial"
        case isFavoriteMaterial = "IsFavoriteMaterial"
        case isGemMaterial = "IsGemMaterial"
        case isGroundPlaneMaterial = "IsGroundPlaneMaterial"
        case isMetalMaterial = "IsMetalMaterial"
        case isMiscellaneousMaterial = "IsMiscellaneousMaterial"
        case isRenderMetalMaterial = "IsRenderMetalMaterial"
        case isRenderGemMaterial = "IsRenderGemMaterial"
        case isModified = "IsModified"
        case isUserMaterial = "IsUserMaterial"
        case luminance = "Luminance"
        case materialOwner = "MaterialOwner"
        case materialSubType = "MaterialSubType"
        case materialType = "MaterialType"
        case materialXml = "MaterialXml"
        case metalQuality = "MetalQuality"
        case metalSubType = "MetalSubType"
        case metalType = "MetalType"
        case name = "Name"
        case previewBase64 = "PreviewBase64"
        case quality = "Quality"
        case qualityType = "QualityType"
        case reflectionColor = "ReflectionColor"
        case reflectiveColor = "ReflectiveColor"
        case reflectivity = "Reflectivity"
        case saturation = "Saturation"
        case shine = "Shine"
        case specificGravity = "SpecificGravity"
        case stockSpecificGravity = "StockSpecificGravity"
        case hasCustomSpecificGravity = "HasCustomSpecificGravity"
        case specular = "Specular"
        case stullerColor = "StullerColor"
        case stullerFamily = "StullerFamily"
        case stullerName = "StullerName"
        case transparency = "Transparency"
        case transparencyColor = "TransparencyColor"
        case displayPreviewRender = "DisplayPreviewRender"
        case filePath = "FilePath"
        case csMaterialName = "CSMaterialName"
    }
}

/// Nested map/texture record (MatrixGold `Common.CyclesModels.MaterialMapData`).
public struct MaterialMapData: Codable, Sendable, Equatable {
    public var blend: Int?
    public var englishName: String?
    public var finishType: Int?
    public var isAvailable: Bool?
    public var isEnvironmentMap: Bool?
    public var isOn: Bool?
    public var isRepeatLocked: Bool?
    public var localName: String?
    public var mapChannelType: Int?
    public var mapPath: String?
    /// Serialized `byte[]`; the desktop format stores base64 text.
    public var mapPreviewBytes: String?
    public var mapType: Int?
    public var repeatX: Double?
    public var repeatY: Double?
    public var repeatRatio: Double?
    public var rotation: Int?
    public var strength: Double?
    public var textureType: Int?
    public var hue: Double?
    public var reflectivity: Double?

    public init() {}

    public var previewData: Data? {
        guard let mapPreviewBytes else { return nil }
        return Data(base64Encoded: mapPreviewBytes)
    }

    enum CodingKeys: String, CodingKey {
        case blend = "Blend"
        case englishName = "EnglishName"
        case finishType = "FinishType"
        case isAvailable = "IsAvailable"
        case isEnvironmentMap = "IsEnvironmentMap"
        case isOn = "IsOn"
        case isRepeatLocked = "IsRepeatLocked"
        case localName = "LocalName"
        case mapChannelType = "MapChannelType"
        case mapPath = "MapPath"
        case mapPreviewBytes = "MapPreviewBytes"
        case mapType = "MapType"
        case repeatX = "RepeatX"
        case repeatY = "RepeatY"
        case repeatRatio = "RepeatRatio"
        case rotation = "Rotation"
        case strength = "Strength"
        case textureType = "TextureType"
        case hue = "Hue"
        case reflectivity = "Reflectivity"
    }
}

/// Who supplied the material (`Common.CyclesModels.MaterialOwner`).
/// The wire format is a bare integer, not a name; `JSONDecoder` cannot decode
/// it into a `String`.
public enum MaterialOwner: Int, Codable, Sendable, CaseIterable {
    case none = 0, stuller, user, publicMaterial
}

public enum MaterialType: Int, Codable, Sendable, CaseIterable {
    case none = 0, metal, gem, groundPlane, miscellaneous, renderMetal, renderGem
}

public enum MetalType: Int, Codable, Sendable, CaseIterable {
    case none = 0, gold, palladium, platinum, silver
}

public enum MetalSubType: Int, Codable, Sendable, CaseIterable {
    case none = 0, green, white, rose, yellow, superWhite, iridium, ruthenium, sterling
}

public enum MetalQuality: Int, Codable, Sendable, CaseIterable {
    case none = 0, metal10K, metal14K, metal18K
}

public enum MaterialSubType: Int, Codable, Sendable, CaseIterable {
    case none = 0, colorMap, environmentMap
}

public enum RenderTextureType: Int, Codable, Sendable, CaseIterable {
    case tileTexture = 0
    case bitmapTexture
    case leatherGrainBumpTexture
    case stuccoTexture
    case noiseTexture
    case other
    case none
}
