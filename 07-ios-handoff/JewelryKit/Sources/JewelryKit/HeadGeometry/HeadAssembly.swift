import Foundation

public struct ProvenanceEntry: Codable, Hashable, Sendable {
    public var name: String
    public var value: Double
    public var method: String
    public var ilOffset: Int
    public var use: String

    enum CodingKeys: String, CodingKey {
        case name, value, method
        case ilOffset = "il_offset"
        case use
    }
}

public enum HeadProvenance {
    public static let all: [ProvenanceEntry] = {
        guard
            let url = Bundle.module.url(forResource: "head-geometry-provenance", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else {
            return []
        }
        return payload.constants
    }()

    private struct Payload: Codable {
        var constants: [ProvenanceEntry]
    }
}

/// The renderable result: a lathed head cage and one swept solid per prong.
public struct HeadAssembly: Sendable {
    public var parameters: HeadShapeParameters
    public var cage: HeadCage
    public var basket: Mesh3D
    public var prongs: [Mesh3D]
    public var combined: Mesh3D
    public var provenance: [ProvenanceEntry]

    public var triangleCount: Int { combined.triangles.count }
    public var vertexCount: Int { combined.vertices.count }

    public init(parameters: HeadShapeParameters) throws {
        self.parameters = parameters
        let cage = try HeadShapeBuilder.build(parameters)
        self.cage = cage

        // Order the four recovered outlines bottom-to-top so the loft normals
        // face outward whichever sign headHeight carries.
        func meanZ(_ ring: [Vec3]) -> Double {
            ring.reduce(0) { $0 + $1.z } / Double(max(ring.count, 1))
        }
        let rings = [cage.base, cage.middle, cage.girdle, cage.top]
            .sorted { meanZ($0) < meanZ($1) }
        self.basket = Mesh3D.loft(rings: rings, closedRing: true, capStart: true, capEnd: true)

        self.prongs = zip(cage.prongRails, parameters.prongs).map { rail, prong in
            ProngSweeper.solid(rail: rail, prong: prong)
        }

        var combined = basket
        for prong in prongs { combined.append(prong) }
        self.combined = combined
        self.provenance = HeadProvenance.all
    }

    public static var solitaire: HeadAssembly {
        // The fixture is validated in tests; a failure here is a programmer error.
        try! HeadAssembly(parameters: .solitaire)
    }

}
