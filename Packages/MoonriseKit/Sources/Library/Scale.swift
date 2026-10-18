import Foundation

/// Something with a size, for the scale view: a body, star, nebula, galaxy or orbit.
public struct ScaleObject: Sendable, Identifiable, Hashable {
    public var name: String
    /// Diameter, or end-to-end length, in metres.
    public var meters: Double
    /// Library page to open, if there is one.
    public var page: String?
    public var id: String { name }
}

extension Library {
    static let lightYear = 9.4607e15
    static let au = 1.495978707e11

    /// Everything in the scale view, smallest first. Sizes come from the Library pages where they give one.
    public static let scaleObjects: [ScaleObject] = {
        var out: [ScaleObject] = [ScaleObject(name: "ISS", meters: 109, page: "international-space-station")]

        // Sun, planets, dwarf planets and moons: the drawing's mean radius.
        for section in [LibrarySection.sun, .planets, .dwarfPlanets, .moons] {
            for p in pages(in: section) {
                if let r = p.drawing?.radiusKm { out.append(ScaleObject(name: p.title, meters: 2 * r * 1000, page: p.id)) }
            }
        }

        // Stars whose page gives a radius as "N × Sun".
        for p in pages(in: .stars) {
            guard let fact = p.facts.first(where: { $0.label == "Radius" }), let r = solarRadii(fact.value) else { continue }
            out.append(ScaleObject(name: p.title, meters: 2 * r * 6.957e8, page: p.id))
        }

        // Deep-sky objects: the page's distance times its apparent size (major axis).
        let deepSky: [(String, Double, Double)] = [ // id, light-years, arcminutes
            ("m57", 2_000, 1.4), ("m1", 6_500, 6), ("m45", 445, 110), ("m42", 1_500, 85),
            ("m13", 25_000, 20), ("m33", 3_000_000, 73), ("m87", 54_000_000, 7), ("m31", 2_500_000, 178),
        ]
        for (id, ly, arcmin) in deepSky {
            guard let p = page(id: id) else { continue }
            out.append(ScaleObject(name: p.title, meters: ly * lightYear * arcmin / 60 * .pi / 180, page: id))
        }

        out += [
            ScaleObject(name: "Moon's orbit", meters: 2 * 384_400e3),
            ScaleObject(name: "Earth's orbit", meters: 2 * au),
            ScaleObject(name: "Neptune's orbit", meters: 2 * 30.07 * au),
            // Voyager 1 crossed the heliopause at about 121 AU.
            ScaleObject(name: "Heliosphere", meters: 2 * 121 * au),
            ScaleObject(name: "Milky Way", meters: 100_000 * lightYear),
            ScaleObject(name: "Local Group", meters: 10e6 * lightYear),
            // Tully et al. 2014.
            ScaleObject(name: "Laniakea Supercluster", meters: 520e6 * lightYear),
            ScaleObject(name: "Observable universe", meters: 93e9 * lightYear),
        ]
        return out.sorted { $0.meters < $1.meters }
    }()

    /// 25.4 from "25.4 ± 0.2 × Sun".
    static func solarRadii(_ s: String) -> Double? {
        guard s.contains("× Sun"), let first = s.split(separator: " ").first else { return nil }
        return Double(first.replacingOccurrences(of: ",", with: ""))
    }

    /// "109 m", "12,742 km", "60.1 AU", "11 light-years", "2.5 million light-years".
    public static func formatSize(_ meters: Double) -> String {
        func n(_ v: Double) -> String { v.formatted(.number.precision(.significantDigits(1...(v < 10 ? 2 : 3)))) }
        switch meters {
        case ..<1_000: return "\(Int(meters.rounded())) m"
        case ..<1e10: return "\(Int((meters / 1000).rounded()).formatted()) km"
        case ..<(0.1 * lightYear): return "\(n(meters / au)) AU"
        case ..<(1e6 * lightYear): return "\(n(meters / lightYear)) light-years"
        case ..<(1e9 * lightYear): return "\(n(meters / lightYear / 1e6)) million light-years"
        default: return "\(n(meters / lightYear / 1e9)) billion light-years"
        }
    }
}
