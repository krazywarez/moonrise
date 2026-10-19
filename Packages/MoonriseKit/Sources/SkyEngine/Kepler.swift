import CAstronomy
import Foundation

/// A two-body orbit around the Sun from osculating elements (J2000 ecliptic), for small bodies the
/// engine doesn't cover. Planetary perturbations are ignored, so positions drift away from the epoch:
/// fine for drawing, not for observing.
public struct KeplerOrbit: Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Library page, if there is one.
    public var page: String?
    public var a: Double, e: Double, i: Double, node: Double, peri: Double
    /// Time of perihelion (TDB Julian date). Propagating from it rather than from the epoch's mean
    /// anomaly keeps comets right near perihelion, where they are worth drawing.
    public var perihelionJD: Double
    public var isComet: Bool

    /// Orbital period in days.
    public var periodDays: Double { 365.256898 * pow(a, 1.5) }

    /// Heliocentric position in AU on J2000 ecliptic axes.
    public func position(at date: Date) -> SIMD3<Double> {
        let jd = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let n = 360 / periodDays
        let M = ((n * (jd - perihelionJD)).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) * .pi / 180
        var E = e < 0.8 ? M : .pi
        for _ in 0..<50 {
            let d = (E - e * sin(E) - M) / (1 - e * cos(E))
            E -= d
            if abs(d) < 1e-12 { break }
        }
        let x = a * (cos(E) - e), y = a * (1 - e * e).squareRoot() * sin(E)
        let r = Double.pi / 180
        let (cO, sO) = (cos(node * r), sin(node * r)), (cw, sw) = (cos(peri * r), sin(peri * r)), (ci, si) = (cos(i * r), sin(i * r))
        return SIMD3(
            (cO * cw - sO * sw * ci) * x + (-cO * sw - sO * cw * ci) * y,
            (sO * cw + cO * sw * ci) * x + (-sO * sw + cO * cw * ci) * y,
            (sw * si) * x + (cw * si) * y
        )
    }

    /// One full orbit, sampled evenly in eccentric anomaly so long, thin comet orbits stay smooth near the Sun.
    public func orbitPath(steps: Int = 240) -> [SIMD3<Double>] {
        let r = Double.pi / 180
        let (cO, sO) = (cos(node * r), sin(node * r)), (cw, sw) = (cos(peri * r), sin(peri * r)), (ci, si) = (cos(i * r), sin(i * r))
        return (0..<steps).map { k in
            let E = Double(k) / Double(steps) * 2 * .pi
            let x = a * (cos(E) - e), y = a * (1 - e * e).squareRoot() * sin(E)
            return SIMD3(
                (cO * cw - sO * sw * ci) * x + (-cO * sw - sO * cw * ci) * y,
                (sO * cw + cO * sw * ci) * x + (-sO * sw + cO * cw * ci) * y,
                (sw * si) * x + (cw * si) * y
            )
        }
    }

    /// The next perihelion after `date`.
    public func nextPerihelion(after date: Date) -> Date {
        let jd = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let k = ((jd - perihelionJD) / periodDays).rounded(.up)
        return Date(timeIntervalSince1970: (perihelionJD + k * periodDays - 2_440_587.5) * 86_400)
    }

    /// JPL Small-Body Database osculating elements (full precision), fetched 2026-10-19.
    public static let dwarfPlanets: [KeplerOrbit] = [
        KeplerOrbit(id: "ceres", name: "Ceres", page: "ceres", a: 2.765552595034094, e: 0.07969229514816586, i: 10.58802780183462, node: 80.24862682043221, peri: 73.29421453021587, perihelionJD: 2461599.841466614, isComet: false),
        KeplerOrbit(id: "haumea", name: "Haumea", page: "haumea", a: 43.06029023650952, e: 0.1944430148898797, i: 28.20847393040364, node: 121.7860561329425, peri: 240.6905472508661, perihelionJD: 2500416.599615283, isComet: false),
        KeplerOrbit(id: "makemake", name: "Makemake", page: "makemake", a: 45.57093317300052, e: 0.1588889953992523, i: 29.02785603743067, node: 79.2948338209406, peri: 297.0922733397207, perihelionJD: 2408158.6940986165, isComet: false),
        KeplerOrbit(id: "eris", name: "Eris", page: "eris", a: 67.93394687853566, e: 0.4382385347971672, i: 43.9258279471791, node: 36.00477044417249, peri: 150.7949235840312, perihelionJD: 2545407.716847013, isComet: false),
    ]

    public static let comets: [KeplerOrbit] = [
        KeplerOrbit(id: "halley", name: "Halley's Comet", page: nil, a: 17.92863504856923, e: 0.9679359956953211, i: 162.1905300439129, node: 59.09894720612437, peri: 112.2414314637764, perihelionJD: 2446469.9736161465, isComet: true),
        KeplerOrbit(id: "encke", name: "Comet Encke", page: nil, a: 2.218624763741819, e: 0.846940430888432, i: 11.33675914978793, node: 334.0171400057891, peri: 187.2881998732444, perihelionJD: 2460240.0285326503, isComet: true),
        KeplerOrbit(id: "67p", name: "67P/Churyumov–Gerasimenko", page: "rosetta", a: 3.462249490129549, e: 0.6409081308996354, i: 7.040294937543767, node: 50.13557377155012, peri: 12.79824970228189, perihelionJD: 2457247.588657812, isComet: true),
        KeplerOrbit(id: "swift-tuttle", name: "Comet Swift–Tuttle", page: nil, a: 26.0920694978266, e: 0.963225755046038, i: 113.453816997171, node: 139.3811920815948, peri: 152.9821676305871, perihelionJD: 2448968.499784556, isComet: true),
        KeplerOrbit(id: "tempel-tuttle", name: "Comet Tempel–Tuttle", page: nil, a: 10.3383382297577, e: 0.905552720972412, i: 162.486575379434, node: 235.270989149082, peri: 172.5002736828059, perihelionJD: 2450872.5977341123, isComet: true),
        KeplerOrbit(id: "phaethon", name: "3200 Phaethon", page: nil, a: 1.271464620762422, e: 0.8896722844001859, i: 22.31052728977475, node: 265.0988060326684, peri: 322.3001684954223, perihelionJD: 2461285.6164380596, isComet: true),
        KeplerOrbit(id: "tuttle", name: "Comet 8P/Tuttle", page: nil, a: 5.700291361749948, e: 0.8197876162331501, i: 54.98196882510133, node: 270.3421615706648, peri: 207.5115175085094, perihelionJD: 2454492.5180154694, isComet: true),
    ]
}

extension MeteorShower {
    /// The comet (or asteroid) whose debris Earth passes through, by KeplerOrbit id.
    public var parent: String? {
        switch name {
        case "Perseids": "swift-tuttle"
        case "Leonids": "tempel-tuttle"
        case "Orionids", "Eta Aquariids": "halley"
        case "Geminids": "phaethon"
        case "Ursids": "tuttle"
        default: nil
        }
    }

    /// Days from `date` to the nearest peak (negative once it has passed), in the given calendar.
    public func daysToPeak(from date: Date, calendar: Calendar = .current) -> Double {
        let year = calendar.component(.year, from: date)
        return (year - 1...year + 1).compactMap { y in
            calendar.date(from: DateComponents(year: y, month: month, day: day, hour: 12)).map { $0.timeIntervalSince(date) / 86_400 }
        }
        .min { abs($0) < abs($1) } ?? .infinity
    }
}

extension SkyEngine {
    /// Io, Europa, Ganymede and Callisto relative to Jupiter, AU on J2000 ecliptic axes.
    public static func galileanMoons(at date: Date) -> [SIMD3<Double>] {
        lock.lock()
        defer { lock.unlock() }
        let m = Astronomy_JupiterMoons(time(date))
        return [m.io, m.europa, m.ganymede, m.callisto].map { ecliptic(SIMD3($0.x, $0.y, $0.z)) }
    }
}
