import Foundation

/// Inputs from `CSHeadBezel.BezelProfile`.
///
/// `seatHeight`, `seatLength` and `seatAngle` are the three seat parameters the
/// signature takes. `samples` is tessellation only.
public struct BezelParameters: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var seatHeight: Double
    public var seatLength: Double
    public var seatAngle: Double
    public var samples: Int

    public init(
        enabled: Bool = true,
        seatHeight: Double = 0.55,
        seatLength: Double = 0.45,
        seatAngle: Double = 10,
        samples: Int = 128
    ) {
        self.enabled = enabled
        self.seatHeight = seatHeight
        self.seatLength = seatLength
        self.seatAngle = seatAngle
        self.samples = samples
    }

    public static let standard = BezelParameters()
}

public struct Bezel: Sendable {
    public var mesh: Mesh3D
    /// First point of each captured seat construction, at the gem girdle.
    public var seatTopFirst: Vec3
    /// The seat folds under the girdle: `seatHeight` down and `seatLength`
    /// inward at `180° + seatAngle`.
    public var seatLipFirst: Vec3
    /// Outer bottom corner of the collar.
    public var wallBottomFirst: Vec3
    public var topZ: Double
    public var lipZ: Double
    public var tier: ProvenanceTier
}

/// A bezel collar built from the captured seat construction.
///
/// `BezelProfile` builds a closed outline in the prong frame:
///
///     start = prong rail top
///     down  = start + (0, 0, −seatHeight)
///     lip   = down + seatLength · (cos(180° + seatAngle), sin(180° + seatAngle))
///
/// This builder applies that three-point construction at every point of the
/// recovered girdle outline and closes the profile with an outer wall whose
/// width is the same captured `seatLength`. Using the radial direction as the
/// ellipse normal is an approximation (graded `inferred`), and the outer wall
/// stands in for the `RevolveBezel` ruling between the profile and the gem
/// offset curve (graded `reconstructed`). The seat itself is recovered.
public enum BezelBuilder {
    public static let seatAngleOffsetDegrees = 180.0

    public static func build(
        cage: HeadCage,
        bezel: BezelParameters
    ) -> Bezel? {
        guard bezel.enabled, bezel.seatHeight > 0, bezel.seatLength > 0 else {
            return nil
        }
        let girdle = cage.girdle
        guard girdle.count >= 3 else { return nil }
        let samples = max(bezel.samples, 3)
        let angle = (bezel.seatAngle + seatAngleOffsetDegrees) * .pi / 180
        let cosine = cos(angle)
        let sine = sin(angle)
        let height = bezel.seatHeight
        let length = bezel.seatLength

        var mesh = Mesh3D()
        mesh.vertices.reserveCapacity(samples * 4)
        mesh.triangles.reserveCapacity(samples * 8)
        var first: (Vec3, Vec3, Vec3)?

        for index in 0..<samples {
            let position = girdle[index % girdle.count]
            let radial = Vec3(position.x, position.y, 0).normalized(fallback: Vec3(1, 0, 0))
            let top = Vec3(position.x, position.y, 0)
            let lip = top + radial * (length * cosine) + Vec3(0, 0, -(height + length * sine))
            let wallBottom = top + radial * length + Vec3(0, 0, -height)
            let wallTop = top + radial * length
            if first == nil { first = (top, lip, wallBottom) }
            mesh.vertices.append(contentsOf: [top, lip, wallBottom, wallTop])
        }
        for index in 0..<samples {
            let next = (index + 1) % samples
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
        guard let first else { return nil }
        return Bezel(
            mesh: mesh,
            seatTopFirst: first.0,
            seatLipFirst: first.1,
            wallBottomFirst: first.2,
            topZ: first.0.z,
            lipZ: first.1.z,
            tier: .reconstructed
        )
    }
}
