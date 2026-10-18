import Library
import simd
import SkyRenderer
import SwiftUI

/// The generated drawing at the top of a Library page, built from the page's data.
struct PageDrawing: View {
    var page: LibraryPage
    var ink: Color
    var accent: Color

    var body: some View {
        Group {
            switch page.drawing?.kind {
            case "planet": planet
            case "constellation": constellation
            case "star": star
            case "deep-sky": deepSky
            case "mission": mission
            case "exoplanet": exoplanet
            case "rocket": RocketLineup(highlight: page.id, ink: ink, accent: accent).frame(height: 260)
            default: EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Planets, moons, the Sun

    /// The body to scale with Earth beside it (or the Sun with Earth as a dot).
    private var planet: some View {
        let d = page.drawing!
        let radius = d.radiusKm ?? 6371
        let fill = Color(hex: d.color) ?? ink.opacity(0.6)
        return Canvas { context, size in
            let earthKm = 6371.0
            let ringed = d.rings == true
            // Rings reach about 2.2 body radii; leave room for the Earth label underneath.
            let extent = ringed ? 2.25 : 1.0
            let maxR = min(size.height / 2 - 16, (size.width - 24) / (2 * extent))
            let scale = maxR / max(radius, earthKm)
            let r = radius * scale, er = max(earthKm * scale, 1.5)
            let c = CGPoint(x: size.width / 2, y: size.height / 2 - 8)
            if ringed {
                let ring = Path(ellipseIn: CGRect(x: c.x - r * 2.2, y: c.y - r * 0.45, width: r * 4.4, height: r * 0.9))
                context.stroke(ring, with: .color(ink.opacity(0.7)), lineWidth: 1)
            }
            context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(fill))
            context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(ink.opacity(0.8)), lineWidth: 0.8)
            if let tilt = d.axialTiltDeg {
                let a = tilt * .pi / 180
                var axis = Path()
                axis.move(to: CGPoint(x: c.x - sin(a) * r * 1.25, y: c.y - cos(a) * r * 1.25))
                axis.addLine(to: CGPoint(x: c.x + sin(a) * r * 1.25, y: c.y + cos(a) * r * 1.25))
                context.stroke(axis, with: .color(accent), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
            }
            if page.id != "earth" {
                let ec = CGPoint(x: size.width - er - 6, y: size.height - er - 16)
                context.fill(Path(ellipseIn: CGRect(x: ec.x - er, y: ec.y - er, width: 2 * er, height: 2 * er)), with: .color(Color(red: 0.35, green: 0.6, blue: 0.95)))
                context.draw(Text("Earth").font(.caption2).foregroundStyle(ink.opacity(0.6)), at: CGPoint(x: size.width - 2, y: size.height - 6), anchor: .trailing)
            }
        }
        .frame(height: 200)
        .accessibilityLabel("\(page.title) drawn to scale with Earth")
    }

    // MARK: Constellations

    private var constellation: some View {
        let lines = Catalog.constellations.first { $0.id == page.link.constellation }?.lines ?? []
        let byHR = Dictionary(uniqueKeysWithValues: Catalog.stars.map { ($0.hr, $0) })
        let stars = Set(lines.joined()).compactMap { byHR[$0] }
        return Canvas { context, size in
            guard !stars.isEmpty else { return }
            // Gnomonic projection about the figure's centre.
            func unit(_ s: Star) -> SIMD3<Double> {
                let ra = s.ra * .pi / 180, dec = s.dec * .pi / 180
                return SIMD3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec))
            }
            var c = stars.map(unit).reduce(SIMD3<Double>(repeating: 0), +)
            c /= (c * c).sum().squareRoot()
            let e0 = SIMD3(-c.y, c.x, 0)
            let east = simd_length(e0) < 1e-6 ? SIMD3<Double>(0, 1, 0) : simd_normalize(e0)
            let north = SIMD3(c.y * east.z - c.z * east.y, c.z * east.x - c.x * east.z, c.x * east.y - c.y * east.x)
            func plane(_ s: Star) -> SIMD2<Double> {
                let v = unit(s), k = (v * c).sum()
                // East to the left, as on the sky.
                return SIMD2(-(v * east).sum() / k, (v * north).sum() / k)
            }
            let pts = Dictionary(uniqueKeysWithValues: stars.map { ($0.hr, plane($0)) })
            let xs = pts.values.map(\.x), ys = pts.values.map(\.y)
            let span = max(xs.max()! - xs.min()!, ys.max()! - ys.min()!, 1e-6)
            let scale = (min(size.width, size.height) - 24) / span
            let mid = SIMD2((xs.max()! + xs.min()!) / 2, (ys.max()! + ys.min()!) / 2)
            func point(_ hr: Int) -> CGPoint? {
                pts[hr].map { CGPoint(x: size.width / 2 + ($0.x - mid.x) * scale, y: size.height / 2 - ($0.y - mid.y) * scale) }
            }
            var path = Path()
            for line in lines {
                for (a, b) in zip(line, line.dropFirst()) {
                    guard let pa = point(a), let pb = point(b) else { continue }
                    path.move(to: pa)
                    path.addLine(to: pb)
                }
            }
            context.stroke(path, with: .color(ink.opacity(0.45)), lineWidth: 0.8)
            for s in stars {
                guard let p = point(s.hr) else { continue }
                let r = max(1.2, 4.2 - 0.6 * s.magnitude)
                context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(ink))
            }
        }
        .frame(height: 240)
        .accessibilityLabel("Figure of \(page.title)")
    }

    // MARK: Stars

    private var star: some View {
        let bv = page.drawing?.colorIndex ?? 0.6
        let t = min(max((bv + 0.3) / 2.0, 0), 1)
        let color = Color(red: 0.75 + 0.25 * t, green: 0.82 - 0.1 * t, blue: 1.0 - 0.45 * t)
        return VStack(spacing: 8) {
            Circle().fill(color).frame(width: 90, height: 90)
            if let sp = page.drawing?.spectralType {
                Text("Spectral type \(sp) · B−V \(String(format: "%.2f", bv))").font(.caption2).opacity(0.6)
            }
        }
        .frame(height: 140)
    }

    // MARK: Deep sky

    /// The object's apparent size beside the full Moon (about 31′).
    private var deepSky: some View {
        let d = page.drawing!
        let size = d.sizeArcmin ?? 5
        return Canvas { context, canvas in
            let moon = 31.0
            let scale = (canvas.height - 30) / max(size, moon)
            let r = size * scale / 2, mr = moon * scale / 2
            let c = CGPoint(x: canvas.width / 2 - mr - 10, y: canvas.height / 2 - 8)
            let m = CGPoint(x: canvas.width / 2 + r + 10, y: canvas.height / 2 - 8)
            let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
            switch d.type {
            case "galaxy":
                context.fill(Path(ellipseIn: rect.insetBy(dx: 0, dy: r * 0.6)), with: .color(ink.opacity(0.5)))
            case "planetary":
                context.stroke(Path(ellipseIn: rect), with: .color(ink.opacity(0.8)), lineWidth: max(1, r * 0.25))
            case "globular", "open":
                context.fill(Path(ellipseIn: rect), with: .color(ink.opacity(d.type == "globular" ? 0.45 : 0.15)))
            default:
                context.fill(Path(ellipseIn: rect), with: .color(ink.opacity(0.3)))
            }
            context.stroke(Path(ellipseIn: CGRect(x: m.x - mr, y: m.y - mr, width: 2 * mr, height: 2 * mr)), with: .color(ink.opacity(0.5)), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
            context.draw(Text("\(Int(size.rounded()))′").font(.caption2).foregroundStyle(ink.opacity(0.7)), at: CGPoint(x: c.x, y: canvas.height - 10))
            context.draw(Text("Full Moon").font(.caption2).foregroundStyle(ink.opacity(0.7)), at: CGPoint(x: m.x, y: canvas.height - 10))
        }
        .frame(height: 170)
        .accessibilityLabel("\(page.title) apparent size compared with the full Moon")
    }

    // MARK: Exoplanets

    /// The planet beside Earth and Jupiter to scale, and its orbit beside Mercury's and Earth's.
    private var exoplanet: some View {
        let d = page.drawing!
        let star = starColor(d.starTempK)
        return HStack(alignment: .bottom, spacing: 24) {
            if let r = d.radiusEarth {
                Canvas { context, size in
                    let maxR = max(r, 11.2)
                    let scale = (size.height - 22) / (2 * maxR)
                    let bodies: [(String, Double, Color)] = [("Earth", 1, Color(red: 0.35, green: 0.6, blue: 0.95)), (page.title, r, ink), ("Jupiter", 11.2, Color(red: 0.85, green: 0.72, blue: 0.55))]
                    var x = 8.0
                    for (name, radius, color) in bodies.sorted(by: { $0.1 < $1.1 }) {
                        let rr = max(radius * scale, 1.5)
                        let c = CGPoint(x: x + rr, y: size.height - 18 - rr)
                        context.fill(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: 2 * rr, height: 2 * rr)), with: .color(name == page.title ? accent : color))
                        context.draw(Text(name).font(.caption2).foregroundStyle(ink.opacity(0.7)), at: CGPoint(x: c.x, y: size.height - 6))
                        x += 2 * rr + 34
                    }
                }
                .frame(height: 140)
                .accessibilityLabel("\(page.title), \(String(format: "%.1f", r)) times Earth's radius")
            }
            if let a = d.orbitAU {
                Canvas { context, size in
                    let c = CGPoint(x: size.width / 2, y: size.height / 2 - 6)
                    let outer = max(a, 1)
                    let scale = (min(size.width, size.height) / 2 - 14) / outer
                    for (name, au) in [("Mercury", 0.387), ("Earth", 1.0)] where au <= outer {
                        let r = au * scale
                        context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(ink.opacity(0.3)), style: StrokeStyle(lineWidth: 0.6, dash: [2, 3]))
                        context.draw(Text(name).font(.caption2).foregroundStyle(ink.opacity(0.6)), at: CGPoint(x: c.x, y: c.y - r - 7))
                    }
                    let r = a * scale
                    context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(accent), lineWidth: 1)
                    context.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(star))
                    context.draw(Text(String(format: "%.3g AU", a)).font(.caption2).foregroundStyle(ink), at: CGPoint(x: c.x, y: size.height - 6))
                }
                .frame(width: 150, height: 150)
                .accessibilityLabel("Orbit \(String(format: "%.3g", a)) astronomical units from its star")
            }
        }
    }

    private func starColor(_ t: Double?) -> Color {
        guard let t else { return ink }
        if t < 3700 { return Color(red: 1, green: 0.6, blue: 0.4) }
        if t < 5200 { return Color(red: 1, green: 0.8, blue: 0.55) }
        if t < 6000 { return Color(red: 1, green: 0.95, blue: 0.8) }
        return Color(red: 0.8, green: 0.88, blue: 1)
    }

    // MARK: Missions

    private var mission: some View {
        let d = page.drawing!
        return HStack(spacing: 10) {
            Text((d.status ?? "").uppercased())
                .font(.caption2.weight(.medium)).tracking(0.6)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .foregroundStyle(d.status == "active" ? Color.black : ink)
                .background(d.status == "active" ? ink : ink.opacity(0.15), in: .rect(cornerRadius: 2))
            if let launch = d.launch { Text("Launched \(launch)").font(.footnote.monospacedDigit()) }
            Spacer()
        }
    }
}

extension Color {
    init?(hex: String?) {
        guard let hex, hex.hasPrefix("#"), hex.count == 7, let v = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
