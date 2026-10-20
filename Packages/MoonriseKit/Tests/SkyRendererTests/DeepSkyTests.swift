import Foundation
import SkyEngine
import SwiftUI
import Testing
@testable import SkyRenderer

@Test func messierCatalogueFollowsOpenNGC() throws {
    let objects = Catalog.deepSky
    // M102 is a duplicate of M101 in OpenNGC.
    #expect(objects.map(\.messier) == Array(1...101) + Array(103...110))
    let m31 = try #require(objects.first { $0.messier == 31 })
    #expect(m31.kind == .galaxy)
    #expect(m31.positionAngle == 35)
    #expect(abs(m31.ra - 10.685) < 0.01 && abs(m31.dec - 41.269) < 0.01)
    #expect(objects.first { $0.messier == 13 }?.kind == .globularCluster)
    #expect(objects.first { $0.messier == 57 }?.kind == .planetaryNebula)
    #expect(objects.first { $0.messier == 42 }?.kind == .nebula)
    #expect(objects.first { $0.messier == 45 }?.kind == .openCluster)
    #expect(objects.allSatisfy { $0.page == "m\($0.messier)" })
}

@Test func tapOnASymbolFindsTheMessierObject() throws {
    let scene = try SkyScene(date: evening, observer: chicago)
    let m57 = try #require(scene.deepSky.first { $0.object.messier == 57 })
    #expect(m57.position.altitude > 30)
    let p = Projection(centerAzimuth: m57.position.azimuth, centerAltitude: m57.position.altitude, fieldOfView: 60, size: CGSize(width: 393, height: 852))
    let pt = try #require(p.point(m57.position))
    #expect(scene.object(at: CGPoint(x: pt.x + 4, y: pt.y), projection: p) == .deepSky(57))
    #expect(scene.object(at: CGPoint(x: pt.x + 4, y: pt.y), projection: p, deepSky: false) != .deepSky(57))
}

/// The symbol frame's east vector matches where a point east of the object projects.
@MainActor
@Test func symbolFrameHasEastAnticlockwiseFromNorth() throws {
    let scene = try SkyScene(date: evening, observer: chicago)
    let view = SkyView(scene: scene)
    for m in [31, 13, 57] {
        let d = try #require(scene.deepSky.first { $0.object.messier == m })
        let p = Projection(centerAzimuth: 180, centerAltitude: 45, fieldOfView: 100, size: CGSize(width: 393, height: 852))
        let f = try #require(view.symbolFrame(d, p))
        let o = d.object
        let east = SkyEngine.horizontal(j2000: [(o.ra + 0.1 / cos(o.dec * .pi / 180), o.dec)], at: evening, from: chicago)[0]
        let e = try #require(p.point(east))
        let measured = CGVector(dx: (e.x - f.center.x) * 10, dy: (e.y - f.center.y) * 10)
        #expect(hypot(measured.dx - f.east.dx, measured.dy - f.east.dy) < 0.05 * hypot(f.east.dx, f.east.dy), "M\(m)")
    }
}

@MainActor
@Test func deepSkyRendersAtEveryZoom() throws {
    let scene = try SkyScene(date: evening, observer: chicago)
    for fov in [30.0, 100.0] {
        let renderer = ImageRenderer(content: SkyView(scene: scene, centerAzimuth: 90, centerAltitude: 50, fieldOfView: fov, showDeepSky: true).frame(width: 393, height: 852))
        #expect(renderer.cgImage != nil)
    }
}
