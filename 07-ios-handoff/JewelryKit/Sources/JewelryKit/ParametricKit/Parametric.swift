import Foundation

/// A geometry program produced by a builder. The iOS kernel translates these operations
/// into OCCT/Rhino Compute/Metal calls; the builder itself stays kernel-independent.
public enum GeometryOperation: Codable, Sendable, Equatable {
    case revolve(profile: [Vec2], axis: Vec3, angleRadians: Double)
    case sweep(profile: [Vec2], rail: [Vec3], closed: Bool)
    case loft(sections: [[Vec3]], closed: Bool)
    case booleanUnion
    case booleanDifference
    case booleanIntersection
    case fillet(radiusMM: Double)
    case offset(distanceMM: Double)
    case polarArray(count: Int, center: Vec3, axis: Vec3)
    case mirror(planeNormal: Vec3, planeOrigin: Vec3)
    case mesh(deviationMM: Double)
}

public struct GeometryPlan: Codable, Sendable, Equatable {
    public var name: String
    public var operations: [GeometryOperation]
    public var metadata: [String: String]

    public init(name: String, operations: [GeometryOperation], metadata: [String: String] = [:]) {
        self.name = name
        self.operations = operations
        self.metadata = metadata
    }
}

public enum BuildError: Error, Sendable, Equatable {
    case invalidParameter(String)
    case unsupportedStyle(SettingStyle)
    case geometryFailure(String)
}

public protocol ParametricBuilder: Sendable {
    associatedtype Parameters: Codable & Sendable
    func build(_ parameters: Parameters) throws -> GeometryPlan
}

public enum BandProfile: String, Codable, Sendable, CaseIterable {
    case flat, domed, halfRound, knifeEdge, comfortFit, concave, twisted, rope
}

public struct RingBandParameters: Codable, Sendable {
    public var ringSize: RingSize
    public var widthMM: Double
    public var thicknessMM: Double
    public var profile: BandProfile
    public var innerDiameterMM: Double?
    public var taperMM: Double?

    public init(
        ringSize: RingSize,
        widthMM: Double,
        thicknessMM: Double,
        profile: BandProfile,
        innerDiameterMM: Double? = nil,
        taperMM: Double? = nil
    ) {
        self.ringSize = ringSize
        self.widthMM = widthMM
        self.thicknessMM = thicknessMM
        self.profile = profile
        self.innerDiameterMM = innerDiameterMM
        self.taperMM = taperMM
    }
}

public struct HeadParameters: Codable, Sendable {
    public var style: SettingStyle
    public var gem: Gemstone
    public var prongCount: Int
    public var prongDiameterMM: Double
    public var seatDepthMM: Double
    public var galleryHeightMM: Double
    public var milgrain: Bool

    public init(
        style: SettingStyle,
        gem: Gemstone,
        prongCount: Int = 4,
        prongDiameterMM: Double = 0.9,
        seatDepthMM: Double = 0.8,
        galleryHeightMM: Double = 1.2,
        milgrain: Bool = false
    ) {
        self.style = style
        self.gem = gem
        self.prongCount = prongCount
        self.prongDiameterMM = prongDiameterMM
        self.seatDepthMM = seatDepthMM
        self.galleryHeightMM = galleryHeightMM
        self.milgrain = milgrain
    }
}

public struct RingBandBuilder: ParametricBuilder {
    public init() {}

    public func build(_ parameters: RingBandParameters) throws -> GeometryPlan {
        guard parameters.widthMM > 0, parameters.thicknessMM > 0 else {
            throw BuildError.invalidParameter("widthMM and thicknessMM must be positive")
        }
        let inner = parameters.innerDiameterMM ?? parameters.ringSize.diameterMM
        let outer = inner + 2 * parameters.thicknessMM
        guard outer > inner else {
            throw BuildError.invalidParameter("outer diameter must exceed inner diameter")
        }
        let halfWidth = parameters.widthMM / 2
        let profile: [Vec2] = [
            Vec2(inner / 2, -halfWidth),
            Vec2(outer / 2, -halfWidth),
            Vec2(outer / 2, halfWidth),
            Vec2(inner / 2, halfWidth),
            Vec2(inner / 2, -halfWidth)
        ]
        return GeometryPlan(
            name: "band-\(parameters.profile.rawValue)",
            operations: [
                .revolve(profile: profile, axis: Vec3(0, 0, 1), angleRadians: 2 * .pi),
                .mesh(deviationMM: 0.02)
            ],
            metadata: [
                "innerDiameterMM": String(inner),
                "widthMM": String(parameters.widthMM),
                "profile": parameters.profile.rawValue
            ]
        )
    }
}

public struct HeadBuilder: ParametricBuilder {
    public init() {}

    public func build(_ parameters: HeadParameters) throws -> GeometryPlan {
        guard parameters.prongCount >= 2 else {
            throw BuildError.invalidParameter("prongCount must be at least 2")
        }
        guard parameters.prongDiameterMM > 0 else {
            throw BuildError.invalidParameter("prongDiameterMM must be positive")
        }
        return GeometryPlan(
            name: "head-\(parameters.style.rawValue)",
            operations: [
                .polarArray(
                    count: parameters.prongCount,
                    center: parameters.gem.position,
                    axis: Vec3(0, 0, 1)
                ),
                .mesh(deviationMM: 0.015)
            ],
            metadata: [
                "gemShape": parameters.gem.shape.rawValue,
                "gemDiameterMM": String(parameters.gem.averageDiameterMM),
                "style": parameters.style.rawValue,
                "milgrain": String(parameters.milgrain)
            ]
        )
    }
}
