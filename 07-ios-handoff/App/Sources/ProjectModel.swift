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
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
        return try? HeadAssembly(parameters: headParameters, railParameters: rails)
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
