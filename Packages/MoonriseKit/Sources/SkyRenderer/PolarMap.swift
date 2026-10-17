import Foundation
import SwiftUI

/// Natural Earth 1:110m coastlines (public domain), polylines of [longitude, latitude],
/// kept where they reach 30° or more from the equator.
public enum Coastline {
    public static let lines: [[(lon: Double, lat: Double)]] = {
        let url = Bundle.module.url(forResource: "coastline", withExtension: "json")!
        let raw = try! JSONDecoder().decode([[[Double]]].self, from: Data(contentsOf: url))
        return raw.map { $0.map { (lon: $0[0], lat: $0[1]) } }
    }()
}

/// Azimuthal equidistant view of one polar region, rotated so the given
/// longitude points down the screen.
public struct PolarProjection: Sendable {
    public var north: Bool
    public var centerLongitude: Double
    /// Latitude at the edge of the map (absolute).
    public var edgeLatitude: Double
    public var size: CGSize

    public init(north: Bool, centerLongitude: Double, edgeLatitude: Double = 40, size: CGSize) {
        self.north = north
        self.centerLongitude = centerLongitude
        self.edgeLatitude = edgeLatitude
        self.size = size
    }

    public func point(lon: Double, lat: Double) -> CGPoint? {
        let colat = 90 - (north ? lat : -lat)
        guard colat <= 90 - edgeLatitude + 2 else { return nil }
        let scale = min(size.width, size.height) / 2 / (90 - edgeLatitude)
        let a = (lon - centerLongitude) * .pi / 180 * (north ? 1 : -1)
        let r = colat * scale
        return CGPoint(x: size.width / 2 + r * sin(a), y: size.height / 2 + r * cos(a))
    }
}

/// A gridded value (e.g. aurora probability, 0–100) on 1° cells.
public struct GridValue: Sendable {
    public var lon: Double
    public var lat: Double
    public var value: Double

    public init(lon: Double, lat: Double, value: Double) {
        self.lon = lon
        self.lat = lat
        self.value = value
    }
}

public struct AuroraMap: View {
    public var cells: [GridValue]
    public var observer: (lat: Double, lon: Double)
    public var ink: Color
    public var aurora: Color

    public init(cells: [GridValue], observer: (lat: Double, lon: Double), ink: Color, aurora: Color = Color(red: 0.35, green: 0.85, blue: 0.5)) {
        self.cells = cells
        self.observer = observer
        self.ink = ink
        self.aurora = aurora
    }

    public var body: some View {
        Canvas { context, size in
            let north = observer.lat >= 0
            let p = PolarProjection(north: north, centerLongitude: observer.lon, size: size)
            let scale = min(size.width, size.height) / 2 / (90 - p.edgeLatitude)

            for c in cells where (c.lat >= 0) == north && c.value >= 3 {
                guard let pt = p.point(lon: c.lon, lat: c.lat) else { continue }
                let s = max(2, scale * 1.1)
                context.fill(Path(CGRect(x: pt.x - s / 2, y: pt.y - s / 2, width: s, height: s)),
                             with: .color(aurora.opacity(min(0.9, 0.15 + c.value / 40))))
            }

            for lat in stride(from: 50.0, through: 80, by: 10) {
                let r = (90 - lat) * scale
                context.stroke(Path(ellipseIn: CGRect(x: size.width / 2 - r, y: size.height / 2 - r, width: 2 * r, height: 2 * r)),
                               with: .color(ink.opacity(0.15)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
            }

            var coast = Path()
            for line in Coastline.lines {
                var pen = false
                for c in line {
                    guard let pt = p.point(lon: c.lon, lat: c.lat) else { pen = false; continue }
                    if pen { coast.addLine(to: pt) } else { coast.move(to: pt); pen = true }
                }
            }
            context.stroke(coast, with: .color(ink.opacity(0.6)), lineWidth: 0.7)

            if let you = p.point(lon: observer.lon, lat: observer.lat) {
                context.fill(Path(ellipseIn: CGRect(x: you.x - 4, y: you.y - 4, width: 8, height: 8)), with: .color(ink))
                context.draw(Text("You").font(.system(size: 10)).foregroundStyle(ink), at: CGPoint(x: you.x, y: you.y + 12))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
