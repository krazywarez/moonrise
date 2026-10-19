import Feeds
import Library
import RealityKit
import SkyEngine
import SwiftUI
import UIKit

/// How distances and sizes are drawn in the 3D solar system.
enum SolarScale: String, CaseIterable, Identifiable {
    /// Distances raised to the power 0.4 and sizes enlarged, so everything fits and can be seen.
    case compressed
    /// Distances and sizes both true (1 AU = 1 scene metre); planets need markers to be found.
    case trueScale
    var id: String { rawValue }
    var name: String { self == .compressed ? "Compressed" : "True scale" }
}

/// One of the Sun's planets, with what the scene needs to draw it.
struct SolarPlanet: Identifiable, Sendable {
    var id: String
    var body: Body?
    var radiusKm: Double
    var color: String
    var tiltDeg: Double
    var periodDays: Double

    static let all: [SolarPlanet] = [
        ("mercury", Body.mercury, 88.0), ("venus", .venus, 224.7), ("earth", nil, 365.25), ("mars", .mars, 687.0),
        ("jupiter", .jupiter, 4332.6), ("saturn", .saturn, 10_759.2), ("uranus", .uranus, 30_688.5), ("neptune", .neptune, 60_182.0),
    ].compactMap { id, body, period in
        guard let d = Library.page(id: id)?.drawing else { return nil }
        return SolarPlanet(id: id, body: body, radiusKm: d.radiusKm ?? 6371, color: d.color ?? "#cccccc", tiltDeg: d.axialTiltDeg ?? 0, periodDays: period)
    }

    /// Heliocentric position on J2000 ecliptic axes, AU.
    func position(at date: Date) -> SIMD3<Double> {
        if let body { return (try? SkyEngine.heliocentricEcliptic(body, at: date)) ?? .zero }
        return (try? SkyEngine.heliocentricEarth(at: date)) ?? .zero
    }
}

/// Maps ecliptic AU to scene metres (y up) and gives drawn radii for each scale.
struct SolarMapping {
    var scale: SolarScale

    static let auKm = 1.495978707e8
    static let sunRadiusKm = 695_700.0

    func point(_ v: SIMD3<Double>) -> SIMD3<Float> {
        let r = (v * v).sum().squareRoot()
        guard r > 0 else { return .zero }
        let d = scale == .compressed ? 1.6 * pow(r, 0.4) : r
        let u = v / r * d
        return SIMD3(Float(u.x), Float(u.z), Float(-u.y))
    }

    func radius(km: Double) -> Float {
        scale == .compressed ? Float(0.09 * pow(km / 6371, 0.45)) : Float(km / Self.auKm)
    }

    var sunRadius: Float { scale == .compressed ? 0.35 : Float(Self.sunRadiusKm / Self.auKm) }
}

/// Orbit camera around a target point.
struct SolarCamera: Equatable {
    var target: SIMD3<Float> = .zero
    var yaw: Float = 0.4
    var pitch: Float = 0.55
    var distance: Float = 14
    static let fovDegrees: Float = 50

    var position: SIMD3<Float> {
        target + distance * SIMD3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
    }

    /// Screen position of a scene point, or nil if it is behind the camera.
    func project(_ p: SIMD3<Float>, in size: CGSize) -> CGPoint? {
        let pos = position
        let f = simd_normalize(target - pos)
        let r = simd_normalize(simd_cross(f, SIMD3(0, 1, 0)))
        let u = simd_cross(r, f)
        let v = p - pos
        let z = simd_dot(v, f)
        guard z > 0 else { return nil }
        let k = Float(size.height / 2) / tan(Self.fovDegrees * .pi / 360)
        return CGPoint(x: size.width / 2 + CGFloat(simd_dot(v, r) / z * k), y: size.height / 2 - CGFloat(simd_dot(v, u) / z * k))
    }

    func distance(to p: SIMD3<Float>) -> Float { simd_length(p - position) }
}

/// The live space weather the scene shows: a flare on the Sun and an aurora ring on Earth.
struct SolarWeather: Equatable {
    var kp: Double?
    /// Strongest X-ray flux in the last three hours and when it peaked.
    var flare: (flux: Double, time: Date)?

    static func == (a: SolarWeather, b: SolarWeather) -> Bool { a.kp == b.kp && a.flare?.flux == b.flare?.flux }

    var showsFlare: Bool { (flare?.flux ?? 0) >= 1e-5 }
    var showsAurora: Bool { (kp ?? 0) >= 4 }

    var summary: String {
        var parts: [String] = []
        if let f = flare {
            parts.append(showsFlare
                ? "\(XRay.flareClass(f.flux)) solar flare at \(f.time.formatted(date: .omitted, time: .shortened))"
                : "No large flares in the last 3 h (peak \(XRay.flareClass(f.flux)))")
        }
        if let kp {
            parts.append(showsAurora
                ? String(format: "Kp %.1f: aurora ring around Earth's poles", kp)
                : String(format: "Kp %.1f: geomagnetic field quiet", kp))
        }
        return parts.isEmpty ? "Loading space weather" : parts.joined(separator: " · ")
    }
}

/// Entities created once and moved on each update.
@MainActor
final class SolarSceneEntities {
    let root = Entity()
    let camera = PerspectiveCamera()
    let sun = ModelEntity()
    var planets: [String: ModelEntity] = [:]
    var nights: [String: ModelEntity] = [:]
    var orbits: [String: ModelEntity] = [:]
    var orbitsBuilt: (SolarScale, Float)?
    let flare = ModelEntity()
    let aurora = Entity()
}

struct SolarSystem3DView: View {
    var date: Date
    var live: Bool
    @Binding var scale: SolarScale
    var ink: Color
    var accent: Color
    var onOpen: (LibraryPage) -> Void

    @State private var entities = SolarSceneEntities()
    @State private var cam = SolarCamera()
    @State private var dragStart: SolarCamera?
    @State private var pinchStart: Float?
    @State private var selected: String?
    @State private var weather = SolarWeather()
    @State private var flight: Task<Void, Never>?
    @State private var pulse = false
    @State private var viewSize = CGSize(width: 400, height: 600)

    private var mapping: SolarMapping { SolarMapping(scale: scale) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RealityView { content in
                    content.camera = .virtual
                    build(content)
                } update: { _ in
                    place()
                }
                .gesture(dragGesture.simultaneously(with: pinchGesture))
                .onTapGesture(coordinateSpace: .local) { tap($0, size: geo.size) }

                labels(size: geo.size).allowsHitTesting(false)

                VStack(spacing: 8) {
                    if let s = selected, let planet = planetOrSun(s) { card(planet) }
                    Spacer()
                    Text(live ? weather.summary : "Live space weather is shown only for today.")
                        .font(.caption2).dimmed(0.75)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.black.opacity(0.6), in: Capsule())
                }
                .padding(12)
            }
            .clipped()
            .onAppear { viewSize = geo.size; cam.distance = fitDistance() }
            .onChange(of: geo.size) { viewSize = geo.size }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("3D solar system. Drag to turn, pinch to zoom, tap a planet to learn about it.")
        .onChange(of: scale) { resetView() }
        .task { await loadWeather() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(700))
                pulse.toggle()
            }
        }
    }

    // MARK: Scene

    private func build(_ content: RealityViewCameraContent) {
        let e = entities
        content.add(e.root)
        e.camera.camera.fieldOfViewInDegrees = SolarCamera.fovDegrees
        e.root.addChild(e.camera)

        var sunMaterial = UnlitMaterial(color: UIColor(red: 1, green: 0.86, blue: 0.5, alpha: 1))
        if let url = Bundle.main.url(forResource: "sun", withExtension: "jpg", subdirectory: "Globes"), let t = try? TextureResource.load(contentsOf: url) {
            sunMaterial.color = .init(tint: .white, texture: .init(t))
        }
        e.sun.model = ModelComponent(mesh: .generateSphere(radius: 1), materials: [sunMaterial])
        e.root.addChild(e.sun)
        // Glow: nested translucent shells, fainter outward.
        for i in 1...10 {
            let r = 1 + Float(i) * 0.07
            let a = CGFloat(0.09 * pow(0.78, Double(i - 1)))
            var g = UnlitMaterial(color: UIColor(red: 1, green: 0.72, blue: 0.32, alpha: a))
            g.blending = .transparent(opacity: .init(floatLiteral: Float(a)))
            let shell = ModelEntity(mesh: .generateSphere(radius: r), materials: [g])
            e.sun.addChild(shell)
        }


        for p in SolarPlanet.all {
            let planet = ModelEntity()
            // Unlit, with a night-side shell turned away from the Sun, so day and night are exact
            // without depending on scene lighting.
            var m = UnlitMaterial()
            if let url = GlobeView.mapURL(p.id), let texture = try? TextureResource.load(contentsOf: url) {
                m.color = .init(texture: .init(texture))
            } else {
                m.color = .init(tint: UIColor(Color(hex: p.color) ?? .gray))
            }
            planet.model = ModelComponent(mesh: .generateSphere(radius: 1), materials: [m])
            let night = Self.nightShell()
            night.name = "night"
            e.nights[p.id] = night
            e.root.addChild(night)
            planet.orientation = simd_quatf(angle: Float(p.tiltDeg * .pi / 180), axis: [1, 0, 0])
            if p.id == "saturn" { planet.addChild(Self.rings(inner: 1.24, outer: 2.27)) }
            e.planets[p.id] = planet
            e.root.addChild(planet)
        }

        var flareMaterial = UnlitMaterial(color: UIColor(red: 1, green: 1, blue: 0.85, alpha: 0.9))
        flareMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.9))
        e.flare.model = ModelComponent(mesh: .generateSphere(radius: 1), materials: [flareMaterial])
        e.root.addChild(e.flare)
        // Two faint bands per pole, a wider glow and a brighter core, just above the surface.
        for y: Float in [0.86, -0.86] {
            for (inner, outer, alpha) in [(0.36, 0.66, 0.22), (0.45, 0.56, 0.5)] as [(Float, Float, CGFloat)] {
                let ring = Self.annulus(inner: inner, outer: outer, color: UIColor(red: 0.35, green: 1, blue: 0.55, alpha: alpha))
                ring.position.y = y * 1.02
                e.aurora.addChild(ring)
            }
        }
        e.planets["earth"]?.addChild(e.aurora)
        place()
    }

    /// Moves everything for the current date, scale and camera.
    private func place() {
        let e = entities
        let map = mapping
        e.sun.scale = .init(repeating: map.sunRadius)
        for p in SolarPlanet.all {
            guard let planet = e.planets[p.id] else { continue }
            planet.position = map.point(p.position(at: date))
            planet.scale = .init(repeating: map.radius(km: p.radiusKm))
            if let night = e.nights[p.id] {
                night.position = planet.position
                night.scale = .init(repeating: map.radius(km: p.radiusKm) * 1.004)
                // The shell's open side (+y) faces the Sun.
                let toSun = simd_normalize(-planet.position)
                night.orientation = simd_quatf(from: SIMD3(0, 1, 0), to: toSun)
            }
        }
        rebuildOrbitsIfNeeded()
        // Orbits are a guide at system scale; close to a planet they only cut across it.
        let farEnough = cam.distance > map.radius(km: 70_000) * 25
        for o in e.orbits.values { o.isEnabled = farEnough }

        // Flare: a bright bulge on the side of the Sun facing Earth, pulsing.
        if live, weather.showsFlare, let earth = e.planets["earth"] {
            e.flare.isEnabled = true
            let dir = simd_normalize(earth.position)
            e.flare.position = dir * map.sunRadius * 1.02
            e.flare.scale = .init(repeating: map.sunRadius * (pulse ? 0.22 : 0.16))
        } else {
            e.flare.isEnabled = false
        }
        e.aurora.isEnabled = live && weather.showsAurora

        e.camera.look(at: cam.target, from: cam.position, relativeTo: nil)
        e.camera.camera.near = max(cam.distance * 0.001, 1e-9)
        e.camera.camera.far = cam.distance * 100 + 200
    }

    /// Orbit ribbons, rebuilt when the scale changes or the zoom changes enough that their width would look wrong.
    private func rebuildOrbitsIfNeeded() {
        let e = entities
        let width = cam.distance * 0.0022
        if let (s, w) = e.orbitsBuilt, s == scale, w / width < 1.6, width / w < 1.6 { return }
        e.orbitsBuilt = (scale, width)
        let map = mapping
        for p in SolarPlanet.all {
            let steps = 240
            let points = (0..<steps).map { i in
                map.point(p.position(at: date.addingTimeInterval(Double(i) / Double(steps) * p.periodDays * 86_400)))
            }
            let ribbon = Self.ribbon(points, width: width)
            if let existing = e.orbits[p.id] {
                existing.model?.mesh = ribbon
            } else {
                var m = UnlitMaterial(color: UIColor(white: 1, alpha: 1))
                m.blending = .transparent(opacity: .init(floatLiteral: 0.22))
                m.faceCulling = .none
                let orbit = ModelEntity(mesh: ribbon, materials: [m])
                e.orbits[p.id] = orbit
                e.root.addChild(orbit)
            }
        }
    }

    // MARK: Meshes

    /// A closed flat ribbon through `points`, lying in the plane of the orbit.
    private static func ribbon(_ points: [SIMD3<Float>], width: Float) -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        let n = points.count
        for i in 0..<n {
            let t = simd_normalize(points[(i + 1) % n] - points[(i + n - 1) % n])
            var side = simd_cross(t, SIMD3(0, 1, 0))
            if simd_length(side) < 1e-6 { side = SIMD3(1, 0, 0) }
            side = simd_normalize(side) * width / 2
            positions += [points[i] - side, points[i] + side]
            let a = UInt32(2 * i), b = UInt32(2 * ((i + 1) % n))
            indices += [a, a + 1, b, b, a + 1, b + 1]
        }
        var d = MeshDescriptor(name: "orbit")
        d.positions = MeshBuffer(positions)
        d.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [d])) ?? .generateBox(size: 0.001)
    }

    /// A flat ring in the local x-z plane, radii in units of the parent's radius.
    private static func annulus(inner: Float, outer: Float, color: UIColor) -> ModelEntity {
        let n = 96
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for i in 0..<n {
            let a = Float(i) / Float(n) * 2 * .pi
            positions += [SIMD3(cos(a) * inner, 0, sin(a) * inner), SIMD3(cos(a) * outer, 0, sin(a) * outer)]
            let p = UInt32(2 * i), q = UInt32(2 * ((i + 1) % n))
            indices += [p, p + 1, q, q, p + 1, q + 1]
        }
        var d = MeshDescriptor(name: "ring")
        d.positions = MeshBuffer(positions)
        d.primitives = .triangles(indices)
        var m = UnlitMaterial(color: color)
        m.blending = .transparent(opacity: .init(floatLiteral: Float(color.cgColor.alpha)))
        m.faceCulling = .none
        return ModelEntity(mesh: (try? MeshResource.generate(from: [d])) ?? .generateBox(size: 0.001), materials: [m])
    }

    /// The half of a unit sphere below y = 0, drawn dark and mostly opaque over the planet's night side.
    private static func nightShell() -> ModelEntity {
        let rings = 24, segments = 64
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for i in 0...rings {
            let lat = -Float.pi / 2 * Float(i) / Float(rings)
            for j in 0...segments {
                let lon = Float(j) / Float(segments) * 2 * .pi
                positions.append(SIMD3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)))
            }
        }
        for i in 0..<rings {
            for j in 0..<segments {
                let a = UInt32(i * (segments + 1) + j), b = a + UInt32(segments + 1)
                indices += [a, b, a + 1, a + 1, b, b + 1]
            }
        }
        var d = MeshDescriptor(name: "night")
        d.positions = MeshBuffer(positions)
        d.primitives = .triangles(indices)
        var m = UnlitMaterial(color: .black)
        m.blending = .transparent(opacity: .init(floatLiteral: 0.88))
        m.faceCulling = .none
        return ModelEntity(mesh: (try? MeshResource.generate(from: [d])) ?? .generateBox(size: 0.001), materials: [m])
    }

    private static func rings(inner: Float, outer: Float) -> ModelEntity {
        annulus(inner: inner, outer: outer, color: UIColor(red: 0.85, green: 0.78, blue: 0.62, alpha: 0.7))
    }

    // MARK: Labels, taps and the card

    private func screenPoints(size: CGSize) -> [(id: String, point: CGPoint, radius: CGFloat)] {
        let e = entities
        var out: [(String, CGPoint, CGFloat)] = []
        if let p = cam.project(.zero, in: size) { out.append(("sun", p, pixelRadius(mapping.sunRadius, at: .zero, size: size))) }
        for planet in SolarPlanet.all {
            guard let entity = e.planets[planet.id] else { continue }
            let pos = mapping.point(planet.position(at: date))
            if let p = cam.project(pos, in: size) {
                out.append((planet.id, p, pixelRadius(mapping.radius(km: planet.radiusKm), at: pos, size: size)))
            }
            _ = entity
        }
        return out
    }

    private func pixelRadius(_ r: Float, at p: SIMD3<Float>, size: CGSize) -> CGFloat {
        let k = Float(size.height / 2) / tan(SolarCamera.fovDegrees * .pi / 360)
        return CGFloat(r / max(cam.distance(to: p), 1e-9) * k)
    }

    /// Points to label: larger bodies first, skipping a label that would sit on one already placed.
    private func labelled(size: CGSize) -> [(id: String, point: CGPoint, radius: CGFloat, showName: Bool)] {
        let order = ["sun", "jupiter", "saturn", "uranus", "neptune", "earth", "venus", "mars", "mercury"]
        var placed: [CGPoint] = []
        return screenPoints(size: size)
            .sorted { (order.firstIndex(of: $0.id) ?? 99) < (order.firstIndex(of: $1.id) ?? 99) }
            .map { item in
                let at = CGPoint(x: item.point.x, y: item.point.y - max(item.radius, 5) - 9)
                let clear = item.id == selected || placed.allSatisfy { abs($0.x - at.x) > 44 || abs($0.y - at.y) > 14 }
                if clear { placed.append(at) }
                return (item.id, item.point, item.radius, clear)
            }
    }

    private func labels(size: CGSize) -> some View {
        ZStack {
            ForEach(labelled(size: size), id: \.id) { item in
                let name = item.id == "sun" ? "Sun" : (Library.page(id: item.id)?.title ?? item.id)
                let tiny = item.radius < 3
                ZStack {
                    if tiny {
                        Circle().stroke(item.id == selected ? accent : ink.opacity(0.7), lineWidth: 1.2).frame(width: 10, height: 10)
                    }
                    if item.showName {
                    Text(name).font(.caption2.weight(item.id == selected ? .semibold : .regular))
                        .foregroundStyle(item.id == selected ? accent : ink.opacity(0.85))
                        .shadow(color: .black, radius: 2)
                        .offset(y: -max(item.radius, 5) - 9)
                    }
                }
                .position(item.point)
            }
        }
    }

    private func tap(_ location: CGPoint, size: CGSize) {
        let hit = screenPoints(size: size)
            .map { ($0.id, hypot($0.point.x - location.x, $0.point.y - location.y) - max($0.radius, 0)) }
            .filter { $0.1 < 28 }
            .min { $0.1 < $1.1 }
        guard let id = hit?.0 else { selected = nil; return }
        selected = id
        fly(to: id)
    }

    private func planetOrSun(_ id: String) -> LibraryPage? { Library.page(id: id) }

    private func card(_ page: LibraryPage) -> some View {
        let planet = SolarPlanet.all.first { $0.id == page.id }
        let au = planet.map { p -> Double in let v = p.position(at: date); return (v * v).sum().squareRoot() }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(page.title).font(.headline)
                Spacer()
                Button { selected = nil; resetView() } label: {
                    Image(systemName: "xmark").font(.footnote.weight(.semibold)).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(-12)
                .accessibilityLabel("Close")
            }
            Text(page.subtitle).font(.footnote).dimmed(0.75)
            if let au {
                Text(String(format: "%.2f AU from the Sun · sunlight takes %@", au, lightTime(au))).font(.footnote.monospacedDigit()).dimmed(0.85)
            }
            Button("Read more") { onOpen(page) }.font(.subheadline.weight(.medium)).foregroundStyle(accent)
        }
        .padding(14)
        .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ink.opacity(0.15), lineWidth: 0.5))
    }

    private func lightTime(_ au: Double) -> String {
        let s = au * 499.004784
        let h = Int(s / 3600), m = Int(s.truncatingRemainder(dividingBy: 3600) / 60)
        return h > 0 ? "\(h) h \(m) min" : "\(m) min"
    }

    // MARK: Camera

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { g in
                flight?.cancel()
                if dragStart == nil { dragStart = cam }
                cam.yaw = dragStart!.yaw - Float(g.translation.width) * 0.008
                cam.pitch = min(max(dragStart!.pitch + Float(g.translation.height) * 0.008, -1.45), 1.45)
            }
            .onEnded { _ in dragStart = nil }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { g in
                flight?.cancel()
                if pinchStart == nil { pinchStart = cam.distance }
                let limits: ClosedRange<Float> = scale == .compressed ? 0.25...60 : 1e-6...200
                cam.distance = min(max(pinchStart! / Float(g.magnification), limits.lowerBound), limits.upperBound)
            }
            .onEnded { _ in pinchStart = nil }
    }

    private func resetView() {
        animateCamera(to: SolarCamera(target: .zero, yaw: cam.yaw, pitch: 0.55, distance: fitDistance()))
    }

    /// Camera distance at which Neptune's orbit fits the narrower side of the view.
    private func fitDistance() -> Float {
        let neptune = Float(mapping.scale == .compressed ? 1.6 * pow(30.1, 0.4) : 30.1)
        let tanV = tan(SolarCamera.fovDegrees * .pi / 360)
        let tanH = tanV * Float(viewSize.width / max(viewSize.height, 1))
        return neptune * 1.22 / min(tanV, tanH)
    }

    /// Centres on a body and zooms to a few times its drawn radius.
    private func fly(to id: String) {
        let target: SIMD3<Float>, radius: Float
        if id == "sun" {
            target = .zero
            radius = mapping.sunRadius
        } else if let p = SolarPlanet.all.first(where: { $0.id == id }) {
            target = mapping.point(p.position(at: date))
            radius = mapping.radius(km: p.radiusKm) * (p.id == "saturn" ? 2.3 : 1)
        } else { return }
        animateCamera(to: SolarCamera(target: target, yaw: cam.yaw, pitch: max(cam.pitch, 0.25), distance: radius * 7))
    }

    /// Moves the camera over about a second, interpolating distance on a log scale.
    private func animateCamera(to end: SolarCamera) {
        flight?.cancel()
        let start = cam
        flight = Task {
            let frames = 50
            for f in 1...frames {
                try? await Task.sleep(for: .milliseconds(18))
                if Task.isCancelled { return }
                let x = Float(f) / Float(frames)
                let t = x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
                cam.target = start.target + (end.target - start.target) * t
                cam.pitch = start.pitch + (end.pitch - start.pitch) * t
                cam.distance = exp(Foundation.log(start.distance) + (Foundation.log(end.distance) - Foundation.log(start.distance)) * t)
            }
        }
    }

    // MARK: Weather

    private func loadWeather() async {
        while !Task.isCancelled {
            async let kp = try? SpaceWeather.fetch()
            async let xray = try? XRay.fetch()
            let (k, x) = await (kp, xray)
            var w = SolarWeather(kp: k?.kpNow)
            if let samples = x {
                let recent = samples.filter { $0.time > .now.addingTimeInterval(-3 * 3600) }
                if let peak = recent.max(by: { $0.flux < $1.flux }) { w.flare = (peak.flux, peak.time) }
            }
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "debugSolarEvents") { w.kp = 6.3; w.flare = (2.4e-5, .now) }
            #endif
            weather = w
            try? await Task.sleep(for: .seconds(600))
        }
    }
}
