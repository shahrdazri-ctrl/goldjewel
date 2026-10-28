import Foundation
import JewelryKit

/// One editable design. This is the app's document model: everything the
/// recovered builders need is stored here and written as JSON.
struct JewelryProject: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var gemDiameterMM: Double
    var prongCount: Int
    var headHeightMM: Double
    var prongHeightMM: Double
    var angleXDegrees: Double
    var angleYDegrees: Double
    var topAngleDegrees: Double
    var baseAngleDegrees: Double
    var baseAnglePosition: Double
    var metalName: String
    var ringRegion: RingSizeRegion
    var ringSizeName: String
    var rail: RailParameters
    var dome: ProngDomeParameters
    var bezel: BezelParameters?
    var halo: HaloParameters?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "Untitled Solitaire",
        gemDiameterMM: Double = 6.5,
        prongCount: Int = 4,
        headHeightMM: Double = -2.4,
        prongHeightMM: Double = 1.6,
        angleXDegrees: Double = 12,
        angleYDegrees: Double = 10,
        topAngleDegrees: Double = 2,
        baseAngleDegrees: Double = 4,
        baseAnglePosition: Double = 0.5,
        metalName: String = "18K Yellow Gold",
        ringRegion: RingSizeRegion = .us,
        ringSizeName: String = "7",
        rail: RailParameters = .standard,
        dome: ProngDomeParameters = .standard,
        bezel: BezelParameters? = nil,
        halo: HaloParameters? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.gemDiameterMM = gemDiameterMM
        self.prongCount = prongCount
        self.headHeightMM = headHeightMM
        self.prongHeightMM = prongHeightMM
        self.angleXDegrees = angleXDegrees
        self.angleYDegrees = angleYDegrees
        self.topAngleDegrees = topAngleDegrees
        self.baseAngleDegrees = baseAngleDegrees
        self.baseAnglePosition = baseAnglePosition
        self.metalName = metalName
        self.ringRegion = ringRegion
        self.ringSizeName = ringSizeName
        self.rail = rail
        self.dome = dome
        self.bezel = bezel
        self.halo = halo
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, gemDiameterMM, prongCount, headHeightMM, prongHeightMM
        case angleXDegrees, angleYDegrees, topAngleDegrees, baseAngleDegrees
        case baseAnglePosition, metalName, ringRegion, ringSizeName, rail
        case dome, bezel, halo, createdAt, updatedAt
    }

    /// Older saved projects predate the dome/bezel/halo families. Decode them
    /// with the dome on (it is now part of the head) and the two optional
    /// families off, so opening an existing document never fails.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        gemDiameterMM = try container.decode(Double.self, forKey: .gemDiameterMM)
        prongCount = try container.decode(Int.self, forKey: .prongCount)
        headHeightMM = try container.decode(Double.self, forKey: .headHeightMM)
        prongHeightMM = try container.decode(Double.self, forKey: .prongHeightMM)
        angleXDegrees = try container.decode(Double.self, forKey: .angleXDegrees)
        angleYDegrees = try container.decode(Double.self, forKey: .angleYDegrees)
        topAngleDegrees = try container.decode(Double.self, forKey: .topAngleDegrees)
        baseAngleDegrees = try container.decode(Double.self, forKey: .baseAngleDegrees)
        baseAnglePosition = try container.decode(Double.self, forKey: .baseAnglePosition)
        metalName = try container.decode(String.self, forKey: .metalName)
        ringRegion = try container.decode(RingSizeRegion.self, forKey: .ringRegion)
        ringSizeName = try container.decode(String.self, forKey: .ringSizeName)
        rail = try container.decode(RailParameters.self, forKey: .rail)
        dome = try container.decodeIfPresent(ProngDomeParameters.self, forKey: .dome) ?? .standard
        bezel = try container.decodeIfPresent(BezelParameters.self, forKey: .bezel)
        halo = try container.decodeIfPresent(HaloParameters.self, forKey: .halo)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    /// The recovered head builder's inputs. Prong section dimensions are the
    /// fixture values from the M3 slice; the builder family that authors them
    /// is not in corpus v1 yet.
    var headParameters: HeadShapeParameters {
        let step = 360.0 / Double(max(prongCount, 1))
        let prongs = (0..<max(prongCount, 1)).map { index in
            ProngPlacement(
                angleDegrees: 45 + step * Double(index),
                topX: 0.9,
                topY: 0.6,
                baseX: 1.0,
                baseY: 0.7
            )
        }
        return HeadShapeParameters(
            gemXSizeMM: gemDiameterMM,
            gemYSizeMM: gemDiameterMM,
            headHeightMM: headHeightMM,
            baseOffsetMM: 0,
            prongHeightMM: prongHeightMM,
            angleXDegrees: angleXDegrees,
            angleYDegrees: angleYDegrees,
            topAngleDegrees: topAngleDegrees,
            baseAngleDegrees: baseAngleDegrees,
            baseAnglePosition: baseAnglePosition,
            prongs: prongs
        )
    }

    var assembly: HeadAssembly? {
        let rails = rail.enabled ? [rail] : []
        return try? HeadAssembly(
            parameters: headParameters,
            railParameters: rails,
            domeParameters: dome,
            bezelParameters: bezel,
            haloParameters: halo
        )
    }

    var ringSize: RingSize? {
        RingSizeCatalog.bundled.size(region: ringRegion, name: ringSizeName)
    }

    static let metalOptions = [
        "18K Yellow Gold",
        "18K White Gold",
        "18K Rose Gold",
        "Platinum 950",
        "Sterling Silver",
        "Palladium 950"
    ]
}
