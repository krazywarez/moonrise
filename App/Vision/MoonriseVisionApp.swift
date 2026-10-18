import Library
import RealityKit
import SkyEngine
import SkyRenderer
import SwiftUI

@main
struct MoonriseVisionApp: App {
    var body: some SwiftUI.Scene {
        WindowGroup { VisionHome() }

        WindowGroup(id: "orrery") { OrreryVolume() }
            .windowStyle(.volumetric)
            .defaultSize(width: 0.8, height: 0.4, depth: 0.8, in: .meters)

        ImmersiveSpace(id: "sky") { ImmersiveSky() }
    }
}

/// Library globes, plus buttons for the orrery volume and the immersive sky.
struct VisionHome: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var immersed = false

    private var bodies: [LibraryPage] {
        [LibrarySection.sun, .planets, .dwarfPlanets, .moons].flatMap { Library.pages(in: $0) }
    }

    var body: some View {
        NavigationSplitView {
            List(bodies) { page in
                NavigationLink(page.title) { GlobeView(page: page, credit: GlobeMaps.credit[page.id]) }
            }
            .navigationTitle("Moonrise")
            .toolbar {
                ToolbarItem(placement: .bottomOrnament) {
                    HStack {
                        Button("Orrery") { openWindow(id: "orrery") }
                        Button(immersed ? "Leave the sky" : "Tonight's sky") {
                            Task {
                                if immersed { await dismissImmersiveSpace() } else { _ = await openImmersiveSpace(id: "sky") }
                                immersed.toggle()
                            }
                        }
                    }
                }
            }
        } detail: {
            Text("Choose a body to see it as a globe.").foregroundStyle(.secondary)
        }
    }
}

/// Outside the view, where `Body` is SkyEngine's rather than the view's body type.
private let orreryPlanets = Body.planets

/// The Sun and planets at today's heliocentric positions. Distances are square-rooted so Neptune fits.
struct OrreryVolume: View {
    var body: some View {
        RealityView { content in
            let sun = ModelEntity(mesh: .generateSphere(radius: 0.025), materials: [UnlitMaterial(color: .yellow)])
            content.add(sun)
            for body in orreryPlanets {
                guard let p = try? SkyEngine.heliocentricEcliptic(body, at: .now) else { continue }
                let au = (p * p).sum().squareRoot()
                let scale = 0.065 * au.squareRoot() / au
                let page = Library.page(body: body.rawValue)
                let colour = UIColor(Color(hex: page?.drawing?.color) ?? .white)
                let planet = ModelEntity(mesh: .generateSphere(radius: 0.008), materials: [SimpleMaterial(color: colour, isMetallic: false)])
                // Ecliptic x, y in the horizontal plane; ecliptic north up.
                planet.position = [Float(p.x * scale), Float(p.z * scale), Float(-p.y * scale)]
                content.add(planet)
            }
        }
    }
}

/// Stars brighter than magnitude 4.5 on a 20 m sphere, placed for now from Chicago,
/// with the horizon as a faint disc.
struct ImmersiveSky: View {
    var body: some View {
        RealityView { content in
            let observer = Observer(latitude: 41.8781, longitude: -87.6298)
            let stars = Catalog.stars.filter { $0.magnitude < 4.5 }
            let positions = SkyEngine.horizontal(j2000: stars.map { $0.position(at: .now) }, at: .now, from: observer)
            let mesh = MeshResource.generateSphere(radius: 0.04)
            for (star, h) in zip(stars, positions) where h.altitude > -2 {
                let alt = Float(h.altitude * .pi / 180), az = Float(h.azimuth * .pi / 180)
                let r: Float = 20
                let s = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .white)])
                s.scale = .init(repeating: max(0.3, Float(2.2 - 0.4 * star.magnitude)))
                // Azimuth from north (−z) towards east (+x).
                s.position = [r * cos(alt) * sin(az), r * sin(alt), -r * cos(alt) * cos(az)]
                content.add(s)
            }
            let ground = ModelEntity(mesh: .generatePlane(width: 40, depth: 40), materials: [UnlitMaterial(color: UIColor(white: 0.05, alpha: 0.9))])
            ground.position.y = -0.01
            content.add(ground)
        }
    }
}
