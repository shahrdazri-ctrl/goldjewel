import Foundation

public struct Vec2: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public static let zero = Vec2(0, 0)
}

public struct Vec3: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    public static let zero = Vec3(0, 0, 0)
}

public enum LengthUnit: String, Codable, Sendable, CaseIterable {
    case millimeter, centimeter, inch

    public var millimetersPerUnit: Double {
        switch self {
        case .millimeter: return 1
        case .centimeter: return 10
        case .inch: return 25.4
        }
    }
}

public enum GemShape: String, Codable, Sendable, CaseIterable {
    case roundBrilliant, oval, cushion, emerald, pear, marquise, princess
    case radiant, asscher, heart, trillion, baguette, briolette, cabochon, custom
}

public struct Gemstone: Codable, Hashable, Sendable {
    public var shape: GemShape
    public var lengthMM: Double
    public var widthMM: Double
    public var depthMM: Double?
    /// Carat weight as entered by the user; kept independent of the computed estimate.
    public var carat: Double?
    public var color: String?
    public var clarity: String?
    public var quantity: Int
    public var position: Vec3
    public var rotationRadians: Vec3

    public init(
        shape: GemShape,
        lengthMM: Double,
        widthMM: Double,
        depthMM: Double? = nil,
        carat: Double? = nil,
        color: String? = nil,
        clarity: String? = nil,
        quantity: Int = 1,
        position: Vec3 = .zero,
        rotationRadians: Vec3 = .zero
    ) {
        self.shape = shape
        self.lengthMM = lengthMM
        self.widthMM = widthMM
        self.depthMM = depthMM
        self.carat = carat
        self.color = color
        self.clarity = clarity
        self.quantity = quantity
        self.position = position
        self.rotationRadians = rotationRadians
    }

    public var averageDiameterMM: Double { (lengthMM + widthMM) / 2 }
}

public struct Metal: Codable, Hashable, Sendable {
    public var type: MetalType
    public var color: MetalSubType
    public var quality: MetalQuality
    public var specificGravity: Double

    public init(type: MetalType, color: MetalSubType, quality: MetalQuality, specificGravity: Double) {
        self.type = type
        self.color = color
        self.quality = quality
        self.specificGravity = specificGravity
    }
}

public enum SettingStyle: String, Codable, Sendable, CaseIterable {
    case prong, bezel, channel, pave, halo, tension, flush, cathedral, threeStone, cluster
}

public enum JewelryItemKind: String, Codable, Sendable, CaseIterable {
    case ring, band, pendant, earring, bracelet, custom
}

public struct JewelryItem: Codable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: JewelryItemKind
    public var ringSize: RingSize?
    public var gems: [Gemstone]
    public var metal: Metal?

    public init(
        id: UUID = UUID(),
        name: String,
        kind: JewelryItemKind,
        ringSize: RingSize? = nil,
        gems: [Gemstone] = [],
        metal: Metal? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.ringSize = ringSize
        self.gems = gems
        self.metal = metal
    }
}

/// Document-level settings. MatrixGold works in millimeters with a modeling tolerance;
/// the tolerance drives booleans, joins and meshing.
public struct JewelryDocument: Codable, Sendable {
    public var schemaVersion: Int
    public var units: LengthUnit
    public var absoluteToleranceMM: Double
    public var angleToleranceRadians: Double
    public var items: [JewelryItem]
    public var metadata: [String: String]

    public init(
        schemaVersion: Int = 1,
        units: LengthUnit = .millimeter,
        absoluteToleranceMM: Double = 0.001,
        angleToleranceRadians: Double = 0.017453292519943295,
        items: [JewelryItem] = [],
        metadata: [String: String] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.units = units
        self.absoluteToleranceMM = absoluteToleranceMM
        self.angleToleranceRadians = angleToleranceRadians
        self.items = items
        self.metadata = metadata
    }
}
