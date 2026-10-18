import Library
import RealityKit
import SwiftUI

/// A Library body as a sphere you can turn with a drag: a global map from the app bundle
/// (Globes/<page id>.jpg) when there is one, otherwise the page's colour. Tilted by its axial tilt.
struct GlobeView: View {
    var page: LibraryPage
    var credit: String?
    @State private var yaw: Float = 0
    @State private var pitch: Float = 0
    @State private var dragStart: (Float, Float)?

    /// Pitch from the drag, then the axial tilt, then the spin.
    private var orientation: simd_quatf {
        let degrees: Double = page.drawing?.axialTiltDeg ?? 0
        let tilt = simd_quatf(angle: Float(degrees * .pi / 180), axis: SIMD3<Float>(0, 0, 1))
        let spin = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
        return simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0)) * tilt * spin
    }

    static func mapURL(_ id: String) -> URL? { Bundle.main.url(forResource: id, withExtension: "jpg", subdirectory: "Globes") }

    var body: some View {
        VStack(spacing: 12) {
            RealityView { content in
                let globe = await Self.makeGlobe(page)
                #if os(visionOS)
                // A 30 cm globe in the window; the room's lighting shades it.
                globe.scale = .init(repeating: 0.3)
                content.add(globe)
                #else
                content.camera = .virtual
                content.add(globe)

                let camera = PerspectiveCamera()
                camera.position = [0, 0, 1.9]
                content.add(camera)

                let sun = DirectionalLight()
                sun.light.intensity = 4000
                sun.look(at: .zero, from: [-1.5, 0.3, 0.5], relativeTo: nil)
                content.add(sun)
                #endif
            } update: { content in
                guard let globe = content.entities.first(where: { $0.name == "globe" }) else { return }
                globe.orientation = orientation
            }
            .gesture(DragGesture()
                .onChanged { g in
                    if dragStart == nil { dragStart = (yaw, pitch) }
                    yaw = dragStart!.0 + Float(g.translation.width) * 0.01
                    pitch = min(max(dragStart!.1 + Float(g.translation.height) * 0.01, -1.2), 1.2)
                }
                .onEnded { _ in dragStart = nil })
            .accessibilityLabel("\(page.title) as a globe. Drag to turn it.")
            Text(Self.mapURL(page.id) == nil
                 ? "No global map yet; shown in its average colour. Drag to turn."
                 : "Drag to turn. Map: \(credit ?? "NASA").")
                .font(.caption2).foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @MainActor
    static func makeGlobe(_ page: LibraryPage) async -> Entity {
        var material = PhysicallyBasedMaterial()
        material.roughness = .init(floatLiteral: 1)
        material.metallic = .init(floatLiteral: 0)
        if let url = mapURL(page.id), let texture = try? await TextureResource(contentsOf: url) {
            material.baseColor = .init(texture: .init(texture))
        } else {
            material.baseColor = .init(tint: UIColor(Color(hex: page.drawing?.color ?? "") ?? .gray))
        }
        if page.id == "sun" {
            var glow = UnlitMaterial(color: UIColor(Color(hex: page.drawing?.color ?? "") ?? .yellow))
            if let url = mapURL(page.id), let texture = try? await TextureResource(contentsOf: url) { glow.color = .init(texture: .init(texture)) }
            let sun = ModelEntity(mesh: .generateSphere(radius: 0.5), materials: [glow])
            sun.name = "globe"
            return sun
        }
        let globe = ModelEntity(mesh: .generateSphere(radius: 0.5), materials: [material])
        globe.name = "globe"
        return globe
    }
}
