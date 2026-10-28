import Foundation

// Minimal geometry kernel for the recovered head builder. It is deliberately
// independent of any renderer: the builder emits meshes, the app draws them.

public extension Vec3 {
    static func + (lhs: Vec3, rhs: Vec3) -> Vec3 {
        Vec3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
    }

    static func - (lhs: Vec3, rhs: Vec3) -> Vec3 {
        Vec3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
    }

    static prefix func - (value: Vec3) -> Vec3 {
        Vec3(-value.x, -value.y, -value.z)
    }

    static func * (lhs: Vec3, rhs: Double) -> Vec3 {
        Vec3(lhs.x * rhs, lhs.y * rhs, lhs.z * rhs)
    }

    static func / (lhs: Vec3, rhs: Double) -> Vec3 {
        Vec3(lhs.x / rhs, lhs.y / rhs, lhs.z / rhs)
    }

    var length: Double {
        (x * x + y * y + z * z).squareRoot()
    }

    func dot(_ other: Vec3) -> Double {
        x * other.x + y * other.y + z * other.z
    }

    func cross(_ other: Vec3) -> Vec3 {
        Vec3(
            y * other.z - z * other.y,
            z * other.x - x * other.z,
            x * other.y - y * other.x
        )
    }

    func normalized(fallback: Vec3 = Vec3(0, 0, 1)) -> Vec3 {
        let length = self.length
        return length > 1e-12 ? self / length : fallback
    }

    func lerp(_ other: Vec3, _ t: Double) -> Vec3 {
        self + (other - self) * t
    }

    static func * (lhs: Vec3, rhs: Vec3) -> Vec3 {
        Vec3(lhs.x * rhs.x, lhs.y * rhs.y, lhs.z * rhs.z)
    }
}

/// Natural cubic spline through points with chord-length knots.
///
/// The vendor calls `Curve.CreateInterpolatedCurve(points, 3, Chord)`. The
/// interpolation degree and knot style are recovered; the solver below is a
/// standards-based natural spline, so this is a reconstruction of that call,
/// not a byte-identical Rhino surface.
public struct CubicSpline3D: Sendable {
    private let points: [Vec3]
    private let knots: [Double]
    private let second: [Vec3]

    public init(points: [Vec3]) {
        self.points = points
        guard points.count > 2 else {
            self.knots = points.isEmpty ? [] : [0, 1]
            self.second = Array(repeating: .zero, count: points.count)
            return
        }

        var knots = [0.0]
        for index in 1..<points.count {
            let distance = (points[index] - points[index - 1]).length
            knots.append(knots.last! + max(distance, 1e-9))
        }
        let total = knots.last!
        self.knots = knots.map { $0 / total }

        var interior = Array(repeating: Vec3.zero, count: points.count)
        let count = points.count
        var lower = Array(repeating: 0.0, count: count)
        var diagonal = Array(repeating: 1.0, count: count)
        var upper = Array(repeating: 0.0, count: count)
        var rhs = Array(repeating: Vec3.zero, count: count)

        for index in 1..<(count - 1) {
            let h0 = self.knots[index] - self.knots[index - 1]
            let h1 = self.knots[index + 1] - self.knots[index]
            lower[index] = h0
            diagonal[index] = 2 * (h0 + h1)
            upper[index] = h1
            let slope0 = (points[index] - points[index - 1]) / h0
            let slope1 = (points[index + 1] - points[index]) / h1
            rhs[index] = (slope1 - slope0) * 6
        }

        // Thomas algorithm, one pass per component.
        func solve(_ values: [Double]) -> [Double] {
            var c = Array(repeating: 0.0, count: count)
            var d = Array(repeating: 0.0, count: count)
            var result = Array(repeating: 0.0, count: count)
            c[1] = upper[1] / diagonal[1]
            d[1] = values[1] / diagonal[1]
            if count > 3 {
                for index in 2..<(count - 1) {
                    let denominator = diagonal[index] - lower[index] * c[index - 1]
                    c[index] = upper[index] / denominator
                    d[index] = (values[index] - lower[index] * d[index - 1]) / denominator
                }
            }
            result[count - 2] = d[count - 2]
            if count > 3 {
                for index in stride(from: count - 3, through: 1, by: -1) {
                    result[index] = d[index] - c[index] * result[index + 1]
                }
            }
            return result
        }

        let mx = solve(rhs.map(\.x))
        let my = solve(rhs.map(\.y))
        let mz = solve(rhs.map(\.z))
        for index in 0..<count {
            interior[index] = Vec3(mx[index], my[index], mz[index])
        }
        self.second = interior
    }

    public func point(at parameter: Double) -> Vec3 {
        guard points.count > 1 else { return points.first ?? .zero }
        if points.count == 2 {
            return points[0].lerp(points[1], min(max(parameter, 0), 1))
        }
        let u = min(max(parameter, 0), 1)
        var segment = 0
        while segment < points.count - 2 && u > knots[segment + 1] {
            segment += 1
        }
        let t0 = knots[segment]
        let t1 = knots[segment + 1]
        let h = t1 - t0
        let a = (t1 - u) / h
        let b = (u - t0) / h
        let correction = (second[segment] * (a * a * a - a) + second[segment + 1] * (b * b * b - b)) * (h * h / 6)
        return points[segment] * a + points[segment + 1] * b + correction
    }

    public func points(count: Int) -> [Vec3] {
        guard count > 1 else { return [] }
        return (0..<count).map { point(at: Double($0) / Double(count - 1)) }
    }
}

public struct MeshTriangle: Hashable, Sendable {
    public var a: Int
    public var b: Int
    public var c: Int

    public init(_ a: Int, _ b: Int, _ c: Int) {
        self.a = a
        self.b = b
        self.c = c
    }
}

public struct Mesh3D: Sendable {
    public var vertices: [Vec3]
    public var triangles: [MeshTriangle]

    public init(vertices: [Vec3] = [], triangles: [MeshTriangle] = []) {
        self.vertices = vertices
        self.triangles = triangles
    }

    public var isEmpty: Bool { triangles.isEmpty }

    public var bounds: (min: Vec3, max: Vec3)? {
        guard let first = vertices.first else { return nil }
        var low = first
        var high = first
        for vertex in vertices.dropFirst() {
            low = Vec3(min(low.x, vertex.x), min(low.y, vertex.y), min(low.z, vertex.z))
            high = Vec3(max(high.x, vertex.x), max(high.y, vertex.y), max(high.z, vertex.z))
        }
        return (low, high)
    }

    public mutating func append(_ other: Mesh3D) {
        let offset = vertices.count
        vertices.append(contentsOf: other.vertices)
        triangles.append(contentsOf: other.triangles.map {
            MeshTriangle($0.a + offset, $0.b + offset, $0.c + offset)
        })
    }

    /// Connects equally sized rings into a quad mesh, optionally closing the
    /// ring and capping the ends. Winding follows the ring order.
    public static func loft(rings: [[Vec3]], closedRing: Bool = true, capStart: Bool = false, capEnd: Bool = false) -> Mesh3D {
        guard let first = rings.first, first.count >= 3, rings.count >= 2 else { return Mesh3D() }
        var mesh = Mesh3D()
        for ring in rings {
            mesh.vertices.append(contentsOf: ring)
        }
        let stride = first.count
        let segments = closedRing ? stride : stride - 1
        for ringIndex in 0..<(rings.count - 1) {
            let base0 = ringIndex * stride
            let base1 = (ringIndex + 1) * stride
            for segment in 0..<segments {
                let next = (segment + 1) % stride
                let a = base0 + segment
                let b = base0 + next
                let c = base1 + next
                let d = base1 + segment
                mesh.triangles.append(MeshTriangle(a, b, c))
                mesh.triangles.append(MeshTriangle(a, c, d))
            }
        }
        if capStart {
            mesh.cap(ring: rings[0], offset: 0, flip: true)
        }
        if capEnd {
            let offset = (rings.count - 1) * stride
            mesh.cap(ring: rings[rings.count - 1], offset: offset, flip: false)
        }
        return mesh
    }

    private mutating func cap(ring: [Vec3], offset: Int, flip: Bool) {
        let center = ring.reduce(Vec3.zero, +) / Double(ring.count)
        let centerIndex = vertices.count
        vertices.append(center)
        for index in 0..<ring.count {
            let next = (index + 1) % ring.count
            if flip {
                triangles.append(MeshTriangle(centerIndex, offset + next, offset + index))
            } else {
                triangles.append(MeshTriangle(centerIndex, offset + index, offset + next))
            }
        }
    }
}
