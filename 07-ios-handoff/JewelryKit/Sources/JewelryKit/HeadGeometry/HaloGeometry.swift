import Foundation

/// Inputs for the halo/cluster placement path.
///
/// These are the documented arguments of
/// `CSClusterGemShapes.CSClusterGemRound.PlaceGems`: `offsetRailX` and
/// `offsetRailZ` offset the seat path from the centre gem, `spacing` is the
/// gap between neighbouring melee stones, `fixPosition` rotates the array and
/// `isEven` forces an even count.
public struct HaloParameters: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var gemDiameter: Double
    public var spacing: Double
    public var offsetRailX: Double
    public var offsetRailZ: Double
    public var even: Bool
    public var fixPosition: Double

    public init(
        enabled: Bool = true,
        gemDiameter: Double = 1.25,
        spacing: Double = 0.18,
        offsetRailX: Double = 0.75,
        offsetRailZ: Double = 0.05,
        even: Bool = false,
        fixPosition: Double = 0
    ) {
        self.enabled = enabled
        self.gemDiameter = gemDiameter
        self.spacing = spacing
        self.offsetRailX = offsetRailX
        self.offsetRailZ = offsetRailZ
        self.even = even
        self.fixPosition = fixPosition
    }

    public static let standard = HaloParameters()
}

public struct HaloSeat: Codable, Hashable, Sendable {
    public var position: Vec3
    public var yawRadians: Double
    public var gemDiameter: Double
}

public struct Halo: Sendable {
    /// Metal band plus the proxy melee stones, in that order.
    public var mesh: Mesh3D
    public var band: Mesh3D
    public var gems: Mesh3D
    public var centers: [Vec3]
    public var seats: [HaloSeat]
    public var count: Int
    /// Placement is recovered; the band is reconstructed from the seat path;
    /// the proxy stones are inferred because the gem table is not rendered.
    public var tier: ProvenanceTier
    public var bandTier: ProvenanceTier
    public var gemTier: ProvenanceTier
}

/// Places melee stones around the centre gem.
///
/// `PlaceGems` is captured in corpus v2. Its recovered behaviour is:
///
///     count = int(curveLength / (gemDiameter + spacing))
///     if even && count is odd { count -= 1 }
///     step = 1 / count
///     phase = fixPosition % step
///     parameters[i] = phase + i·step (wrapped), sorted
///
/// The seat path is the gem offset curve translated by `offsetRailZ`; this port
/// samples the same ellipse the recovered girdle uses, offset by `offsetRailX`.
/// Rhino's `NormalizedLengthParameters` is reproduced by arc-length lookup.
/// The metal is a modelled band and the melee stones are proxy crowns; both are
/// graded separately so the placement can be trusted without overclaiming the
/// visual surface.
public enum HaloBuilder {
    public static let curveSamples = 256
    public static let bandSamples = 128
    public static let proxyFacets = 6

    public static func build(
        parameters: HeadShapeParameters,
        halo: HaloParameters
    ) -> Halo? {
        guard halo.enabled, halo.gemDiameter > 0, halo.spacing >= 0 else { return nil }
        let radiusX = parameters.gemXSizeMM / 2 + halo.offsetRailX
        let radiusY = parameters.gemYSizeMM / 2 + halo.offsetRailX
        guard radiusX > 0, radiusY > 0 else { return nil }

        var curve: [Vec3] = []
        curve.reserveCapacity(curveSamples)
        for index in 0..<curveSamples {
            let angle = 2 * Double.pi * Double(index) / Double(curveSamples)
            curve.append(Vec3(radiusX * cos(angle), radiusY * sin(angle), halo.offsetRailZ))
        }
        var cumulative = [0.0]
        for index in 1...curveSamples {
            let a = curve[index - 1]
            let b = curve[index % curveSamples]
            cumulative.append(cumulative.last! + (b - a).length)
        }
        let totalLength = cumulative.last!
        var count = Int(totalLength / (halo.gemDiameter + halo.spacing))
        if halo.even, count % 2 == 1 { count -= 1 }
        count = max(count, 3)

        let step = 1.0 / Double(count)
        let phase = halo.fixPosition.truncatingRemainder(dividingBy: step)
        var parametersOnCurve: [Double] = []
        parametersOnCurve.reserveCapacity(count)
        for index in 0..<count {
            var u = phase + Double(index) * step
            if u > 1 { u -= 1 }
            parametersOnCurve.append(u)
        }
        parametersOnCurve.sort()

        var centers: [Vec3] = []
        var seats: [HaloSeat] = []
        centers.reserveCapacity(count)
        seats.reserveCapacity(count)
        for u in parametersOnCurve {
            let point = pointAt(normalizedArc: u, curve: curve, cumulative: cumulative)
            let ahead = pointAt(normalizedArc: (u + 0.001).truncatingRemainder(dividingBy: 1),
                                curve: curve, cumulative: cumulative)
            let tangent = (ahead - point).normalized(fallback: Vec3(1, 0, 0))
            centers.append(point)
            seats.append(HaloSeat(
                position: point,
                yawRadians: atan2(tangent.y, tangent.x),
                gemDiameter: halo.gemDiameter
            ))
        }

        let band = buildBand(radiusX: radiusX, radiusY: radiusY, z: halo.offsetRailZ,
                             gemDiameter: halo.gemDiameter)
        var gems = Mesh3D()
        for seat in seats {
            appendProxy(seat: seat, into: &gems)
        }
        var mesh = band
        mesh.append(gems)
        return Halo(
            mesh: mesh,
            band: band,
            gems: gems,
            centers: centers,
            seats: seats,
            count: count,
            tier: .reconstructed,
            bandTier: .reconstructed,
            gemTier: .inferred
        )
    }

    static func pointAt(normalizedArc u: Double, curve: [Vec3], cumulative: [Double]) -> Vec3 {
        let target = min(max(u, 0), 1) * cumulative[cumulative.count - 1]
        var low = 0
        var high = cumulative.count - 1
        while low < high - 1 {
            let middle = (low + high) / 2
            if cumulative[middle] <= target { low = middle } else { high = middle }
        }
        let span = cumulative[high] - cumulative[low]
        let t = span > 1e-12 ? (target - cumulative[low]) / span : 0
        return curve[low].lerp(curve[high % curve.count], t)
    }

    /// A rectangular band along the seat path. It is narrower than a melee
    /// stone and sits below the seats, so the stones read as separate and the
    /// halo does not become a solid washer from above.
    private static func buildBand(
        radiusX: Double,
        radiusY: Double,
        z: Double,
        gemDiameter: Double
    ) -> Mesh3D {
        let halfWidth = gemDiameter * 0.30
        let halfHeight = gemDiameter * 0.12
        let bandZ = z - gemDiameter * 0.25
        var mesh = Mesh3D()
        mesh.vertices.reserveCapacity(bandSamples * 4)
        mesh.triangles.reserveCapacity(bandSamples * 8)
        for index in 0..<bandSamples {
            let angle = 2 * Double.pi * Double(index) / Double(bandSamples)
            let position = Vec3(radiusX * cos(angle), radiusY * sin(angle), z)
            let radial = Vec3(cos(angle), sin(angle), 0).normalized()
            let outer = position + radial * halfWidth
            let inner = position - radial * halfWidth
            mesh.vertices.append(Vec3(outer.x, outer.y, bandZ + halfHeight))
            mesh.vertices.append(Vec3(outer.x, outer.y, bandZ - halfHeight))
            mesh.vertices.append(Vec3(inner.x, inner.y, bandZ - halfHeight))
            mesh.vertices.append(Vec3(inner.x, inner.y, bandZ + halfHeight))
        }
        for index in 0..<bandSamples {
            let next = (index + 1) % bandSamples
            let order = [(0, 1), (1, 2), (2, 3), (3, 0)]
            for (a, b) in order {
                let i0 = index * 4 + a
                let j0 = index * 4 + b
                let i1 = next * 4 + a
                let j1 = next * 4 + b
                mesh.triangles.append(MeshTriangle(i0, j0, j1))
                mesh.triangles.append(MeshTriangle(i0, j1, i1))
            }
        }
        return mesh
    }

    /// Octagonal melee proxy: girdle, pavilion tip, crown ring and table.
    /// Geometry is inferred; the seat position and yaw are recovered.
    private static func appendProxy(seat: HaloSeat, into mesh: inout Mesh3D) {
        let base = mesh.vertices.count
        let radius = seat.gemDiameter / 2
        let cosine = cos(seat.yawRadians)
        let sine = sin(seat.yawRadians)
        func rotated(_ x: Double, _ y: Double) -> Vec3 {
            Vec3(x * cosine - y * sine, x * sine + y * cosine, 0)
        }
        for index in 0..<proxyFacets {
            let angle = 2 * Double.pi * Double(index) / Double(proxyFacets)
            let point = rotated(radius * cos(angle), radius * sin(angle))
            mesh.vertices.append(seat.position + point)
        }
        let bottom = mesh.vertices.count
        mesh.vertices.append(seat.position + Vec3(0, 0, -radius * 0.9))
        let topStart = mesh.vertices.count
        for index in 0..<proxyFacets {
            let angle = 2 * Double.pi * Double(index) / Double(proxyFacets)
            let point = rotated(radius * 0.35 * cos(angle), radius * 0.35 * sin(angle))
            mesh.vertices.append(seat.position + point + Vec3(0, 0, radius * 0.55))
        }
        let table = mesh.vertices.count
        mesh.vertices.append(seat.position + Vec3(0, 0, radius * 0.7))

        for index in 0..<proxyFacets {
            let next = (index + 1) % proxyFacets
            mesh.triangles.append(MeshTriangle(base + index, bottom, base + next))
            mesh.triangles.append(MeshTriangle(base + index, base + next, topStart + next))
            mesh.triangles.append(MeshTriangle(base + index, topStart + next, topStart + index))
            mesh.triangles.append(MeshTriangle(topStart + index, topStart + next, table))
        }
    }
}
