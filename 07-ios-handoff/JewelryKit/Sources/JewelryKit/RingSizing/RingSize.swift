import Foundation

public struct RingSize: Codable, Hashable, Sendable {
    public let region: RingSizeRegion
    public let name: String
    public let diameterMM: Double
    public let radiusMM: Double
    public let index: Int

    public init(region: RingSizeRegion, name: String, diameterMM: Double, radiusMM: Double, index: Int) {
        self.region = region
        self.name = name
        self.diameterMM = diameterMM
        self.radiusMM = radiusMM
        self.index = index
    }

    public var circumferenceMM: Double { diameterMM * .pi }

    /// MatrixGold's `ToString()` shape: `ABRV:Name:Diameter`.
    public var displayString: String {
        "\(region.abbreviation):\(name):\(diameterMM)"
    }
}

public struct RingSizeTable: Sendable {
    public let region: RingSizeRegion
    public let abbreviation: String
    public let kind: RingSizeRegion.Kind
    public let sizes: [RingSize]

    public var count: Int { sizes.count }

    public func size(at index: Int) -> RingSize? {
        guard sizes.indices.contains(index) else { return nil }
        return sizes[index]
    }

    /// Exact, case-insensitive name lookup. Fractional spellings are normalized.
    public func size(named rawName: String) -> RingSize? {
        let wanted = RingSizeCatalog.normalizeName(rawName)
        return sizes.first { RingSizeCatalog.normalizeName($0.name) == wanted }
    }

    /// Nearest size by diameter; ties resolve to the lower index, matching the original scan.
    public func nearest(diameterMM: Double) -> RingSize? {
        guard !sizes.isEmpty else { return nil }
        let clamped = min(max(diameterMM, sizes[0].diameterMM), sizes[sizes.count - 1].diameterMM)
        var best = sizes[0]
        var bestDelta = abs(best.diameterMM - clamped)
        for size in sizes.dropFirst() {
            let delta = abs(size.diameterMM - clamped)
            if delta < bestDelta {
                best = size
                bestDelta = delta
            }
        }
        return best
    }
}

public struct RingSizeCatalog: Sendable {
    private let tables: [RingSizeRegion: RingSizeTable]

    public init(data: Data) throws {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        var built: [RingSizeRegion: RingSizeTable] = [:]
        for region in payload.regions {
            let sizes = region.sizes.map {
                RingSize(
                    region: region.region,
                    name: $0.name,
                    diameterMM: $0.diameterMM,
                    radiusMM: $0.radiusMM,
                    index: $0.index
                )
            }
            built[region.region] = RingSizeTable(
                region: region.region,
                abbreviation: region.abbreviation,
                kind: region.kind,
                sizes: sizes
            )
        }
        self.tables = built
    }

    /// Loads the bundled `ring-sizes.json` generated from the real assembly.
    public static let bundled: RingSizeCatalog = {
        guard
            let url = Bundle.module.url(forResource: "ring-sizes", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let catalog = try? RingSizeCatalog(data: data)
        else {
            preconditionFailure("RingSizing: bundled ring-sizes.json is missing or malformed")
        }
        return catalog
    }()

    public var regions: [RingSizeRegion] {
        RingSizeRegion.allCases.filter { tables[$0] != nil }
    }

    public var totalSizeCount: Int {
        tables.values.reduce(0) { $0 + $1.count }
    }

    public func table(for region: RingSizeRegion) -> RingSizeTable? {
        tables[region]
    }

    public func sizes(for region: RingSizeRegion) -> [RingSize] {
        tables[region]?.sizes ?? []
    }

    public func size(region: RingSizeRegion, index: Int) -> RingSize? {
        tables[region]?.size(at: index)
    }

    public func size(region: RingSizeRegion, name: String) -> RingSize? {
        tables[region]?.size(named: name)
    }

    public func nearest(region: RingSizeRegion, diameterMM: Double) -> RingSize? {
        tables[region]?.nearest(diameterMM: diameterMM)
    }

    /// Normalizes `7 1/2`, `7.5`, `7  1/2` and case differences for lookup.
    public static func normalizeName(_ name: String) -> String {
        var value = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        value = value.replacingOccurrences(of: "  1/2", with: " 1/2")
        if value.hasSuffix(".5") {
            value = String(value.dropLast(2)) + " 1/2"
        } else if value.hasSuffix(".25") {
            value = String(value.dropLast(3)) + " 1/4"
        } else if value.hasSuffix(".75") {
            value = String(value.dropLast(3)) + " 3/4"
        }
        return value
    }

    private struct Payload: Codable {
        let regions: [RegionDTO]
    }

    private struct RegionDTO: Codable {
        let region: RingSizeRegion
        let abbreviation: String
        let kind: RingSizeRegion.Kind
        let sizes: [SizeDTO]
    }

    private struct SizeDTO: Codable {
        let name: String
        let diameterMM: Double
        let radiusMM: Double
        let index: Int
    }
}
