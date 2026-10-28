import Foundation

/// A closed 2D profile in the sweep plane, normalised to a unit box.
///
/// The vendor receives this curve from the document (`ProngTopProfile` /
/// `ProngBaseProfile`) and scales it per prong. The authored profile is not a
/// numeric constant in the IL, so the default below is an explicit stand-in:
/// a rounded rectangle with a 0.25 corner fraction. Replacing it with a
/// recovered profile changes no placement maths.
public enum ProngProfile {
    /// 0.5 makes the rounded rectangle a circle, so the scaled profile is an
    /// ellipse: the default prong section. The authored curve can replace it.
    public static let cornerFraction = 0.5

    public static func roundedRectangle(samples: Int = 32) -> [Vec2] {
        let half = 0.5
        let radius = cornerFraction
        let cornerCenters = [
            Vec2(half - radius, half - radius),
            Vec2(-half + radius, half - radius),
            Vec2(-half + radius, -half + radius),
            Vec2(half - radius, -half + radius)
        ]
        // Start at the top-right corner's 90° point and walk counter-clockwise.
        let cornerStart = [0.0, Double.pi / 2, Double.pi, 3 * Double.pi / 2]
        var points: [Vec2] = []
        let perCorner = max(samples / 4, 2)
        for corner in 0..<4 {
            for step in 0...perCorner {
                let angle = cornerStart[corner] + (Double.pi / 2) * Double(step) / Double(perCorner)
                points.append(Vec2(
                    cornerCenters[corner].x + radius * cos(angle),
                    cornerCenters[corner].y + radius * sin(angle)
                ))
            }
        }
        return points
    }
}

public enum ProngSweeper {
    /// `ProngProfileSweep` scales the authored profile by the prong's
    /// width/height and, for a planar dome, by `1/cos(angle)` where the angle
    /// is between the downgoing rail tangent and the head tangent.
    static func secantFactor(tangent: Vec3) -> Double {
        let angle = acos(min(max((-tangent).dot(Vec3(0, 0, 1)) , -1), 1))
        let cosine = cos(angle)
        return cosine > 1e-6 ? 1 / cosine : 1
    }

    /// The section at one rail sample. Exposed so a dome cap sits on exactly
    /// the same top ring as the prong solid.
    public static func section(
        rail: [Vec3],
        index: Int,
        prong: ProngPlacement,
        profile: [Vec2] = ProngProfile.roundedRectangle()
    ) -> [Vec3] {
        guard rail.count >= 2, rail.indices.contains(index) else { return [] }
        let tangent = (rail[1] - rail[0]).normalized()
        let secant = secantFactor(tangent: tangent)

        // Recovered offsets: (0 - ProngTopY) * ProngTopNudge, likewise base.
        let topOffset = -prong.topY * prong.topNudge
        let baseOffset = -prong.baseY * prong.baseNudge
        let topScale = Vec2(prong.topX, prong.topY * secant)
        let baseScale = Vec2(prong.baseX, prong.baseY)

        let origin = rail[index]
        let previous = rail[max(index - 1, 0)]
        let next = rail[min(index + 1, rail.count - 1)]
        let railTangent = (next - previous).normalized(fallback: tangent)

        // The sweep plane is perpendicular to the rail. Width runs along the
        // tangential direction; thickness runs radially outwards.
        let radial = Vec3(origin.x, origin.y, 0).normalized(fallback: Vec3(0, 1, 0))
        var side = railTangent.cross(radial).normalized(fallback: Vec3(1, 0, 0))
        if side.length < 1e-9 { side = Vec3(1, 0, 0) }
        let normal = side.cross(railTangent).normalized(fallback: radial)

        let t = Double(index) / Double(rail.count - 1)
        let scale = Vec2(
            topScale.x + (baseScale.x - topScale.x) * t,
            topScale.y + (baseScale.y - topScale.y) * t
        )
        let offset = topOffset + (baseOffset - topOffset) * t
        return profile.map {
            origin + side * ($0.x * scale.x) + normal * ($0.y * scale.y + offset)
        }
    }

    /// Places the profile at the start (top) and end (base) of the rail and
    /// lofts between those two sections along the rail.
    public static func solid(rail: [Vec3], prong: ProngPlacement) -> Mesh3D {
        guard rail.count >= 2 else { return Mesh3D() }
        let profile = ProngProfile.roundedRectangle()
        let rings = (0..<rail.count).map {
            section(rail: rail, index: $0, prong: prong, profile: profile)
        }
        return Mesh3D.loft(rings: rings, closedRing: true, capStart: true, capEnd: true)
    }
}
