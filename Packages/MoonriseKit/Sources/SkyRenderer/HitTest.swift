import CoreGraphics
import SkyEngine

public enum SkyObject: Sendable, Equatable {
    case body(Body)
    /// IAU abbreviation.
    case constellation(String)
    /// Messier number.
    case deepSky(Int)
    /// NGC or IC designation, e.g. "NGC 7000".
    case ngc(String)
}

extension SkyScene {
    /// The object under a tap: the nearest visible sun, moon or planet within `radius` points,
    /// else the nearest Messier object within 0.6 × `radius` (when `deepSky`),
    /// else the constellation whose figure has a star nearest the tap.
    public func object(at point: CGPoint, projection p: Projection, radius: CGFloat = 28, deepSky: Bool = true) -> SkyObject? {
        func distance(_ h: Horizontal) -> CGFloat? {
            guard h.altitude > 0, let q = p.point(h) else { return nil }
            return hypot(q.x - point.x, q.y - point.y)
        }
        let bodyHit = bodies
            .filter { $0.magnitude <= 6 }
            .compactMap { b in distance(b.position).map { (b.body, $0) } }
            .filter { $0.1 <= radius }
            .min { $0.1 < $1.1 }
        if let bodyHit { return .body(bodyHit.0) }

        if deepSky {
            let hit = self.deepSky
                .compactMap { d in distance(d.position).map { (d.object.messier, $0) } }
                .filter { $0.1 <= radius * 0.6 }
                .min { $0.1 < $1.1 }
            if let hit { return .deepSky(hit.0) }
            if p.fieldOfView <= 40, let n = ngc
                .compactMap({ d in distance(d.position).map { (d.object.name, $0) } })
                .filter({ $0.1 <= radius * 0.6 })
                .min(by: { $0.1 < $1.1 }) {
                return .ngc(n.0)
            }
        }

        var best: (String, CGFloat)?
        for c in Catalog.constellations {
            for hr in c.lines.joined() {
                guard let h = starsByHR[hr], let d = distance(h), d <= radius * 1.5 else { continue }
                if best == nil || d < best!.1 { best = (c.id, d) }
            }
        }
        return best.map { .constellation($0.0) }
    }
}
