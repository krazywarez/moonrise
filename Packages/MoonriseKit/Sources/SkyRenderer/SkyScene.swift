import Foundation
import SkyEngine

public struct Star: Sendable {
    public var hr: Int
    public var ra: Double
    public var dec: Double
    public var magnitude: Double
    public var colorIndex: Double
    /// Proper motion in arcseconds per year; `pmRA` already includes cos(dec).
    public var pmRA: Double = 0
    public var pmDec: Double = 0

    /// J2000 coordinates moved by proper motion to `date` (linear, which is close enough over a few thousand years).
    public func position(at date: Date) -> (ra: Double, dec: Double) {
        let years = date.timeIntervalSince(SkyEngine.j2000) / (365.25 * 86_400)
        let dec = self.dec + pmDec * years / 3600
        let ra = self.ra + pmRA * years / 3600 / max(cos(self.dec * .pi / 180), 1e-6)
        return (ra, dec)
    }
}

public struct Constellation: Sendable, Decodable {
    public var id: String
    /// Polylines of HR numbers.
    public var lines: [[Int]]
}

public enum Catalog {
    /// Yale Bright Star Catalogue, 5th ed. (VizieR V/50): HR, RA and Dec (J2000, degrees), V, B−V,
    /// proper motion in RA (× cos dec) and Dec (arcsec/yr).
    public static let stars: [Star] = {
        let url = Bundle.module.url(forResource: "bsc5", withExtension: "json")!
        let rows = try! JSONDecoder().decode([[Double]].self, from: Data(contentsOf: url))
        return rows.map { Star(hr: Int($0[0]), ra: $0[1], dec: $0[2], magnitude: $0[3], colorIndex: $0[4], pmRA: $0[5], pmDec: $0[6]) }
    }()

    public static let constellations: [Constellation] = {
        let url = Bundle.module.url(forResource: "constellations", withExtension: "json")!
        return try! JSONDecoder().decode([Constellation].self, from: Data(contentsOf: url))
    }()
}

public struct PlacedStar: Sendable {
    public var star: Star
    public var position: Horizontal
}

public struct PlacedBody: Sendable {
    public var body: Body
    public var position: Horizontal
    public var magnitude: Double
    public var phaseFraction: Double
}

/// Everything above (and just below) the horizon for one place and time.
public struct SkyScene: Sendable {
    public var date: Date
    public var observer: Observer
    public var stars: [PlacedStar]
    public var starsByHR: [Int: Horizontal]
    public var bodies: [PlacedBody]
    /// Moon's elongation east of the sun, degrees (0 new, 180 full).
    public var moonPhase: Double

    public init(date: Date, observer: Observer, magnitudeLimit: Double = 6.5) throws {
        self.date = date
        self.observer = observer
        let visible = Catalog.stars.filter { $0.magnitude <= magnitudeLimit }
        let positions = SkyEngine.horizontal(j2000: visible.map { $0.position(at: date) }, at: date, from: observer)
        stars = zip(visible, positions).map { PlacedStar(star: $0, position: $1) }
        starsByHR = Dictionary(uniqueKeysWithValues: stars.map { ($0.star.hr, $0.position) })
        bodies = try ([.moon] + Body.planets).map { body in
            let i = try SkyEngine.illumination(body, at: date)
            return PlacedBody(
                body: body,
                position: try SkyEngine.horizontal(body, at: date, from: observer),
                magnitude: i.magnitude,
                phaseFraction: i.phaseFraction
            )
        }
        moonPhase = try SkyEngine.moonPhase(at: date)
    }
}
