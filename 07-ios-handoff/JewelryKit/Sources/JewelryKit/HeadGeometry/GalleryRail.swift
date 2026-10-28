import Foundation

/// Inputs of `CSHeadGalleryRails.GalleryRail_V1`.
///
/// The recovered placement is: a normalised height down the side rail, a
/// horizontal ray intersection with that rail, the two gem-offset outlines,
/// and a swept profile. `position` is `RailPos`, `width`/`height` are
/// `RailX`/`RailY`, and `offset` is `RailOffset`.
///
/// The authored rail profile is a document curve, not a constant in the IL.
/// This port therefore builds the rail as a closed band between the two
/// recovered offset outlines; `height` is that band's thickness. Replacing the
/// band with the authored profile changes no placement maths.
public struct RailParameters: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var position: Double
    public var width: Double
    public var height: Double
    public var offset: Double
    public var shearMultiplier: Double
    public var upperToggle: Bool
    public var moveWithFocalPoint: Bool

    public init(
        enabled: Bool = false,
        position: Double = 0.85,
        width: Double = 0.55,
        height: Double = 0.35,
        offset: Double = 0.15,
        shearMultiplier: Double = 0,
        upperToggle: Bool = false,
        moveWithFocalPoint: Bool = false
    ) {
        self.enabled = enabled
        self.position = position
        self.width = width
        self.height = height
        self.offset = offset
        self.shearMultiplier = shearMultiplier
        self.upperToggle = upperToggle
        self.moveWithFocalPoint = moveWithFocalPoint
    }

    public static let standard = RailParameters(enabled: true)
}

public enum GalleryRailError: Error, Sendable, Equatable {
    case railOutsideHead
    case degenerateOffset
}

/// The two outlines and the band produced for one gallery rail.
public struct GalleryRail: Sendable {
    public var heightMM: Double
    public var outer: [Vec3]
    public var inner: [Vec3]
    public var mesh: Mesh3D
}

/// Port of `CSHeadGalleryRails.GalleryRail_V1` with the authored profile
/// substituted by a constant-thickness band.
///
/// Recovered: rail height `sideX.end.z * (1 - RailPos)`, the intersection of
/// a horizontal ray with the side rails at that height, the gem scaling
/// `(x / GemXMax, y / GemYMax)`, and the two offsets `RailOffset` and
/// `RailOffset - RailX`.
///
/// Inferred: the horizontal intersection is linearly interpolated between the
/// 32 sampled rail points rather than solved on the NURBS curve; the 2D gem
/// offset of an ellipse is approximated by adding the offset to both radii;
/// the band is rectangular because the authored profile is not in the corpus.
public enum GalleryRailBuilder {
    public static let samples = 128
    /// `Intersection.CurveCurve(..., 0.01, 0.01)` in `GalleryRail_V1`.
    public static let intersectionTolerance = 0.01

    public static func build(
        cage: HeadCage,
        parameters: HeadShapeParameters,
        rail: RailParameters
    ) throws -> GalleryRail {
        guard rail.width > 0, rail.height > 0 else {
            throw GalleryRailError.degenerateOffset
        }
        let gemXMax = parameters.gemXSizeMM / 2
        let gemYMax = parameters.gemYSizeMM / 2

        // PointAtEnd is the base of the side rail (z = drop). A RailPos of 0
        // sits on the base, 1 on the girdle.
        let baseZ = cage.sideX.last?.z ?? cage.dropMM
        var z = baseZ * (1 - rail.position)
        if rail.upperToggle {
            z = -rail.height / 2 - rail.position
        }

        let x = try intersectionX(curve: cage.sideX, z: z)
        let y = try intersectionY(curve: cage.sideY, z: z)
        let scaleX = x / gemXMax
        let scaleY = y / gemYMax

        // `GemOffset` at RailOffset and RailOffset - RailX. For an ellipse the
        // exact parallel offset is not an ellipse; adding to both radii keeps
        // the recovered offset distance and is documented as inferred.
        let outerX = gemXMax * scaleX + rail.offset
        let outerY = gemYMax * scaleY + rail.offset
        let innerX = outerX - rail.width
        let innerY = outerY - rail.width
        guard innerX > 0, innerY > 0 else {
            throw GalleryRailError.degenerateOffset
        }

        var outer: [Vec3] = []
        var inner: [Vec3] = []
        outer.reserveCapacity(samples)
        inner.reserveCapacity(samples)
        for index in 0..<samples {
            let angle = 2 * Double.pi * Double(index) / Double(samples)
            let cosine = cos(angle)
            let sine = sin(angle)
            // The rail is centred on its height; top and bottom are the same
            // outline in this substitute.
            outer.append(Vec3(outerX * cosine, outerY * sine, z))
            inner.append(Vec3(innerX * cosine, innerY * sine, z))
        }

        let mesh = band(outer: outer, inner: inner, height: rail.height)
        return GalleryRail(heightMM: z, outer: outer, inner: inner, mesh: mesh)
    }

    /// Linear interpolation of the sampled side rail at a height. The vendor
    /// extends the curve if the ray misses; we clamp to the sampled span.
    static func intersectionX(curve: [Vec3], z: Double) throws -> Double {
        guard let first = curve.first, let last = curve.last else {
            throw GalleryRailError.railOutsideHead
        }
        let low = min(first.z, last.z)
        let high = max(first.z, last.z)
        guard z >= low - intersectionTolerance, z <= high + intersectionTolerance else {
            throw GalleryRailError.railOutsideHead
        }
        return interpolate(curve: curve, z: z).x
    }

    static func intersectionY(curve: [Vec3], z: Double) throws -> Double {
        guard let first = curve.first, let last = curve.last else {
            throw GalleryRailError.railOutsideHead
        }
        let low = min(first.z, last.z)
        let high = max(first.z, last.z)
        guard z >= low - intersectionTolerance, z <= high + intersectionTolerance else {
            throw GalleryRailError.railOutsideHead
        }
        return interpolate(curve: curve, z: z).y
    }

    private static func interpolate(curve: [Vec3], z: Double) -> Vec3 {
        for index in 0..<(curve.count - 1) {
            let a = curve[index]
            let b = curve[index + 1]
            let span = b.z - a.z
            if abs(span) < 1e-12 { continue }
            let t = (z - a.z) / span
            if t >= 0, t <= 1 {
                return a.lerp(b, t)
            }
        }
        // Numerical edge: return the closest endpoint on the requested side.
        return abs(curve[0].z - z) < abs(curve[curve.count - 1].z - z)
            ? curve[0]
            : curve[curve.count - 1]
    }

    /// Four rings around the band: outer bottom/top and inner bottom/top.
    /// Every pair of adjacent angular samples contributes eight triangles.
    static func band(outer: [Vec3], inner: [Vec3], height: Double) -> Mesh3D {
        let count = min(outer.count, inner.count)
        guard count >= 3 else { return Mesh3D() }
        var mesh = Mesh3D()
        let half = height / 2
        for index in 0..<count {
            let o = outer[index]
            let i = inner[index]
            mesh.vertices.append(Vec3(o.x, o.y, o.z - half)) // outer bottom
            mesh.vertices.append(Vec3(o.x, o.y, o.z + half)) // outer top
            mesh.vertices.append(Vec3(i.x, i.y, i.z - half)) // inner bottom
            mesh.vertices.append(Vec3(i.x, i.y, i.z + half)) // inner top
        }
        for index in 0..<count {
            let next = (index + 1) % count
            let o0b = index * 4
            let o0t = o0b + 1
            let i0b = o0b + 2
            let i0t = o0b + 3
            let o1b = next * 4
            let o1t = o1b + 1
            let i1b = o1b + 2
            let i1t = o1b + 3
            // Outer wall
            mesh.triangles.append(MeshTriangle(o0b, o1b, o1t))
            mesh.triangles.append(MeshTriangle(o0b, o1t, o0t))
            // Inner wall, reversed so it faces the gem
            mesh.triangles.append(MeshTriangle(i0b, i0t, i1t))
            mesh.triangles.append(MeshTriangle(i0b, i1t, i1b))
            // Top annulus
            mesh.triangles.append(MeshTriangle(o0t, o1t, i1t))
            mesh.triangles.append(MeshTriangle(o0t, i1t, i0t))
            // Bottom annulus
            mesh.triangles.append(MeshTriangle(o0b, i0b, i1b))
            mesh.triangles.append(MeshTriangle(o0b, i1b, o1b))
        }
        return mesh
    }
}
