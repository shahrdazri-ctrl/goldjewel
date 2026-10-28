import Foundation

/// One prong's placement and profile dimensions.
///
/// `angleDegrees` is `ProngPointAngle`; the width/height pairs are
/// `ProngTopX/Y` and `ProngBaseX/Y`. The vendor scales the authored profile
/// curve by these values (see `ProngProfileSweep`), so they are dimensions,
/// not radii.
public struct ProngPlacement: Codable, Hashable, Sendable {
    public var angleDegrees: Double
    public var topX: Double
    public var topY: Double
    public var topNudge: Double
    public var baseX: Double
    public var baseY: Double
    public var baseNudge: Double

    public init(
        angleDegrees: Double,
        topX: Double = 1.0,
        topY: Double = 0.75,
        topNudge: Double = 0,
        baseX: Double = 1.1,
        baseY: Double = 0.8,
        baseNudge: Double = 0
    ) {
        self.angleDegrees = angleDegrees
        self.topX = topX
        self.topY = topY
        self.topNudge = topNudge
        self.baseX = baseX
        self.baseY = baseY
        self.baseNudge = baseNudge
    }
}

/// Inputs of `CSHeadShape.HeadShape` for a gem with no base object.
///
/// `headHeightMM` is the vendor's `headHeight` (negative below the girdle);
/// `baseOffsetMM` is `baseOffset`. With a null base object `GetDrop` returns
/// `headHeight + baseOffset`, which is what this port uses.
public struct HeadShapeParameters: Codable, Sendable, Hashable {
    public var gemXSizeMM: Double
    public var gemYSizeMM: Double
    public var headHeightMM: Double
    public var baseOffsetMM: Double
    public var prongHeightMM: Double
    public var angleXDegrees: Double
    public var angleYDegrees: Double
    public var topAngleDegrees: Double
    public var baseAngleDegrees: Double
    public var baseAnglePosition: Double
    /// `CSGemData.BezelParameter`, a normalised curve parameter. The gem table
    /// supplies it; 0.5 is used for the round solitaire fixture.
    public var bezelParameter: Double
    public var prongs: [ProngPlacement]

    public init(
        gemXSizeMM: Double,
        gemYSizeMM: Double,
        headHeightMM: Double,
        baseOffsetMM: Double = 0,
        prongHeightMM: Double,
        angleXDegrees: Double,
        angleYDegrees: Double,
        topAngleDegrees: Double,
        baseAngleDegrees: Double,
        baseAnglePosition: Double,
        bezelParameter: Double = 0.5,
        prongs: [ProngPlacement]
    ) {
        self.gemXSizeMM = gemXSizeMM
        self.gemYSizeMM = gemYSizeMM
        self.headHeightMM = headHeightMM
        self.baseOffsetMM = baseOffsetMM
        self.prongHeightMM = prongHeightMM
        self.angleXDegrees = angleXDegrees
        self.angleYDegrees = angleYDegrees
        self.topAngleDegrees = topAngleDegrees
        self.baseAngleDegrees = baseAngleDegrees
        self.baseAnglePosition = baseAnglePosition
        self.bezelParameter = bezelParameter
        self.prongs = prongs
    }

    /// 6.5 mm round solitaire: four prongs at the diagonals, standard head.
    public static let solitaire = HeadShapeParameters(
        gemXSizeMM: 6.5,
        gemYSizeMM: 6.5,
        headHeightMM: -2.4,
        prongHeightMM: 1.6,
        angleXDegrees: 12,
        angleYDegrees: 10,
        topAngleDegrees: 2,
        baseAngleDegrees: 4,
        baseAnglePosition: 0.5,
        prongs: [
            ProngPlacement(angleDegrees: 45),
            ProngPlacement(angleDegrees: 135),
            ProngPlacement(angleDegrees: 225),
            ProngPlacement(angleDegrees: 315)
        ]
    )
}

public enum HeadShapeError: Error, Sendable, Equatable {
    case invalidGemSize
    case invalidProng(Int)
}

/// The four closed outlines and the prong rails produced by `HeadShape`.
public struct HeadCage: Sendable {
    public var girdle: [Vec3]
    public var middle: [Vec3]
    public var base: [Vec3]
    public var top: [Vec3]
    public var prongRails: [[Vec3]]
    public var bezelRail: [Vec3]
    public var dropMM: Double
    /// Scale factors applied to the girdle outline at the three heights.
    public var scaleBase: Vec3
    public var scaleMiddle: Vec3
    public var scaleTop: Vec3
}

/// Port of `CSBlocks.Settings.Heads.CSHeadBuilderV2.CSHeadShape`.
///
/// Recovered behaviour: `GetDrop` for a null base object, the three scale
/// transforms, the four-point prong rail and the chord-knot interpolation.
/// See `head-geometry-provenance.json` for the IL offset of every literal.
public enum HeadShapeBuilder {
    /// Tessellation only; no vendor value depends on it.
    public static let ringSamples = 128
    public static let railSamples = 32

    public static func build(_ parameters: HeadShapeParameters) throws -> HeadCage {
        guard parameters.gemXSizeMM > 0, parameters.gemYSizeMM > 0 else {
            throw HeadShapeError.invalidGemSize
        }
        for (index, prong) in parameters.prongs.enumerated() {
            guard prong.topX > 0, prong.topY > 0, prong.baseX > 0, prong.baseY > 0 else {
                throw HeadShapeError.invalidProng(index)
            }
        }

        // HeadShape: if (prongHeight < 0.01) prongHeight = 0.01;
        let prongHeight = max(parameters.prongHeightMM, 0.01)
        let drop = parameters.headHeightMM + parameters.baseOffsetMM

        let gemXSize = parameters.gemXSizeMM
        let gemYSize = parameters.gemYSizeMM
        let gemXMax = gemXSize / 2
        let gemYMax = gemYSize / 2

        func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

        let offsetX = drop * tan(radians(parameters.angleXDegrees))
        let offsetY = drop * tan(radians(parameters.angleYDegrees))
        let baseXSize = gemXSize + offsetX * 2
        let baseYSize = gemYSize + offsetY * 2
        let scaleBase = Vec3(baseXSize / gemXSize, baseYSize / gemYSize, 1)

        let position = min(max(parameters.baseAnglePosition, 0), 1)
        let extraX = -drop * position * tan(radians(parameters.angleXDegrees + parameters.baseAngleDegrees))
        let extraY = -drop * position * tan(radians(parameters.angleYDegrees + parameters.baseAngleDegrees))
        let scaleMiddle = Vec3(
            (baseXSize + extraX * 2) / gemXSize,
            (baseYSize + extraY * 2) / gemYSize,
            1
        )
        let middleZ = drop * (1 - position)

        let topXOffset = prongHeight * tan(radians(parameters.angleXDegrees + parameters.topAngleDegrees))
        let topYOffset = prongHeight * tan(radians(parameters.angleYDegrees + parameters.topAngleDegrees))
        let scaleTop = Vec3(
            (gemXSize + topXOffset * 2) / gemXSize,
            (gemYSize + topYOffset * 2) / gemYSize,
            1
        )

        func girdlePoint(angle: Double) -> Vec3 {
            Vec3(gemXMax * cos(angle), gemYMax * sin(angle), 0)
        }

        func ring(_ scale: Vec3, z: Double) -> [Vec3] {
            (0..<ringSamples).map { index in
                let angle = 2 * Double.pi * Double(index) / Double(ringSamples)
                let point = girdlePoint(angle: angle)
                return Vec3(point.x * scale.x, point.y * scale.y, z)
            }
        }

        let girdle = ring(Vec3(1, 1, 1), z: 0)
        let middle = ring(scaleMiddle, z: middleZ)
        let base = ring(scaleBase, z: drop)
        let top = ring(scaleTop, z: prongHeight)

        // A ray at the prong angle meets the girdle ellipse here. This is the
        // recovered `Intersection.CurveCurve(curve2, radialLine)` result.
        func ellipsePoint(polarAngle: Double) -> Vec3 {
            let cosine = cos(polarAngle)
            let sine = sin(polarAngle)
            let denominator = ((cosine / gemXMax) * (cosine / gemXMax) + (sine / gemYMax) * (sine / gemYMax)).squareRoot()
            let radius = 1 / denominator
            return Vec3(radius * cosine, radius * sine, 0)
        }

        func rail(polarAngle: Double) -> [Vec3] {
            let girdlePoint = ellipsePoint(polarAngle: polarAngle)
            let topPoint = Vec3(girdlePoint.x * scaleTop.x, girdlePoint.y * scaleTop.y, prongHeight)
            let middlePoint = Vec3(girdlePoint.x * scaleMiddle.x, girdlePoint.y * scaleMiddle.y, middleZ)
            let basePoint = Vec3(girdlePoint.x * scaleBase.x, girdlePoint.y * scaleBase.y, drop)
            return interpolatedRail([topPoint, girdlePoint, middlePoint, basePoint])
        }

        let prongRails = parameters.prongs.map { rail(polarAngle: radians($0.angleDegrees)) }
        let bezelAngle = parameters.bezelParameter * 2 * Double.pi
        let bezelRail = rail(polarAngle: bezelAngle)

        return HeadCage(
            girdle: girdle,
            middle: middle,
            base: base,
            top: top,
            prongRails: prongRails,
            bezelRail: bezelRail,
            dropMM: drop,
            scaleBase: scaleBase,
            scaleMiddle: scaleMiddle,
            scaleTop: scaleTop
        )
    }

    /// `ProngInterpCurve`: drop points closer than 0.01, guarantee three
    /// points, then interpolate with degree 3 and chord knots.
    public static func interpolatedRail(_ input: [Vec3]) -> [Vec3] {
        var points = input
        var index = 0
        while index < points.count - 1 {
            if (points[index] - points[index + 1]).length < 0.01 {
                points.remove(at: index)
                index = max(index - 1, 0)
            } else {
                index += 1
            }
        }
        if points.count < 2 { return [] }
        if points.count == 2 {
            let middle = points[0].lerp(points[1], 0.1)
            points = [points[0], middle, points[1]]
        }
        return CubicSpline3D(points: points).points(count: railSamples)
    }
}
