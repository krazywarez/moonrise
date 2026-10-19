import Feeds
import Library
import RealityKit
import SkyEngine
import SkyRenderer
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

    /// Pluto, which Astronomy Engine covers, drawn with the dwarf planets.
    static let pluto: SolarPlanet? = Library.page(id: "pluto")?.drawing.map {
        SolarPlanet(id: "pluto", body: .pluto, radiusKm: $0.radiusKm ?? 1188, color: $0.color ?? "#cdb79e", tiltDeg: $0.axialTiltDeg ?? 0, periodDays: 90_560)
    }

    /// Heliocentric position on J2000 ecliptic axes, AU.
    func position(at date: Date) -> SIMD3<Double> {
        if let body { return (try? SkyEngine.heliocentricEcliptic(body, at: date)) ?? .zero }
        return (try? SkyEngine.heliocentricEarth(at: date)) ?? .zero
    }
}

/// A moon from its Library page: exact positions for Earth's Moon and Jupiter's four big moons,
/// a circular orbit in the planet's equator plane (at an arbitrary starting point) for the rest.
struct SolarMoon: Identifiable, Sendable {
    var id: String
    var parent: String
    var distanceKm: Double
    var periodDays: Double
    var radiusKm: Double
    var color: String

    static let galilean = ["io", "europa", "ganymede", "callisto"]

    static let all: [SolarMoon] = Library.pages(in: .moons).compactMap { p in
        guard let dist = p.facts.first(where: { $0.label.hasPrefix("Mean distance from") }),
              let period = p.facts.first(where: { $0.label.hasPrefix("Orbital period") }),
              let km = number(dist.value), let days = number(period.value) else { return nil }
        let parent = dist.label.replacingOccurrences(of: "Mean distance from ", with: "").lowercased()
        let retrograde = p.facts.contains { $0.value == "Retrograde" }
        return SolarMoon(id: p.id, parent: parent, distanceKm: km, periodDays: retrograde ? -days : days,
                         radiusKm: p.drawing?.radiusKm ?? 100, color: p.drawing?.color ?? "#999999")
    }

    /// 1070400 from "1,070,400 km"; 0.319 from "0.319 days (7 h 39 m)".
    static func number(_ s: String) -> Double? {
        s.split(separator: " ").first.flatMap { Double($0.replacingOccurrences(of: ",", with: "")) }
    }

    var isExact: Bool { id == "moon" || Self.galilean.contains(id) }
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

    /// Ecliptic axes to scene axes without changing length.
    static func axes(_ v: SIMD3<Double>) -> SIMD3<Float> { SIMD3(Float(v.x), Float(v.z), Float(-v.y)) }

    func radius(km: Double) -> Float {
        scale == .compressed ? Float(0.09 * pow(km / 6371, 0.45)) : Float(km / Self.auKm)
    }

    /// How far from its planet a moon is drawn: log-squeezed in compressed scale, true otherwise.
    func moonDistance(km: Double, planetRadiusKm: Double) -> Float {
        scale == .compressed
            ? radius(km: planetRadiusKm) * Float(1.2 + 1.6 * log10(max(km / planetRadiusKm, 1.5)))
            : Float(km / Self.auKm)
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

/// Which optional layers are drawn.
struct SolarLayers: Equatable {
    var moons = true
    var dwarfs = true
    var craft = true
    var comets = true
}

/// Anything the scene draws and can label or fly to.
struct SolarMarker {
    enum Kind { case sun, planet, moon, dwarf, craft, comet }
    var id: String
    var name: String
    var kind: Kind
    var scene: SIMD3<Float>
    /// Drawn radius in scene units (for dots, the dot's size at the current zoom).
    var radius: Float
    var visible: Bool
}

/// Entities created once and moved on each update.
@MainActor
final class SolarSceneEntities {
    let root = Entity()
    let camera = PerspectiveCamera()
    let sun = ModelEntity()
    var bodies: [String: ModelEntity] = [:]
    var nights: [String: ModelEntity] = [:]
    var tails: [String: ModelEntity] = [:]
    var orbits: [String: ModelEntity] = [:]
    var orbitsBuilt: (SolarScale, Float)?
    var paths: [String: ModelEntity] = [:]
    var pathsBuilt: (SolarScale, Float, Int)?
    let debris = ModelEntity()
    var debrisBuilt: (SolarScale, Float, String)?
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
    @AppStorage("solar.moons") private var showMoons = true
    @AppStorage("solar.dwarfs") private var showDwarfs = true
    @AppStorage("solar.craft") private var showCraft = true
    @AppStorage("solar.comets") private var showComets = true

    private var mapping: SolarMapping { SolarMapping(scale: scale) }
    private var layers: SolarLayers { SolarLayers(moons: showMoons, dwarfs: showDwarfs, craft: showCraft, comets: showComets) }

    private static let mainComets: Set<String> = ["halley", "encke", "67p"]
    private static let craftColor = UIColor(red: 0.88, green: 0.24, blue: 0.19, alpha: 1)

    /// Meteor showers within a week of their peak, with a parent orbit to draw.
    private var activeShowers: [MeteorShower] {
        MeteorShower.major.filter { $0.parent != nil && abs($0.daysToPeak(from: date)) <= 7 }
    }

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
                    if let s = selected { card(s) }
                    Spacer()
                    HStack(alignment: .bottom) {
                        Text(summary)
                            .font(.caption2).dimmed(0.8)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                        Spacer(minLength: 8)
                        layerMenu
                    }
                }
                .padding(12)
            }
            .clipped()
            .onAppear { viewSize = geo.size; cam.distance = fitDistance() }
            .onChange(of: geo.size) { viewSize = geo.size }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("3D solar system. Drag to turn, pinch to zoom, tap a body to learn about it.")
        .onChange(of: scale) { resetView() }
        .task { await loadWeather() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(700))
                pulse.toggle()
            }
        }
    }

    private var summary: String {
        var lines: [String] = []
        if let s = activeShowers.first, let parent = KeplerOrbit.comets.first(where: { $0.id == s.parent }) {
            let d = s.daysToPeak(from: date)
            let when = abs(d) < 1 ? "peak today" : d > 0 ? "peak in \(Int(d.rounded())) days" : "peaked \(Int((-d).rounded())) days ago"
            lines.append("\(s.name) \(when): Earth is crossing debris from \(parent.name).")
        }
        lines.append(live ? weather.summary : "Live space weather is shown only for today.")
        return lines.joined(separator: "\n")
    }

    private var layerMenu: some View {
        Menu {
            Toggle("Moons", isOn: $showMoons)
            Toggle("Dwarf planets", isOn: $showDwarfs)
            Toggle("Spacecraft", isOn: $showCraft)
            Toggle("Comets and meteor showers", isOn: $showComets)
        } label: {
            Image(systemName: "square.3.layers.3d").font(.body).frame(width: 44, height: 44)
                .background(Color.black.opacity(0.7), in: Circle())
        }
        .accessibilityLabel("Layers")
    }

    // MARK: Markers

    /// Every body's scene position and drawn size for the current date, scale, layers and camera.
    private func markers() -> [SolarMarker] {
        let map = mapping
        var out: [SolarMarker] = [SolarMarker(id: "sun", name: "Sun", kind: .sun, scene: .zero, radius: map.sunRadius, visible: true)]
        var parents: [String: (scene: SIMD3<Float>, radiusKm: Double, tiltDeg: Double)] = [:]
        func dot(_ p: SIMD3<Float>) -> Float { cam.distance(to: p) * 0.006 }

        for p in SolarPlanet.all {
            let s = map.point(p.position(at: date))
            parents[p.id] = (s, p.radiusKm, p.tiltDeg)
            out.append(SolarMarker(id: p.id, name: Library.page(id: p.id)?.title ?? p.id, kind: .planet, scene: s, radius: map.radius(km: p.radiusKm), visible: true))
        }
        if let pluto = SolarPlanet.pluto {
            let s = map.point(pluto.position(at: date))
            parents["pluto"] = (s, pluto.radiusKm, pluto.tiltDeg)
            out.append(SolarMarker(id: "pluto", name: "Pluto", kind: .dwarf, scene: s, radius: map.radius(km: pluto.radiusKm), visible: layers.dwarfs))
        }
        for k in KeplerOrbit.dwarfPlanets {
            let r = Library.page(id: k.id)?.drawing?.radiusKm ?? 500
            out.append(SolarMarker(id: k.id, name: k.name, kind: .dwarf, scene: map.point(k.position(at: date)), radius: map.radius(km: r), visible: layers.dwarfs))
        }

        // Moons appear when the camera is near their planet (or the planet or moon is selected).
        let galilean = SkyEngine.galileanMoons(at: date)
        let jd = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        var reach: [String: Float] = [:]
        var moonMarkers: [SolarMarker] = []
        for m in SolarMoon.all {
            guard let parent = parents[m.parent] else { continue }
            let dist = map.moonDistance(km: m.distanceKm, planetRadiusKm: parent.radiusKm)
            reach[m.parent] = max(reach[m.parent] ?? 0, dist)
            var dir: SIMD3<Float>
            if m.id == "moon" {
                dir = simd_normalize(SolarMapping.axes(SkyEngine.geocentricMoonEcliptic(at: date)))
            } else if let i = SolarMoon.galilean.firstIndex(of: m.id) {
                dir = simd_normalize(SolarMapping.axes(galilean[i]))
            } else {
                let phase = Double(m.id.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 97) / 97
                let a = 2 * Double.pi * ((jd - 2_451_545) / m.periodDays + phase)
                let flat = SIMD3(Float(cos(a)), 0, Float(sin(a)))
                dir = simd_quatf(angle: Float(parent.tiltDeg * .pi / 180), axis: [1, 0, 0]).act(flat)
            }
            moonMarkers.append(SolarMarker(id: m.id, name: Library.page(id: m.id)?.title ?? m.id, kind: .moon,
                                           scene: parent.scene + dir * dist, radius: map.radius(km: m.radiusKm), visible: false))
        }
        for i in moonMarkers.indices {
            let m = SolarMoon.all.first { $0.id == moonMarkers[i].id }!
            guard let parent = parents[m.parent], let r = reach[m.parent] else { continue }
            let near = cam.distance(to: parent.scene) < r * 16
            let chosen = selected == m.id || selected == m.parent
            let parentShown = m.parent != "pluto" || layers.dwarfs
            moonMarkers[i].visible = layers.moons && parentShown && (near || chosen)
        }
        out += moonMarkers

        for craft in Spacecraft.all {
            guard let p = craft.position3(at: date) else { continue }
            let s = map.point(p)
            out.append(SolarMarker(id: "craft:\(craft.name)", name: craft.name, kind: .craft, scene: s, radius: dot(s), visible: layers.craft))
        }

        let showerParents = Set(activeShowers.compactMap(\.parent))
        for c in KeplerOrbit.comets {
            let s = map.point(c.position(at: date))
            let shown = layers.comets && (Self.mainComets.contains(c.id) || showerParents.contains(c.id))
            out.append(SolarMarker(id: "comet:\(c.id)", name: c.name, kind: .comet, scene: s, radius: dot(s), visible: shown))
        }
        return out
    }

    // MARK: Scene

    private func build(_ content: RealityViewCameraContent) {
        let e = entities
        content.add(e.root)
        e.camera.camera.fieldOfViewInDegrees = SolarCamera.fovDegrees
        e.root.addChild(e.camera)

        let sunMaterial = UnlitMaterial(color: UIColor(red: 1, green: 0.86, blue: 0.5, alpha: 1))
        e.sun.model = ModelComponent(mesh: .generateSphere(radius: 1), materials: [sunMaterial])
        e.root.addChild(e.sun)
        // Glow: nested translucent shells, fainter outward.
        for i in 1...10 {
            let r = 1 + Float(i) * 0.07
            let a = CGFloat(0.09 * pow(0.78, Double(i - 1)))
            var g = UnlitMaterial(color: UIColor(red: 1, green: 0.72, blue: 0.32, alpha: a))
            g.blending = .transparent(opacity: .init(floatLiteral: Float(a)))
            e.sun.addChild(ModelEntity(mesh: .generateSphere(radius: r), materials: [g]))
        }

        // Planets, dwarf planets and moons: textured where there is a map, with a night side.
        var spheres: [(id: String, color: String, tilt: Double)] = SolarPlanet.all.map { ($0.id, $0.color, $0.tiltDeg) }
        if let pluto = SolarPlanet.pluto { spheres.append(("pluto", pluto.color, pluto.tiltDeg)) }
        spheres += KeplerOrbit.dwarfPlanets.map { ($0.id, Library.page(id: $0.id)?.drawing?.color ?? "#999999", 0) }
        spheres += SolarMoon.all.map { ($0.id, $0.color, 0) }
        for s in spheres {
            let body = ModelEntity()
            // Plain colour first; the map, if there is one, is swapped in once it has loaded.
            let m = UnlitMaterial(color: UIColor(Color(hex: s.color) ?? .gray))
            body.model = ModelComponent(mesh: .generateSphere(radius: 1), materials: [m])
            body.orientation = simd_quatf(angle: Float(s.tilt * .pi / 180), axis: [1, 0, 0])
            if s.id == "saturn" { body.addChild(Self.annulus(inner: 1.24, outer: 2.27, color: UIColor(red: 0.85, green: 0.78, blue: 0.62, alpha: 0.7))) }
            e.bodies[s.id] = body
            e.root.addChild(body)
            let night = Self.nightShell()
            e.nights[s.id] = night
            e.root.addChild(night)
        }

        // Spacecraft and comet nuclei: dots sized each frame to stay visible.
        for craft in Spacecraft.all {
            let dot = ModelEntity(mesh: .generateSphere(radius: 1), materials: [UnlitMaterial(color: Self.craftColor)])
            e.bodies["craft:\(craft.name)"] = dot
            e.root.addChild(dot)
        }
        for c in KeplerOrbit.comets {
            let nucleus = ModelEntity(mesh: .generateSphere(radius: 1), materials: [UnlitMaterial(color: UIColor(white: 0.92, alpha: 1))])
            e.bodies["comet:\(c.id)"] = nucleus
            e.root.addChild(nucleus)
            // A soft tail: nested cones, wider and fainter outward.
            let tail = ModelEntity()
            for (radius, alpha) in [(0.025, 0.3), (0.06, 0.14), (0.11, 0.06)] as [(Float, Float)] {
                var t = UnlitMaterial(color: UIColor(red: 0.7, green: 0.88, blue: 1, alpha: 1))
                t.blending = .transparent(opacity: .init(floatLiteral: alpha))
                tail.addChild(ModelEntity(mesh: .generateCone(height: 1, radius: radius), materials: [t]))
            }
            e.tails[c.id] = tail
            e.root.addChild(tail)
        }

        var debrisMaterial = UnlitMaterial(color: UIColor(red: 1, green: 0.88, blue: 0.65, alpha: 0.55))
        debrisMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.55))
        debrisMaterial.faceCulling = .none
        e.debris.model = ModelComponent(mesh: .generateBox(size: 0.0001), materials: [debrisMaterial])
        e.root.addChild(e.debris)

        var flareMaterial = UnlitMaterial(color: UIColor(red: 1, green: 1, blue: 0.85, alpha: 0.9))
        flareMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.9))
        e.flare.model = ModelComponent(mesh: .generateSphere(radius: 1), materials: [flareMaterial])
        e.root.addChild(e.flare)
        for y: Float in [0.86, -0.86] {
            for (inner, outer, alpha) in [(0.36, 0.66, 0.22), (0.45, 0.56, 0.5)] as [(Float, Float, CGFloat)] {
                let ring = Self.annulus(inner: inner, outer: outer, color: UIColor(red: 0.35, green: 1, blue: 0.55, alpha: alpha))
                ring.position.y = y * 1.02
                e.aurora.addChild(ring)
            }
        }
        e.bodies["earth"]?.addChild(e.aurora)
        place()
        loadTextures()
    }

    /// Loads surface maps off the main thread (about 0.6 s for all of them) and applies each as it arrives.
    private func loadTextures() {
        let e = entities
        var jobs: [(entity: ModelEntity, url: URL, tint: UIColor)] = e.bodies.compactMap { id, entity in
            GlobeView.mapURL(id).map { (entity, $0, .white) }
        }
        if let sun = Bundle.main.url(forResource: "sun", withExtension: "jpg", subdirectory: "Globes") { jobs.append((e.sun, sun, .white)) }
        for job in jobs {
            Task {
                guard let texture = try? await TextureResource(contentsOf: job.url) else { return }
                var m = UnlitMaterial()
                m.color = .init(tint: job.tint, texture: .init(texture))
                job.entity.model?.materials = [m]
            }
        }
    }

    /// Moves everything for the current date, scale, layers and camera.
    private func place() {
        let e = entities
        let map = mapping
        e.sun.scale = .init(repeating: map.sunRadius)
        for m in markers() where m.kind != .sun {
            guard let body = e.bodies[m.id] else { continue }
            body.isEnabled = m.visible
            body.position = m.scene
            body.scale = .init(repeating: m.radius)
            if let night = e.nights[m.id] {
                night.isEnabled = m.visible
                night.position = m.scene
                night.scale = .init(repeating: m.radius * 1.004)
                night.orientation = simd_quatf(from: SIMD3(0, 1, 0), to: simd_normalize(-m.scene))
            }
            if m.kind == .comet, let tail = e.tails[String(m.id.dropFirst(6))] {
                place(tail: tail, at: m, map: map)
            }
        }
        rebuildOrbitsIfNeeded()
        rebuildPathsIfNeeded()
        rebuildDebrisIfNeeded()
        // Planet orbits are a guide at system scale; close to a planet they only cut across it.
        let farEnough = cam.distance > map.radius(km: 70_000) * 25
        for (id, o) in e.orbits {
            o.isEnabled = farEnough && orbitShown(id)
        }
        for p in e.paths.values { p.isEnabled = farEnough && layers.craft }

        if live, weather.showsFlare, let earth = e.bodies["earth"] {
            e.flare.isEnabled = true
            e.flare.position = simd_normalize(earth.position) * map.sunRadius * 1.02
            e.flare.scale = .init(repeating: map.sunRadius * (pulse ? 0.22 : 0.16))
        } else {
            e.flare.isEnabled = false
        }
        e.aurora.isEnabled = live && weather.showsAurora

        e.camera.look(at: cam.target, from: cam.position, relativeTo: nil)
        e.camera.camera.near = max(cam.distance * 0.001, 1e-9)
        e.camera.camera.far = cam.distance * 100 + 400
    }

    /// A comet's tail points away from the Sun and grows as the comet nears it; none beyond 4 AU.
    private func place(tail: ModelEntity, at m: SolarMarker, map: SolarMapping) {
        guard let c = KeplerOrbit.comets.first(where: { "comet:\($0.id)" == m.id }) else { return }
        let au = (c.position(at: date) * c.position(at: date)).sum().squareRoot()
        guard m.visible, au < 4 else { tail.isEnabled = false; return }
        tail.isEnabled = true
        let away = simd_normalize(m.scene)
        let length = (map.scale == .compressed ? 0.9 : 0.4) * Float(min(1 / au, 2.5))
        // The cone's apex is at +y: point it at the Sun so the tail widens away from it.
        tail.orientation = simd_quatf(from: SIMD3(0, 1, 0), to: -away)
        tail.scale = .init(repeating: length)
        tail.position = m.scene + away * length / 2
    }

    private func orbitShown(_ id: String) -> Bool {
        if id.hasPrefix("comet:") {
            let c = String(id.dropFirst(6))
            return layers.comets && (Self.mainComets.contains(c) || activeShowers.contains { $0.parent == c })
        }
        if id.hasPrefix("dwarf:") { return layers.dwarfs }
        return true
    }

    /// Orbit ribbons for planets, dwarf planets and comets; rebuilt when the scale changes or the zoom
    /// changes enough that their width would look wrong.
    private func rebuildOrbitsIfNeeded() {
        let e = entities
        let width = cam.distance * 0.0022
        if let (s, w) = e.orbitsBuilt, s == scale, w / width < 1.6, width / w < 1.6 { return }
        e.orbitsBuilt = (scale, width)
        let map = mapping
        func set(_ id: String, _ points: [SIMD3<Float>], color: UIColor, opacity: Float) {
            let mesh = Self.ribbon(points, width: width, closed: true)
            if let existing = e.orbits[id] { existing.model?.mesh = mesh; return }
            var m = UnlitMaterial(color: color)
            m.blending = .transparent(opacity: .init(floatLiteral: opacity))
            m.faceCulling = .none
            let orbit = ModelEntity(mesh: mesh, materials: [m])
            e.orbits[id] = orbit
            e.root.addChild(orbit)
        }
        for p in SolarPlanet.all + [SolarPlanet.pluto].compactMap({ $0 }) {
            let pts = (0..<240).map { i in map.point(p.position(at: date.addingTimeInterval(Double(i) / 240 * p.periodDays * 86_400))) }
            set(p.id == "pluto" ? "dwarf:pluto" : p.id, pts, color: .white, opacity: p.id == "pluto" ? 0.12 : 0.22)
        }
        for k in KeplerOrbit.dwarfPlanets {
            set("dwarf:\(k.id)", k.orbitPath().map(map.point), color: .white, opacity: 0.12)
        }
        for c in KeplerOrbit.comets {
            set("comet:\(c.id)", c.orbitPath(steps: 400).map(map.point), color: UIColor(red: 0.6, green: 0.8, blue: 1, alpha: 1), opacity: 0.22)
        }
    }

    /// Spacecraft paths from launch to the slider's date, rebuilt every 10 days of date change.
    private func rebuildPathsIfNeeded() {
        let e = entities
        let width = cam.distance * 0.0022
        let bucket = Int(date.timeIntervalSince1970 / 864_000)
        let built = e.pathsBuilt
        if let built, built.0 == scale, built.1 / width < 1.6, width / built.1 < 1.6, built.2 == bucket { return }
        e.pathsBuilt = (scale, width, bucket)
        let map = mapping
        let day = date.timeIntervalSince1970 / 86_400
        for craft in Spacecraft.all {
            var pts = craft.points.filter { $0[0] <= day }.map { map.point(SIMD3($0[1], $0[2], $0[3])) }
            if let now = craft.position3(at: date) { pts.append(map.point(now)) }
            let mesh: MeshResource = pts.count > 1 ? Self.ribbon(pts, width: width, closed: false) : .generateBox(size: 0.0001)
            if let existing = e.paths[craft.name] {
                existing.model?.mesh = mesh
            } else {
                var m = UnlitMaterial(color: Self.craftColor)
                m.blending = .transparent(opacity: .init(floatLiteral: 0.4))
                m.faceCulling = .none
                let path = ModelEntity(mesh: mesh, materials: [m])
                e.paths[craft.name] = path
                e.root.addChild(path)
            }
        }
    }

    /// Debris along an active meteor shower's parent orbit: small specks, densest where it crosses Earth's orbit.
    private func rebuildDebrisIfNeeded() {
        let e = entities
        let showers = layers.comets ? activeShowers.compactMap(\.parent).sorted().joined(separator: ",") : ""
        let size = cam.distance * 0.0016
        if let (s, w, key) = e.debrisBuilt, s == scale, key == showers, w / size < 1.6, size / w < 1.6 { return }
        e.debrisBuilt = (scale, size, showers)
        guard !showers.isEmpty else { e.debris.isEnabled = false; return }
        e.debris.isEnabled = true
        let map = mapping
        var rng = SeededRandom(seed: 42)
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for id in showers.split(separator: ",") {
            guard let c = KeplerOrbit.comets.first(where: { $0.id == id }) else { continue }
            for p in c.orbitPath(steps: 360) {
                let r = (p * p).sum().squareRoot()
                // More specks near 1 AU, where Earth meets the stream.
                let copies = abs(r - 1) < 0.15 ? 4 : 1
                for _ in 0..<copies {
                    let jitter = SIMD3(rng.next() - 0.5, rng.next() - 0.5, rng.next() - 0.5) * 0.08 * max(r, 0.3)
                    let c = map.point(p + jitter)
                    let base = UInt32(positions.count)
                    positions += [c + SIMD3(size, 0, 0), c + SIMD3(-size / 2, size, 0), c + SIMD3(-size / 2, -size / 2, size)]
                    indices += [base, base + 1, base + 2]
                }
            }
        }
        var d = MeshDescriptor(name: "debris")
        d.positions = MeshBuffer(positions)
        d.primitives = .triangles(indices)
        if let mesh = try? MeshResource.generate(from: [d]) { e.debris.model?.mesh = mesh }
    }

    // MARK: Meshes

    /// A flat ribbon through `points`, lying in the plane of the orbit.
    private static func ribbon(_ points: [SIMD3<Float>], width: Float, closed: Bool) -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        let n = points.count
        for i in 0..<n {
            let next = closed ? points[(i + 1) % n] : points[min(i + 1, n - 1)]
            let prev = closed ? points[(i + n - 1) % n] : points[max(i - 1, 0)]
            var t = next - prev
            if simd_length(t) < 1e-12 { t = SIMD3(1, 0, 0) }
            var side = simd_cross(simd_normalize(t), SIMD3(0, 1, 0))
            if simd_length(side) < 1e-6 { side = SIMD3(1, 0, 0) }
            side = simd_normalize(side) * width / 2
            positions += [points[i] - side, points[i] + side]
            if closed || i < n - 1 {
                let a = UInt32(2 * i), b = UInt32(2 * ((i + 1) % n))
                indices += [a, a + 1, b, b, a + 1, b + 1]
            }
        }
        var d = MeshDescriptor(name: "orbit")
        d.positions = MeshBuffer(positions)
        d.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [d])) ?? .generateBox(size: 0.0001)
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

    /// The half of a unit sphere below y = 0, drawn dark and mostly opaque over a body's night side.
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

    // MARK: Labels, taps and the card

    private func screenPoints(size: CGSize) -> [(marker: SolarMarker, point: CGPoint, radius: CGFloat)] {
        markers().filter(\.visible).compactMap { m in
            cam.project(m.scene, in: size).map { (m, $0, pixelRadius(m.radius, at: m.scene, size: size)) }
        }
    }

    private func pixelRadius(_ r: Float, at p: SIMD3<Float>, size: CGSize) -> CGFloat {
        let k = Float(size.height / 2) / tan(SolarCamera.fovDegrees * .pi / 360)
        return CGFloat(r / max(cam.distance(to: p), 1e-9) * k)
    }

    /// Points to label, most important first, skipping a label that would sit on one already placed.
    private func labelled(size: CGSize) -> [(marker: SolarMarker, point: CGPoint, radius: CGFloat, showName: Bool)] {
        let planetOrder = ["jupiter", "saturn", "uranus", "neptune", "earth", "venus", "mars", "mercury"]
        func rank(_ m: SolarMarker) -> Int {
            switch m.kind {
            case .sun: 0
            case .planet: 1 + (planetOrder.firstIndex(of: m.id) ?? 9)
            case .craft: 20
            case .dwarf: 30
            case .comet: 40
            case .moon: 50
            }
        }
        var placed: [CGPoint] = []
        let points = screenPoints(size: size)
        // Anything whose centre falls on the disc of a nearer body is hidden behind it.
        let discs = points.filter { $0.radius > 4 }.map { ($0.point, $0.radius, cam.distance(to: $0.marker.scene)) }
        return points
            .filter { item in
                let d = cam.distance(to: item.marker.scene)
                return !discs.contains { $0.2 < d && hypot($0.0.x - item.point.x, $0.0.y - item.point.y) < $0.1 }
            }
            .sorted { rank($0.marker) < rank($1.marker) }
            .map { item in
                let at = CGPoint(x: item.point.x, y: item.point.y - max(item.radius, 5) - 9)
                let clear = item.marker.id == selected || placed.allSatisfy { abs($0.x - at.x) > 48 || abs($0.y - at.y) > 14 }
                if clear { placed.append(at) }
                return (item.marker, item.point, item.radius, clear)
            }
    }

    private func labels(size: CGSize) -> some View {
        ZStack {
            ForEach(labelled(size: size), id: \.marker.id) { item in
                let m = item.marker
                let isSelected = m.id == selected
                let color: Color = isSelected ? accent : m.kind == .craft ? accent.opacity(0.9) : m.kind == .comet ? Color(red: 0.7, green: 0.85, blue: 1) : ink.opacity(m.kind == .moon ? 0.7 : 0.85)
                ZStack {
                    if item.radius < 3, m.kind != .craft, m.kind != .comet {
                        Circle().stroke(isSelected ? accent : ink.opacity(0.6), lineWidth: 1.2).frame(width: 10, height: 10)
                    }
                    if item.showName {
                        Text(m.name).font(.caption2.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(color)
                            .shadow(color: .black, radius: 2)
                            .fixedSize()
                            .offset(y: -max(item.radius, 5) - 9)
                    }
                }
                .position(item.point)
            }
        }
    }

    private func tap(_ location: CGPoint, size: CGSize) {
        let hit = screenPoints(size: size)
            .map { ($0.marker.id, hypot($0.point.x - location.x, $0.point.y - location.y) - max($0.radius, 0)) }
            .filter { $0.1 < 28 }
            .min { $0.1 < $1.1 }
        guard let id = hit?.0 else { selected = nil; return }
        selected = id
        fly(to: id)
    }

    /// The selected body's Library page, title, one-line description and position note.
    private func details(_ id: String) -> (page: LibraryPage?, title: String, subtitle: String, note: String?) {
        func fromSun(_ v: SIMD3<Double>) -> String {
            let au = (v * v).sum().squareRoot()
            return String(format: "%.2f AU from the Sun · sunlight takes %@", au, lightTime(au))
        }
        if id.hasPrefix("craft:") {
            let name = String(id.dropFirst(6))
            let page = Library.page(spacecraft: name)
            let pos = Spacecraft.all.first { $0.name == name }?.position3(at: date)
            return (page, name, page?.subtitle ?? "Spacecraft", pos.map(fromSun))
        }
        if id.hasPrefix("comet:"), let c = KeplerOrbit.comets.first(where: { "comet:\($0.id)" == id }) {
            let years = c.periodDays / 365.25
            let last = Date(timeIntervalSince1970: (c.perihelionJD - 2_440_587.5) * 86_400)
            var sub = String(format: "Goes round the Sun every %.0f years.", years)
            if years < 10 {
                sub += " Next closest to the Sun \(c.nextPerihelion(after: .now).formatted(.dateTime.month(.wide).year()))."
            } else {
                sub += " Last closest to the Sun in \(last.formatted(.dateTime.year()))."
            }
            if let shower = MeteorShower.major.first(where: { $0.parent == c.id }) {
                sub += " Its debris makes the \(shower.name)."
            }
            return (c.page.flatMap { Library.page(id: $0) }, c.name, sub, fromSun(c.position(at: date)))
        }
        let page = Library.page(id: id)
        let title = page?.title ?? id
        let subtitle = page?.subtitle ?? ""
        if let m = SolarMoon.all.first(where: { $0.id == id }) {
            let parentName = Library.page(id: m.parent)?.title ?? m.parent
            let note = "\(Int(m.distanceKm).formatted()) km from \(parentName)" + (m.isExact ? "" : " · position illustrative")
            return (page, title, subtitle, note)
        }
        if let p = SolarPlanet.all.first(where: { $0.id == id }) ?? (id == "pluto" ? SolarPlanet.pluto : nil) {
            return (page, title, subtitle, fromSun(p.position(at: date)))
        }
        if let k = KeplerOrbit.dwarfPlanets.first(where: { $0.id == id }) {
            return (page, title, subtitle, fromSun(k.position(at: date)))
        }
        return (page, title, subtitle, nil)
    }

    private func card(_ id: String) -> some View {
        let d = details(id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(d.title).font(.headline)
                Spacer()
                Button { selected = nil; resetView() } label: {
                    Image(systemName: "xmark").font(.footnote.weight(.semibold)).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(-12)
                .accessibilityLabel("Close")
            }
            if !d.subtitle.isEmpty { Text(d.subtitle).font(.footnote).dimmed(0.75).fixedSize(horizontal: false, vertical: true) }
            if let note = d.note { Text(note).font(.footnote.monospacedDigit()).dimmed(0.85) }
            if let page = d.page {
                Button("Read more") { onOpen(page) }.font(.subheadline.weight(.medium)).foregroundStyle(accent)
            }
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
                let limits: ClosedRange<Float> = scale == .compressed ? 0.02...80 : 1e-6...400
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

    /// Centres on a body and zooms to a few times its drawn radius (or a fixed distance for dots).
    private func fly(to id: String) {
        guard let m = markers().first(where: { $0.id == id }) else { return }
        let distance: Float
        switch m.kind {
        case .craft, .comet: distance = scale == .compressed ? 1.2 : 0.6
        default: distance = m.radius * (m.id == "saturn" ? 2.3 : 1) * 7
        }
        animateCamera(to: SolarCamera(target: m.scene, yaw: cam.yaw, pitch: max(cam.pitch, 0.25), distance: distance))
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

/// A small deterministic generator, so debris looks the same each time it is rebuilt.
private struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }
}
