import Foundation
import SkyEngine
import SwiftUI
import Testing
@testable import SkyRenderer

let chicago = Observer(latitude: 41.8781, longitude: -87.6298)
let evening = Date(timeIntervalSince1970: 1_792_202_400) // 2026-10-17T02:00:00Z, 21:00 CDT

@Test func catalogLoads() {
    #expect(Catalog.stars.count > 9_000)
    #expect(Catalog.stars.contains { $0.hr == 2491 && $0.magnitude < -1 }) // Sirius
}

@Test func sceneHasSaturnUpAndMarsDown() throws {
    let scene = try SkyScene(date: evening, observer: chicago)
    let saturn = try #require(scene.bodies.first { $0.body == .saturn })
    let mars = try #require(scene.bodies.first { $0.body == .mars })
    #expect(saturn.position.altitude > 30)
    #expect(mars.position.altitude < 0)
}

/// Renders the sky to a PNG and reports timings. Set SKY_RENDER_OUT to keep the image.
@MainActor
@Test func renderStaticSky() throws {
    let clock = ContinuousClock()
    var scene: SkyScene!
    let build = try clock.measure { scene = try SkyScene(date: evening, observer: chicago) }

    let renderer = ImageRenderer(content: SkyView(scene: scene).frame(width: 393, height: 852))
    renderer.scale = 3
    var image: CGImage?
    let render = clock.measure { image = renderer.cgImage }
    let cg = try #require(image)

    print("scene: \(scene.stars.count) stars, build \(build); render \(cg.width)x\(cg.height) in \(render)")

    if let out = ProcessInfo.processInfo.environment["SKY_RENDER_OUT"] {
        let url = URL(fileURLWithPath: out)
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, cg, nil)
        #expect(CGImageDestinationFinalize(dest))
    }
}
