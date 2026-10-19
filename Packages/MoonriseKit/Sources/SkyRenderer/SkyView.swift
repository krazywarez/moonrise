import SkyEngine
import SwiftUI

/// Stereographic projection of the sky centred on a viewing direction.
public struct Projection: Sendable {
    public var centerAzimuth: Double
    public var centerAltitude: Double
    /// Horizontal field of view in degrees.
    public var fieldOfView: Double
    public var size: CGSize

    public init(centerAzimuth: Double, centerAltitude: Double, fieldOfView: Double, size: CGSize) {
        self.centerAzimuth = centerAzimuth
        self.centerAltitude = centerAltitude
        self.fieldOfView = fieldOfView
        self.size = size
    }

    /// Screen point, or nil when the direction is behind the viewer.
    public func point(_ h: Horizontal) -> CGPoint? {
        let r = Double.pi / 180
        let alt = h.altitude * r, alt0 = centerAltitude * r
        let dAz = (h.azimuth - centerAzimuth) * r
        let cosC = sin(alt0) * sin(alt) + cos(alt0) * cos(alt) * cos(dAz)
        guard cosC > -0.2 else { return nil }
        let k = 2 / (1 + cosC)
        let x = k * cos(alt) * sin(dAz)
        let y = k * (cos(alt0) * sin(alt) - sin(alt0) * cos(alt) * cos(dAz))
        let scale = Double(size.width) / (4 * tan(fieldOfView * r / 4))
        return CGPoint(x: Double(size.width) / 2 + x * scale, y: Double(size.height) / 2 - y * scale)
    }
}

public struct SkyStyle: Sendable {
    public var background = Color(red: 0.043, green: 0.078, blue: 0.141)
    public var ground = Color(red: 0.02, green: 0.035, blue: 0.06)
    public var line = Color(red: 0.30, green: 0.36, blue: 0.45)
    public var label = Color(red: 0.95, green: 0.95, blue: 0.93)
    public var muted = Color(red: 0.60, green: 0.64, blue: 0.70)
    public var moonLight = Color(red: 0.93, green: 0.91, blue: 0.85)
    public var moonDark = Color(red: 0.16, green: 0.20, blue: 0.27)
    public var planet = Color(red: 0.95, green: 0.84, blue: 0.60)
    /// Rings and lines for whatever a tour is pointing at.
    public var highlight = Color(red: 1.0, green: 0.78, blue: 0.35)
    /// Draw stars in a single red, for dark-adapted eyes.
    public var monochromeStars: Color?

    public init() {}

    /// Night-mode red: 6.2:1 against black, 5.1:1 at 90% opacity (WCAG AA needs 4.5:1).
    public static let nightRed = Color(red: 1.0, green: 0.27, blue: 0.2)

    /// Red on black, to keep night vision.
    public static let night: SkyStyle = {
        var s = SkyStyle()
        let red = SkyStyle.nightRed
        s.background = .black
        s.ground = Color(red: 0.06, green: 0, blue: 0)
        s.line = red.opacity(0.35)
        s.label = red
        s.muted = red.opacity(0.9)
        s.moonLight = red
        s.highlight = red
        s.moonDark = Color(red: 0.12, green: 0, blue: 0)
        s.planet = red
        s.monochromeStars = red
        return s
    }()

    /// Star tint from B−V colour index, kept pale.
    func starColor(_ bv: Double) -> Color {
        if let monochromeStars { return monochromeStars }
        let t = min(max((bv + 0.3) / 2.0, 0), 1)
        return Color(red: 0.80 + 0.20 * t, green: 0.86 - 0.06 * t, blue: 1.0 - 0.32 * t)
    }
}

/// Something to draw attention to, e.g. the current stop of a guided tour.
public enum SkyHighlight: Sendable, Equatable {
    /// IAU abbreviation.
    case constellation(String)
    /// Bright Star Catalogue HR number.
    case star(Int)
    case body(Body)
}

public struct SkyView: View {
    public var scene: SkyScene
    public var centerAzimuth: Double
    public var centerAltitude: Double
    public var fieldOfView: Double
    public var style: SkyStyle
    /// Figures to draw instead of the IAU constellation lines.
    public var culture: SkyCulture?
    public var highlight: SkyHighlight?
    /// Called after each draw with the time the draw took.
    public var onDraw: (@Sendable (Duration) -> Void)?

    public init(scene: SkyScene, centerAzimuth: Double = 180, centerAltitude: Double = 55, fieldOfView: Double = 110, style: SkyStyle = SkyStyle(), culture: SkyCulture? = nil, highlight: SkyHighlight? = nil, onDraw: (@Sendable (Duration) -> Void)? = nil) {
        self.scene = scene
        self.style = style
        self.culture = culture
        self.highlight = highlight
        self.centerAzimuth = centerAzimuth
        self.centerAltitude = centerAltitude
        self.fieldOfView = fieldOfView
        self.onDraw = onDraw
    }

    public var body: some View {
        Canvas { context, size in
            let start = ContinuousClock.now
            let p = Projection(centerAzimuth: centerAzimuth, centerAltitude: centerAltitude, fieldOfView: fieldOfView, size: size)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(style.background))
            drawConstellations(&context, p)
            drawStars(&context, p)
            drawBodies(&context, p)
            if let highlight { drawHighlight(highlight, &context, p) }
            drawHorizon(&context, p, size: size)
            onDraw?(ContinuousClock.now - start)
        }
    }

    func drawConstellations(_ context: inout GraphicsContext, _ p: Projection) {
        if let culture {
            drawCulture(culture, &context, p)
            return
        }
        var path = Path()
        for c in Catalog.constellations {
            for line in c.lines {
                for (a, b) in zip(line, line.dropFirst()) {
                    guard let ha = scene.starsByHR[a], let hb = scene.starsByHR[b],
                          ha.altitude > -5 || hb.altitude > -5,
                          let pa = p.point(ha), let pb = p.point(hb) else { continue }
                    path.move(to: pa)
                    path.addLine(to: pb)
                }
            }
        }
        context.stroke(path, with: .color(style.line), lineWidth: 0.6)
    }

    /// A culture's figures, named at the middle of their visible stars once zoomed in
    /// (closer for cultures with many small figures).
    func drawCulture(_ culture: SkyCulture, _ context: inout GraphicsContext, _ p: Projection) {
        var path = Path()
        let labelBelow = culture.constellations.count > 60 ? 60.0 : 110.0
        for figure in culture.constellations {
            var points: [CGPoint] = []
            for line in figure.lines {
                for (a, b) in zip(line, line.dropFirst()) {
                    guard let ha = scene.starsByHR[a], let hb = scene.starsByHR[b],
                          ha.altitude > -5 || hb.altitude > -5,
                          let pa = p.point(ha), let pb = p.point(hb) else { continue }
                    path.move(to: pa)
                    path.addLine(to: pb)
                    points += [pa, pb]
                }
            }
            if fieldOfView <= labelBelow, points.count > 1 {
                let c = CGPoint(x: points.map(\.x).reduce(0, +) / Double(points.count), y: points.map(\.y).reduce(0, +) / Double(points.count))
                context.draw(Text(figure.name).font(.caption2).foregroundStyle(style.muted), at: c)
            }
        }
        context.stroke(path, with: .color(style.line), lineWidth: 0.6)
    }

    /// A constellation's IAU lines drawn bright and thick; a star or body ringed.
    func drawHighlight(_ h: SkyHighlight, _ context: inout GraphicsContext, _ p: Projection) {
        func ring(_ position: Horizontal?, radius: Double) {
            guard let position, let pt = p.point(position) else { return }
            context.stroke(Path(ellipseIn: CGRect(x: pt.x - radius, y: pt.y - radius, width: 2 * radius, height: 2 * radius)),
                           with: .color(style.highlight), lineWidth: 2)
        }
        switch h {
        case .star(let hr):
            ring(scene.starsByHR[hr], radius: 14)
        case .body(let body):
            ring(scene.bodies.first { $0.body == body }?.position, radius: 18)
        case .constellation(let id):
            guard let figure = Catalog.constellations.first(where: { $0.id == id }) else { return }
            var path = Path()
            for line in figure.lines {
                for (a, b) in zip(line, line.dropFirst()) {
                    guard let ha = scene.starsByHR[a], let hb = scene.starsByHR[b],
                          let pa = p.point(ha), let pb = p.point(hb) else { continue }
                    path.move(to: pa)
                    path.addLine(to: pb)
                }
            }
            context.stroke(path, with: .color(style.highlight.opacity(0.9)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }

    func drawStars(_ context: inout GraphicsContext, _ p: Projection) {
        for s in scene.stars where s.position.altitude > 0 {
            guard let pt = p.point(s.position) else { continue }
            let r = max(0.3, 2.6 - 0.42 * s.star.magnitude)
            let opacity = min(1, max(0.25, 1.15 - 0.13 * s.star.magnitude))
            context.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: 2 * r, height: 2 * r)), with: .color(style.starColor(s.star.colorIndex).opacity(opacity)))
        }
    }

    func drawBodies(_ context: inout GraphicsContext, _ p: Projection) {
        // Naked-eye bodies only; Neptune (about mag 7.8) is left out.
        for b in scene.bodies where b.position.altitude > 0 && b.magnitude <= 6 {
            guard let pt = p.point(b.position) else { continue }
            if b.body == .moon {
                drawMoon(&context, at: pt, radius: 14, fraction: b.phaseFraction, waxing: scene.moonPhase < 180)
                label(&context, "Moon \(Int((b.phaseFraction * 100).rounded()))%", at: CGPoint(x: pt.x - 20, y: pt.y), anchor: .trailing)
            } else {
                let r = max(2.0, 3.6 - 0.35 * b.magnitude)
                context.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: 2 * r, height: 2 * r)), with: .color(style.planet))
                // Label to the right, or to the left when it would run off the edge (large text sizes).
                let name = b.body.rawValue.capitalized
                let width = context.resolve(Text(name).font(.caption2)).measure(in: p.size).width
                let side: Double = pt.x + r + 18 + width > p.size.width ? -1 : 1
                var tick = Path()
                tick.move(to: CGPoint(x: pt.x + side * (r + 3), y: pt.y))
                tick.addLine(to: CGPoint(x: pt.x + side * (r + 15), y: pt.y))
                context.stroke(tick, with: .color(style.muted), lineWidth: 0.6)
                label(&context, name, at: CGPoint(x: pt.x + side * (r + 18), y: pt.y), anchor: side > 0 ? .leading : .trailing)
            }
        }
    }

    func drawMoon(_ context: inout GraphicsContext, at c: CGPoint, radius r: Double, fraction: Double, waxing: Bool) {
        let disc = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        context.fill(Path(ellipseIn: disc), with: .color(style.moonDark))
        context.fill(Path.moonLit(center: c, radius: r, fraction: fraction, waxing: waxing), with: .color(style.moonLight))
    }

    func drawHorizon(_ context: inout GraphicsContext, _ p: Projection, size: CGSize) {
        var edge: [CGPoint] = []
        var az = centerAzimuth - fieldOfView
        while az <= centerAzimuth + fieldOfView {
            if let pt = p.point(Horizontal(altitude: 0, azimuth: az)) { edge.append(pt) }
            az += 1
        }
        guard let first = edge.first, let last = edge.last else { return }
        var ground = Path()
        ground.move(to: first)
        for pt in edge.dropFirst() { ground.addLine(to: pt) }
        ground.addLine(to: CGPoint(x: last.x, y: size.height + 10))
        ground.addLine(to: CGPoint(x: first.x, y: size.height + 10))
        ground.closeSubpath()
        context.fill(ground, with: .color(style.ground))
        for (name, az) in [("N", 0.0), ("NE", 45.0), ("E", 90.0), ("SE", 135.0), ("S", 180.0), ("SW", 225.0), ("W", 270.0), ("NW", 315.0)] {
            guard let pt = p.point(Horizontal(altitude: 0, azimuth: az)), pt.x > 0, pt.x < size.width else { continue }
            label(&context, name, at: CGPoint(x: pt.x, y: pt.y + 18), anchor: .center, color: style.muted)
        }
    }

    func label(_ context: inout GraphicsContext, _ text: String, at point: CGPoint, anchor: UnitPoint, color: Color? = nil) {
        let t = Text(text).font(.caption2).foregroundStyle(color ?? style.label)
        context.draw(t, at: point, anchor: anchor)
    }
}

extension Path {
    /// The lit part of the moon's disc: a half disc plus or minus the terminator ellipse.
    /// Waxing is lit on the right, as seen from the northern hemisphere.
    public static func moonLit(center c: CGPoint, radius r: Double, fraction: Double, waxing: Bool) -> Path {
        let side: Double = waxing ? 1 : -1
        var lit = Path()
        lit.move(to: CGPoint(x: c.x, y: c.y - r))
        lit.addArc(center: c, radius: r, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: side < 0)
        lit.addEllipseArc(center: c, rx: r * abs(1 - 2 * fraction), ry: r, gibbous: fraction > 0.5, side: side)
        lit.closeSubpath()
        return lit
    }

    /// Half of the terminator ellipse, from the moon's bottom to its top.
    mutating func addEllipseArc(center c: CGPoint, rx: Double, ry: Double, gibbous: Bool, side: Double) {
        // Gibbous: terminator bulges into the dark half; crescent: into the lit half.
        let direction = gibbous ? -side : side
        let steps = 24
        for i in 0...steps {
            let a = Double.pi / 2 - Double.pi * Double(i) / Double(steps)
            addLine(to: CGPoint(x: c.x + direction * rx * cos(a), y: c.y + ry * sin(a)))
        }
    }
}
