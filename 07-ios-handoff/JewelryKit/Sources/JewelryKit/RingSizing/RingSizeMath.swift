import Foundation

/// Closed-form ring-size math recovered from MatrixGold's `RingSizeRegionTranslator*` classes.
///
/// The original uses `Math.Round(value, digits)`, i.e. mid-point-to-even. All helpers here
/// reproduce that behaviour so generated values match the shipped tables exactly.
public enum RingSizeMath {
    public static func count(for region: RingSizeRegion) -> Int? {
        switch region {
        case .us: return 65
        case .uk: return 66
        case .eu: return 39
        case .jp: return 37
        case .fr: return 160
        case .de: return 38
        case .ch: return 160
        default: return nil
        }
    }

    public static func diameterMM(region: RingSizeRegion, index: Int) -> Double? {
        guard let count = count(for: region), (0..<count).contains(index) else { return nil }
        guard let raw = rawDiameterMM(region: region, index: index) else { return nil }
        return roundToEven(raw, digits: 2)
    }

    public static func radiusMM(region: RingSizeRegion, index: Int) -> Double? {
        guard let raw = rawDiameterMM(region: region, index: index) else { return nil }
        return roundToEven(raw / 2.0, digits: 2)
    }

    public static func name(region: RingSizeRegion, index: Int) -> String? {
        guard let count = count(for: region), (0..<count).contains(index) else { return nil }
        switch region {
        case .us:
            return "\(index / 4)" + fraction(index % 4)
        case .uk:
            var value: String
            if index >= 52 {
                value = "Z+\((index - 50) / 2)"
            } else {
                guard let scalar = UnicodeScalar(65 + index / 2) else { return nil }
                value = String(Character(scalar))
            }
            if index % 2 == 1 { value += " 1/2" }
            return value
        case .eu:
            return "\(index + 41)"
        case .jp:
            return "\(index)"
        case .fr:
            return "\(index / 4 + 41)" + fraction(index % 4)
        case .de:
            let n = index + 53
            return "\(n / 4)" + fraction(n % 4)
        case .ch:
            return "\(index / 4 + 1)" + fraction(index % 4)
        default:
            return nil
        }
    }

    public static func index(region: RingSizeRegion, diameterMM: Double) -> Int? {
        guard let count = count(for: region) else { return nil }
        let raw: Double
        switch region {
        case .us:
            raw = (diameterMM * 0.0393700787 * .pi - 1.43) / 0.102 * 4.0
        case .uk:
            raw = (diameterMM * .pi - 37.55) / 1.25 * 2.0
        case .eu:
            raw = diameterMM * .pi - 41.0
        case .jp:
            raw = 3.0 * diameterMM - 38.0
        case .fr, .ch:
            raw = (diameterMM * .pi - 41.0) * 4.0
        case .de:
            raw = diameterMM * 4.0 - 53.0
        default:
            return nil
        }
        let rounded = Int(roundToEven(raw, digits: 0))
        return min(max(rounded, 0), count - 1)
    }

    /// Convenience that composes the formula with clamping, mirroring `GetRingSizeFromIndex`.
    public static func size(region: RingSizeRegion, index: Int) -> RingSize? {
        guard
            let count = count(for: region),
            let diameter = diameterMM(region: region, index: index),
            let radius = radiusMM(region: region, index: index),
            let name = name(region: region, index: index)
        else { return nil }
        let clamped = min(max(index, 0), count - 1)
        return RingSize(region: region, name: name, diameterMM: diameter, radiusMM: radius, index: clamped)
    }

    private static func rawDiameterMM(region: RingSizeRegion, index: Int) -> Double? {
        switch region {
        case .us:
            return ((Double(index) / 4.0 * 0.102 + 1.43) / .pi) * 25.4
        case .uk:
            return ((Double(index) / 2.0 * 1.25 + 37.55) / .pi)
        case .eu:
            return Double(index + 41) / .pi
        case .jp:
            return (Double(index) + 38.0) / 3.0
        case .fr, .ch:
            return (Double(index) / 4.0 + 41.0) / .pi
        case .de:
            return Double(index + 53) / 4.0
        default:
            return nil
        }
    }

    private static func fraction(_ remainder: Int) -> String {
        switch remainder {
        case 1: return " 1/4"
        case 2: return " 1/2"
        case 3: return " 3/4"
        default: return ""
        }
    }

    /// `Math.Round(value, digits)` equivalent: mid-point-to-even, not away-from-zero.
    private static func roundToEven(_ value: Double, digits: Int) -> Double {
        let factor = pow(10.0, Double(digits))
        let scaled = value * factor
        let lower = scaled.rounded(.down)
        let fraction = scaled - lower
        let nearest: Double
        if abs(abs(fraction) - 0.5) < 1e-7 {
            nearest = lower.truncatingRemainder(dividingBy: 2) == 0 ? lower : lower + 1
        } else {
            nearest = scaled.rounded()
        }
        return nearest / factor
    }
}
