import Foundation

/// A place where totality or annularity lasts nearly as long as on the centre line, for driving to.
public struct EclipseSite: Sendable {
    public var latitude: Double
    public var longitude: Double
    public var duration: TimeInterval
    /// On the centre line at the same point of the path.
    public var centerDuration: TimeInterval
    /// Straight-line distance from the observer.
    public var distanceKm: Double
}

extension EclipsePath {
    /// A point in the band of the path where the central phase should last at least `share` of its centre-line length.
    public struct Candidate: Sendable {
        public var latitude: Double
        public var longitude: Double
        var center: (lat: Double, lon: Double)
        public var distanceKm: Double
    }

    /// Points in the band nearest `observer` first, each at least `spacingKm` from those before it, up to `limit`.
    /// With a uniform shadow the duration falls off as √(1 − x²) at a fraction x of the way to the limit, so the band
    /// is within √(1 − share²) of the centre line (31% for 95%). Some may be at sea; check each with `site(_:share:)`.
    public func candidates(near observer: Observer, share: Double = 0.95, limit: Int = 60, spacingKm: Double = 25) -> [Candidate] {
        let reach = (1 - share * share).squareRoot()
        var out: [Candidate] = []
        for (a, b) in zip(points, points.dropFirst()) {
            guard let an = a.north, let asouth = a.south, let bn = b.north, let bs = b.south else { continue }
            for step in 0..<4 {
                let u = Double(step) / 4
                let c = Self.mix(a.center, b.center, u), n = Self.mix(an, bn, u), s = Self.mix(asouth, bs, u)
                for k in -4...4 {
                    let t = reach * Double(k) / 4
                    let p = Self.mix(c, t >= 0 ? n : s, abs(t))
                    out.append(Candidate(latitude: p.lat, longitude: p.lon, center: c,
                                         distanceKm: Self.distanceKm(p, (observer.latitude, observer.longitude))))
                }
            }
        }
        var picked: [Candidate] = []
        for c in out.sorted(by: { $0.distanceKm < $1.distanceKm }) where picked.count < limit {
            if picked.allSatisfy({ Self.distanceKm(($0.latitude, $0.longitude), (c.latitude, c.longitude)) >= spacingKm }) { picked.append(c) }
        }
        return picked
    }

    /// The candidate with its durations, if a full local calculation confirms at least `share` of the centre line.
    public func site(_ c: Candidate, share: Double = 0.95) -> EclipseSite? {
        guard let center = Self.duration(at: c.center, near: peak), let d = Self.duration(at: (c.latitude, c.longitude), near: peak),
              d >= share * center else { return nil }
        return EclipseSite(latitude: c.latitude, longitude: c.longitude, duration: d, centerDuration: center, distanceKm: c.distanceKm)
    }

    static func duration(at p: (lat: Double, lon: Double), near date: Date) -> TimeInterval? {
        guard let l = LocalEclipse.at(Observer(latitude: p.lat, longitude: p.lon), near: date),
              let b = l.centralBegin, let e = l.centralEnd else { return nil }
        return e.timeIntervalSince(b)
    }

    /// Linear in latitude and longitude, the short way round in longitude.
    static func mix(_ a: (lat: Double, lon: Double), _ b: (lat: Double, lon: Double), _ u: Double) -> (lat: Double, lon: Double) {
        let dLon = remainder(b.lon - a.lon, 360)
        return (a.lat + (b.lat - a.lat) * u, remainder(a.lon + dLon * u, 360))
    }

    /// Great-circle distance on a 6,371 km sphere.
    static func distanceKm(_ a: (lat: Double, lon: Double), _ b: (lat: Double, lon: Double)) -> Double {
        let r = Double.pi / 180
        let h = pow(sin((b.lat - a.lat) * r / 2), 2) + cos(a.lat * r) * cos(b.lat * r) * pow(sin((b.lon - a.lon) * r / 2), 2)
        return 2 * 6371 * asin(min(1, h.squareRoot()))
    }
}
