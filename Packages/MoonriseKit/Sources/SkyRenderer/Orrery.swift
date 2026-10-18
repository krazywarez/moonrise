import Foundation
import SkyEngine
import SwiftUI

/// SkyEngine's Body, named so it isn't shadowed by View.Body.
typealias SolarBody = Body

/// Deep-space probes with heliocentric ecliptic positions every 30 days to 2050,
/// from JPL Horizons (REF_PLANE ECLIPTIC, CENTER 500@10), fetched 2026-10-17.
public struct Spacecraft: Sendable, Identifiable, Decodable {
    public var id: Int
    public var name: String
    public var launch: String
    /// [days since 1970-01-01, x AU, y AU, z AU]
    public var points: [[Double]]

    public static let all: [Spacecraft] = {
        let url = Bundle.module.url(forResource: "spacecraft", withExtension: "json")!
        return try! JSONDecoder().decode([Spacecraft].self, from: Data(contentsOf: url))
    }()

    var firstDay: Double { points.first?[0] ?? 0 }

    /// Linearly interpolated position on the ecliptic plane, or nil before the data starts.
    public func position(at date: Date) -> SIMD2<Double>? {
        position3(at: date).map { SIMD2($0.x, $0.y) }
    }

    /// Linearly interpolated position in AU, or nil before the data starts.
    public func position3(at date: Date) -> SIMD3<Double>? {
        let d = date.timeIntervalSince1970 / 86_400
        guard let first = points.first, d >= first[0] else { return nil }
        let v: ([Double]) -> SIMD3<Double> = { SIMD3($0[1], $0[2], $0[3]) }
        guard let i = points.firstIndex(where: { $0[0] >= d }) else { return points.last.map(v) }
        if i == 0 { return v(first) }
        let a = points[i - 1], b = points[i]
        let t = (d - a[0]) / (b[0] - a[0])
        return v(a) + (v(b) - v(a)) * t
    }

    /// Distance from the Sun in AU.
    public func distance(at date: Date) -> Double? {
        position3(at: date).map { ($0 * $0).sum().squareRoot() }
    }

    /// Path from the start of the data up to `date`.
    public func path(until date: Date) -> [SIMD2<Double>] {
        let d = date.timeIntervalSince1970 / 86_400
        var out = points.prefix { $0[0] <= d }.map { SIMD2($0[1], $0[2]) }
        if let p = position(at: date) { out.append(p) }
        return out
    }
}

/// Top-down view of the solar system on ecliptic axes with a compressed
/// radial scale so inner planets and the Voyagers fit on one screen.
public struct OrreryScale: Sendable {
    public var size: CGSize
    /// Distance (AU) mapped to the edge of the view.
    public var maxAU: Double = 230

    public init(size: CGSize) { self.size = size }

    /// Radius in points for a distance in AU: logarithmic beyond 1 AU, linear inside.
    public func radius(_ au: Double) -> Double {
        let edge = Double(min(size.width, size.height)) / 2 - 8
        let f = au <= 1 ? au * 0.2 : 0.2 + 0.8 * log10(au) / log10(maxAU)
        return edge * f
    }

    public func point(_ v: SIMD2<Double>) -> CGPoint {
        let au = (v * v).sum().squareRoot()
        guard au > 0 else { return CGPoint(x: size.width / 2, y: size.height / 2) }
        let r = radius(au) / au
        // Ecliptic x (vernal equinox) to the right, y up.
        return CGPoint(x: size.width / 2 + v.x * r, y: size.height / 2 - v.y * r)
    }
}

public struct OrreryView: View {
    public var date: Date
    public var ink: Color
    public var accent: Color

    public init(date: Date, ink: Color, accent: Color) {
        self.date = date
        self.ink = ink
        self.accent = accent
    }

    /// Mean distances (AU) for orbit rings.
    static let orbits: [(SolarBody, Double)] = [(.mercury, 0.387), (.venus, 0.723), (.sun, 1.0), (.mars, 1.524), (.jupiter, 5.203), (.saturn, 9.537), (.uranus, 19.19), (.neptune, 30.07)]

    public var body: some View {
        Canvas { context, size in
            let s = OrreryScale(size: size)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)

            for au: Double in [50, 100, 200] {
                let r = CGFloat(s.radius(au))
                context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                               with: .color(ink.opacity(0.12)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                context.draw(Text("\(Int(au)) AU").font(.system(size: 9)).foregroundStyle(ink.opacity(0.4)), at: CGPoint(x: c.x, y: c.y - r - 7))
            }
            for (_, au) in Self.orbits {
                let r = CGFloat(s.radius(au))
                context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(ink.opacity(0.25)), lineWidth: 0.5)
            }
            context.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(Color(red: 0.95, green: 0.75, blue: 0.35)))

            for craft in Spacecraft.all {
                let path = craft.path(until: date)
                guard let last = path.last else { continue }
                var line = Path()
                line.move(to: s.point(path[0]))
                for v in path.dropFirst() { line.addLine(to: s.point(v)) }
                context.stroke(line, with: .color(accent.opacity(0.7)), lineWidth: 0.8)
                let p = s.point(last)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(accent))
                context.draw(Text(craft.name).font(.system(size: 9)).foregroundStyle(accent), at: CGPoint(x: p.x + 6, y: p.y), anchor: .leading)
            }

            for body in [SolarBody.mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune] {
                guard let v = try? SkyEngine.heliocentricEcliptic(body, at: date) else { continue }
                let p = s.point(SIMD2(v.x, v.y))
                let r: CGFloat = [.jupiter, .saturn].contains(body) ? 4 : 3
                context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(ink))
                if [.jupiter, .saturn, .uranus, .neptune].contains(body) {
                    context.draw(Text(body.rawValue.capitalized).font(.system(size: 9)).foregroundStyle(ink.opacity(0.8)), at: CGPoint(x: p.x, y: p.y + 10))
                }
            }
            if let earth = try? SkyEngine.heliocentricEarth(at: date) {
                let p = s.point(SIMD2(earth.x, earth.y))
                context.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(Color(red: 0.35, green: 0.6, blue: 0.95)))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

}
