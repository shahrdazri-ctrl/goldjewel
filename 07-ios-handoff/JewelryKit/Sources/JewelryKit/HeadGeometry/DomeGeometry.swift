import Foundation

/// Inputs used by `CSHeadBezel.ProngDomeCurve`.
///
/// `height` is `ProngDomeHeight`; `settingDistance` and `settingAngle` are the
/// two `ProngDomeSetting*` values. The six blend values remain explicit because
/// the vendor exposes all of them as inputs even though the built-in head uses
/// the defaults.
public struct ProngDomeParameters: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var height: Double
    public var settingDistance: Double
    public var settingAngle: Double
    public var planar: Bool
    public var blendAmount: Double
    public var blendStartInside: Double
    public var blendEndInside: Double
    public var blendStartOutside: Double
    public var blendEndOutside: Double

    public init(
        enabled: Bool = true,
        height: Double = 0.7,
        settingDistance: Double = 0,
        settingAngle: Double = 0,
        planar: Bool = false,
        blendAmount: Double = 1,
        blendStartInside: Double = 1,
        blendEndInside: Double = 1,
        blendStartOutside: Double = 1,
        blendEndOutside: Double = 1
    ) {
        self.enabled = enabled
        self.height = height
        self.settingDistance = settingDistance
        self.settingAngle = settingAngle
        self.planar = planar
        self.blendAmount = blendAmount
        self.blendStartInside = blendStartInside
        self.blendEndInside = blendEndInside
        self.blendStartOutside = blendStartOutside
        self.blendEndOutside = blendEndOutside
    }

    public static let standard = ProngDomeParameters()
}

public struct ProngDome: Sendable {
    public var mesh: Mesh3D
    public var apex: Vec3
    public var baseCenter: Vec3
    /// Midpoint of the first meridian; this is where the blend construction is
    /// visible, so the golden test compares it as well as the apex.
    public var meridianMid: Vec3
    public var heightMM: Double
    public var tier: ProvenanceTier
}

/// A dome cap over the top section of a prong.
///
/// `ProngDomeCurve` blends each side of the split prong section to a common
/// apex with `CSUtilCurves.BlendCurve`. That helper is captured in corpus v2:
/// it is a six-point Bezier whose interior controls sit at 20 % and 40 % of
/// the chord along the supplied tangents. This builder uses the same six
/// controls for every meridian from the top section to the apex. The choice of
/// a radial start tangent is a modelling decision and is graded `inferred` in
/// the provenance claims; the blend curve and the apex rule are reconstructed.
public enum ProngDomeBuilder {
    /// Tessellation only; no vendor value depends on it.
    public static let samples = 8
    /// `CreateDomeRC` treats a dome smaller than this as flat.
    public static let flatThresholdMM = 0.005
    /// From `CSUtilCurves.BlendCurve`: interior controls at 20 % and 40 %.
    public static let blendNear = 0.2
    public static let blendFar = 0.4

    public static func cap(
        rail: [Vec3],
        prong: ProngPlacement,
        parameters: ProngDomeParameters
    ) -> ProngDome? {
        guard parameters.enabled, parameters.height >= flatThresholdMM, rail.count >= 2 else {
            return nil
        }
        let base = ProngSweeper.section(rail: rail, index: 0, prong: prong)
        guard base.count >= 3 else { return nil }
        let baseCenter = base.reduce(Vec3.zero, +) / Double(base.count)
        let tangent = (rail[1] - rail[0]).normalized()
        let axis = -tangent
        let tangential = axis.cross(Vec3(0, 0, 1)).normalized(fallback: Vec3(1, 0, 0))

        var apex = baseCenter + axis * parameters.height
        if parameters.settingDistance != 0 {
            apex = apex + tangential * parameters.settingDistance
        }
        if parameters.settingAngle != 0 {
            apex = baseCenter + rotated(
                apex - baseCenter,
                around: tangential,
                radians: parameters.settingAngle * .pi / 180
            )
        }

        let firstMeridian = meridian(
            from: base[0],
            center: baseCenter,
            to: apex,
            axis: axis
        )

        var rings: [[Vec3]] = [base]
        rings.reserveCapacity(samples)
        for step in 1..<samples {
            let u = Double(step) / Double(samples)
            rings.append(base.map { point in
                meridian(
                    from: point,
                    center: baseCenter,
                    to: apex,
                    axis: axis
                ).point(at: u)
            })
        }

        var mesh = Mesh3D()
        for ring in rings { mesh.vertices.append(contentsOf: ring) }
        let apexIndex = mesh.vertices.count
        mesh.vertices.append(apex)
        let stride = base.count
        for ringIndex in 0..<(rings.count - 1) {
            let lower = ringIndex * stride
            let upper = (ringIndex + 1) * stride
            for index in 0..<stride {
                let next = (index + 1) % stride
                mesh.triangles.append(MeshTriangle(lower + index, lower + next, upper + next))
                mesh.triangles.append(MeshTriangle(lower + index, upper + next, upper + index))
            }
        }
        let last = (rings.count - 1) * stride
        for index in 0..<stride {
            let next = (index + 1) % stride
            mesh.triangles.append(MeshTriangle(last + index, last + next, apexIndex))
        }

        return ProngDome(
            mesh: mesh,
            apex: apex,
            baseCenter: baseCenter,
            meridianMid: firstMeridian.point(at: 0.5),
            heightMM: parameters.height,
            tier: .reconstructed
        )
    }

    /// `CSUtilCurves.BlendCurve` with the default blend amounts.
    ///
    /// The vendor builds `[start, start + d0·L·0.2, start + d0·L·0.4,
    /// end + d1·L·0.4, end + d1·L·0.2, end]` and feeds the six points to
    /// `BezierCurve`. The returned sampler evaluates that Bezier.
    static func meridian(
        from start: Vec3,
        center: Vec3,
        to end: Vec3,
        axis: Vec3
    ) -> BezierSampler {
        let outward = (start - center).normalized(fallback: axis)
        let length = (end - start).length
        let controls = [
            start,
            start + outward * (length * blendNear),
            start + outward * (length * blendFar),
            end + (-axis) * (length * blendFar),
            end + (-axis) * (length * blendNear),
            end
        ]
        return BezierSampler(controls: controls)
    }

    static func rotated(_ value: Vec3, around axis: Vec3, radians: Double) -> Vec3 {
        let unit = axis.normalized()
        let cosine = cos(radians)
        let sine = sin(radians)
        return value * cosine
            + unit.cross(value) * sine
            + unit * (unit.dot(value) * (1 - cosine))
    }
}

/// De Casteljau evaluation of a Bezier curve of any degree.
struct BezierSampler {
    var controls: [Vec3]

    func point(at t: Double) -> Vec3 {
        guard controls.count > 1 else { return controls.first ?? .zero }
        let clamped = min(max(t, 0), 1)
        var points = controls
        for level in stride(from: points.count - 1, through: 1, by: -1) {
            for index in 0..<level {
                points[index] = points[index].lerp(points[index + 1], clamped)
            }
        }
        return points[0]
    }
}
