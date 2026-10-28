import Foundation

/// Evidence grade for a numeric fact or a geometry behaviour.
///
/// `recovered` facts are IL literals at a named method and offset.
/// `reconstructed` behaviours follow a documented algorithm when the vendor's
/// helper was not captured; they cite that algorithm.
/// `inferred` behaviours are explicit substitutes and must give a rationale.
public enum ProvenanceTier: String, Codable, CaseIterable, Hashable, Sendable {
    case recovered
    case reconstructed
    case inferred
}

public struct ProvenanceEntry: Codable, Hashable, Sendable {
    public var name: String
    public var value: Double
    public var method: String
    public var ilOffset: Int
    public var use: String
    public var tier: ProvenanceTier

    enum CodingKeys: String, CodingKey {
        case name, value, method
        case ilOffset = "il_offset"
        case use, tier
    }
}

public struct ProvenanceClaim: Codable, Hashable, Sendable {
    public var id: String
    public var tier: ProvenanceTier
    public var statement: String
    public var evidence: String
    public var method: String?
    public var ilOffset: Int?
    public var documentedAlgorithm: String?
    public var rationale: String?

    enum CodingKeys: String, CodingKey {
        case id, tier, statement, evidence, method, rationale
        case ilOffset = "il_offset"
        case documentedAlgorithm = "documented_algorithm"
    }
}

public enum HeadProvenance {
    public static let all: [ProvenanceEntry] = payload?.constants ?? []
    public static let claims: [ProvenanceClaim] = payload?.claims ?? []

    public static func claims(for tier: ProvenanceTier) -> [ProvenanceClaim] {
        claims.filter { $0.tier == tier }
    }

    private static let payload: Payload? = {
        guard
            let url = Bundle.module.url(forResource: "head-geometry-provenance", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else {
            return nil
        }
        return payload
    }()

    private struct Payload: Codable {
        var constants: [ProvenanceEntry]
        var claims: [ProvenanceClaim]
    }
}

/// The renderable result: a lathed head cage and one swept solid per prong.
public struct HeadAssembly: Sendable {
    public var parameters: HeadShapeParameters
    public var cage: HeadCage
    public var basket: Mesh3D
    public var prongs: [Mesh3D]
    public var domes: [ProngDome]
    public var rails: [GalleryRail]
    public var bezel: Bezel?
    public var halo: Halo?
    public var combined: Mesh3D
    public var provenance: [ProvenanceEntry]
    /// Evidence grade of each rendered family. The test suite requires every
    /// non-empty part here and rejects an empty or unknown grade.
    public var partTiers: [String: ProvenanceTier]

    public var triangleCount: Int { combined.triangles.count }
    public var vertexCount: Int { combined.vertices.count }

    public init(
        parameters: HeadShapeParameters,
        railParameters: [RailParameters] = [],
        domeParameters: ProngDomeParameters? = nil,
        bezelParameters: BezelParameters? = nil,
        haloParameters: HaloParameters? = nil
    ) throws {
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
        // The basket is open at the girdle and at the base: the gem sits in it
        // and the shank joins below. Capping would hide the seat.
        self.basket = Mesh3D.loft(rings: rings, closedRing: true, capStart: false, capEnd: false)

        self.prongs = zip(cage.prongRails, parameters.prongs).map { rail, prong in
            ProngSweeper.solid(rail: rail, prong: prong)
        }

        self.domes = zip(cage.prongRails, parameters.prongs).compactMap { rail, prong in
            guard let domeParameters else { return nil }
            return ProngDomeBuilder.cap(rail: rail, prong: prong, parameters: domeParameters)
        }
        self.rails = try railParameters
            .filter(\.enabled)
            .map { try GalleryRailBuilder.build(cage: cage, parameters: parameters, rail: $0) }
        let builtBezel = bezelParameters.flatMap {
            BezelBuilder.build(cage: cage, bezel: $0)
        }
        self.bezel = builtBezel
        let builtHalo = haloParameters.flatMap {
            HaloBuilder.build(parameters: parameters, halo: $0)
        }
        self.halo = builtHalo

        var combined = basket
        for prong in prongs { combined.append(prong) }
        for dome in domes { combined.append(dome.mesh) }
        for rail in rails { combined.append(rail.mesh) }
        if let builtBezel { combined.append(builtBezel.mesh) }
        if let builtHalo { combined.append(builtHalo.mesh) }
        self.combined = combined
        self.provenance = HeadProvenance.all
        var tiers: [String: ProvenanceTier] = [
            "basket": .recovered,
            "prongs": .inferred
        ]
        if !domes.isEmpty { tiers["domes"] = .reconstructed }
        if !rails.isEmpty { tiers["gallery"] = .inferred }
        if let builtBezel { tiers["bezel"] = builtBezel.tier }
        if let builtHalo {
            tiers["haloSeats"] = .recovered
            tiers["haloBand"] = builtHalo.bandTier
            tiers["haloGems"] = builtHalo.gemTier
        }
        self.partTiers = tiers
    }

    public static var solitaire: HeadAssembly {
        // The fixture is validated in tests; a failure here is a programmer error.
        try! HeadAssembly(parameters: .solitaire)
    }

}
