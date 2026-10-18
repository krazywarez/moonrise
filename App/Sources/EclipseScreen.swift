import SkyEngine
import SkyRenderer
import SwiftUI

/// Map of a total or annular eclipse's path, with timings at greatest eclipse and for the observer.
struct EclipseScreen: View {
    var date: Date
    var observer: Observer
    var placeName: String
    @State private var path: EclipsePath?
    @State private var local: LocalEclipse?
    @State private var loaded = false
    @Environment(\.dismiss) private var dismiss

    private let ink = Color(red: 0.95, green: 0.95, blue: 0.93)
    private let accent = Color(red: 0.88, green: 0.24, blue: 0.19)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let path {
                        EclipseMap(path: path, observer: observer, ink: ink, accent: accent)
                            .aspectRatio(1.6, contentMode: .fit)
                            .accessibilityLabel("Map of the path of the eclipse")
                        facts(path)
                    } else if loaded {
                        Text("This eclipse is partial everywhere, so there is no path to map.").font(.footnote).dimmed(0.7)
                    } else {
                        ProgressView().tint(ink).frame(maxWidth: .infinity, minHeight: 200)
                    }
                    if loaded { here }
                }
                .padding(20)
                .readableWidth()
            }
            .background(Color.black.ignoresSafeArea())
            .foregroundStyle(ink)
            .navigationTitle(path.map { "\($0.kind) solar eclipse" } ?? "Solar eclipse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task {
            let date = date, observer = observer
            (path, local) = await Task.detached { (EclipsePath.compute(near: date), LocalEclipse.at(observer, near: date)) }.value
            loaded = true
        }
    }

    private func facts(_ p: EclipsePath) -> some View {
        let middle = p.points.min { abs($0.date.timeIntervalSince(p.peak)) < abs($1.date.timeIntervalSince(p.peak)) }
        var rows: [(String, String)] = [
            ("Date", p.peak.formatted(date: .long, time: .omitted)),
            ("Greatest eclipse", "\(p.peak.formatted(date: .omitted, time: .shortened)) at \(latLon(p.greatest))"),
        ]
        if let d = p.centralDuration { rows.append(("\(p.kind == "Total" ? "Totality" : "Annularity") there", minutes(d))) }
        if let m = middle { rows.append(("Path width there", "\(Int(m.widthKm.rounded())) km")) }
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            ForEach(rows, id: \.0) { r in
                GridRow { Text(r.0).dimmed(0.7); Text(r.1).monospacedDigit() }.font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private var here: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("From \(placeName)").font(.caption2.weight(.medium)).textCase(.uppercase).tracking(0.8).dimmed(0.6)
            if let l = local {
                let central = l.kind == "Total" ? "Totality" : "Annular phase"
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow { Text("Begins").dimmed(0.7); Text(time(l.partialBegin)) }
                    if let b = l.centralBegin, let e = l.centralEnd {
                        GridRow { Text(central).dimmed(0.7); Text("\(time(b))–\(time(e)), \(minutes(e.timeIntervalSince(b)))") }
                    }
                    GridRow { Text("Maximum").dimmed(0.7); Text("\(time(l.peak)), \(Int((l.obscuration * 100).rounded()))% of the Sun covered") }
                    GridRow { Text("Ends").dimmed(0.7); Text(time(l.partialEnd)) }
                }
                .font(.subheadline.monospacedDigit())
                if l.peakAltitude < 10 {
                    Text("The Sun is low at maximum (\(Int(l.peakAltitude.rounded()))°). Find a clear horizon.").font(.footnote).dimmed(0.7)
                }
            } else {
                Text("Not visible from here.").font(.subheadline).dimmed(0.7)
            }
            Text("Never look at the Sun without certified eclipse glasses, except during totality itself.")
                .font(.footnote).foregroundStyle(accent).padding(.top, 6)
        }
    }

    private func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .standard) }

    private func minutes(_ s: TimeInterval) -> String { "\(Int(s) / 60) m \(Int(s) % 60) s" }

    private func latLon(_ p: (lat: Double, lon: Double)) -> String {
        String(format: "%.1f°%@, %.1f°%@", abs(p.lat), p.lat >= 0 ? "N" : "S", abs(p.lon), p.lon >= 0 ? "E" : "W")
    }
}

/// Equirectangular map around the path: coastlines, the band between the limits, and the centre line.
struct EclipseMap: View {
    var path: EclipsePath
    var observer: Observer
    var ink: Color
    var accent: Color

    var body: some View {
        Canvas { context, size in
            let centers = path.points.map(\.center)
            let lats = centers.map(\.lat), lons = centers.map(\.lon)
            let latRange = (lats.min()! - 8)...(lats.max()! + 8)
            let lonRange = (lons.min()! - 10)...(lons.max()! + 10)
            func pt(_ lat: Double, _ lon: Double) -> CGPoint {
                CGPoint(x: (lon - lonRange.lowerBound) / (lonRange.upperBound - lonRange.lowerBound) * size.width,
                        y: (latRange.upperBound - lat) / (latRange.upperBound - latRange.lowerBound) * size.height)
            }

            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(ink.opacity(0.04)))
            var grid = Path()
            for lat in stride(from: -80.0, through: 80, by: 10) where latRange.contains(lat) {
                grid.move(to: pt(lat, lonRange.lowerBound)); grid.addLine(to: pt(lat, lonRange.upperBound))
            }
            for lon in stride(from: -180.0, through: 180, by: 10) where lonRange.contains(lon) {
                grid.move(to: pt(latRange.lowerBound, lon)); grid.addLine(to: pt(latRange.upperBound, lon))
            }
            context.stroke(grid, with: .color(ink.opacity(0.08)), lineWidth: 0.5)

            var coast = Path()
            for line in Coastline.lines {
                var pen = false
                for p in line {
                    let q = pt(p.lat, p.lon)
                    if pen { coast.addLine(to: q) } else { coast.move(to: q); pen = true }
                }
            }
            context.stroke(coast, with: .color(ink.opacity(0.55)), lineWidth: 0.8)

            let limits = path.points.compactMap { p in p.north.flatMap { n in p.south.map { (n, $0) } } }
            if limits.count > 1 {
                var band = Path()
                band.move(to: pt(limits[0].0.lat, limits[0].0.lon))
                for l in limits.dropFirst() { band.addLine(to: pt(l.0.lat, l.0.lon)) }
                for l in limits.reversed() { band.addLine(to: pt(l.1.lat, l.1.lon)) }
                band.closeSubpath()
                context.fill(band, with: .color(accent.opacity(0.4)))
            }
            var center = Path()
            center.addLines(centers.map { pt($0.lat, $0.lon) })
            context.stroke(center, with: .color(accent), lineWidth: 1.2)

            let g = pt(path.greatest.lat, path.greatest.lon)
            context.stroke(Path(ellipseIn: CGRect(x: g.x - 5, y: g.y - 5, width: 10, height: 10)), with: .color(ink), lineWidth: 1.5)
            if latRange.contains(observer.latitude), lonRange.contains(observer.longitude) {
                let o = pt(observer.latitude, observer.longitude)
                context.fill(Path(ellipseIn: CGRect(x: o.x - 4, y: o.y - 4, width: 8, height: 8)), with: .color(ink))
                context.draw(Text("You").font(.caption2).foregroundStyle(ink), at: CGPoint(x: o.x, y: o.y - 11))
            }
        }
        .overlay(alignment: .bottomLeading) {
            Text("Shaded: where the eclipse is \(path.kind.lowercased()). Ring: greatest eclipse.")
                .font(.caption2).dimmed(0.7).padding(6)
        }
    }
}
