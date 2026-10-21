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

@Test func tapOnSaturnFindsSaturnAndNearbyStarsFindTheirConstellation() throws {
    let scene = try SkyScene(date: evening, observer: chicago)
    let p = Projection(centerAzimuth: 180, centerAltitude: 45, fieldOfView: 100, size: CGSize(width: 393, height: 852))
    let saturn = try #require(scene.bodies.first { $0.body == .saturn })
    let pt = try #require(p.point(saturn.position))
    #expect(scene.object(at: CGPoint(x: pt.x + 5, y: pt.y), projection: p) == .body(.saturn))

    // Altair (HR 7557) is in Aquila's figure.
    let altair = try #require(scene.starsByHR[7557])
    let a = try #require(p.point(altair))
    #expect(scene.object(at: a, projection: p) == .constellation("Aql"))
}

@Test func starBinsStayCloseToEachStar() {
    var used = Set<Int>()
    for star in Catalog.stars where star.magnitude <= 6.5 {
        let bin = StarBin(magnitude: star.magnitude, colorIndex: star.colorIndex)
        #expect(abs(bin.magnitude - star.magnitude) <= 0.25, "HR \(star.hr)")
        let tint = min(max((star.colorIndex + 0.3) / 2, 0), 1)
        #expect(abs(bin.tint - tint) <= 1.0 / 6 + 1e-9, "HR \(star.hr)")
        used.insert(bin.index)
    }
    #expect(used.allSatisfy { (0..<StarBin.count).contains($0) })
}

@MainActor
@Test func nightStyleRenders() throws {
    let scene = try SkyScene(date: evening, observer: chicago)
    let renderer = ImageRenderer(content: SkyView(scene: scene, style: .night).frame(width: 393, height: 852))
    #expect(renderer.cgImage != nil)
}

@Test func skyCulturesUseCatalogueStars() {
    let cultures = Catalog.skyCultures
    #expect(cultures.count == 10)
    let known = Set(Catalog.stars.map(\.hr))
    for c in cultures {
        #expect(!c.constellations.isEmpty, "\(c.id)")
        #expect(c.licence.contains("BY-SA") || c.licence.contains("BY SA"), "\(c.id)")
        for f in c.constellations {
            #expect(f.lines.allSatisfy { $0.count > 1 && $0.allSatisfy(known.contains) }, "\(c.id) \(f.name)")
        }
    }
    // The Norse Wolf's Mouth is the Hyades and includes Aldebaran (HR 1457).
    #expect(cultures.first { $0.id == "norse" }?.constellations.contains { $0.name == "Wolf's Mouth" && $0.lines.joined().contains(1457) } == true)
}

/// Figure labels are drawn exactly when some of the label falls on the canvas.
@MainActor
@Test func cultureLabelsDrawnAreTheOnScreenOnes() throws {
    let scene = try SkyScene(date: evening, observer: chicago)
    let culture = try #require(Catalog.skyCultures.first { $0.id == "chinese" })
    for (az, alt) in [(180.0, 45.0), (90, 30), (300, 70)] {
        let view = SkyView(scene: scene, centerAzimuth: az, centerAltitude: alt, fieldOfView: 45, culture: culture)
        var drawn: [String] = [], onScreen: [String] = [], labelled = 0
        let canvas = Canvas { context, size in
            let p = Projection(centerAzimuth: az, centerAltitude: alt, fieldOfView: 45, size: size)
            drawn = view.drawCulture(culture, &context, p)
            for figure in culture.constellations {
                var points: [CGPoint] = []
                for line in figure.lines {
                    for (a, b) in zip(line, line.dropFirst()) {
                        guard let ha = scene.starsByHR[a], let hb = scene.starsByHR[b], ha.altitude > -5 || hb.altitude > -5,
                              let pa = p.point(ha), let pb = p.point(hb) else { continue }
                        points += [pa, pb]
                    }
                }
                guard points.count > 1 else { continue }
                labelled += 1
                let c = CGPoint(x: points.map(\.x).reduce(0, +) / Double(points.count), y: points.map(\.y).reduce(0, +) / Double(points.count))
                let s = context.resolve(Text(figure.name).font(.caption2)).measure(in: CGSize(width: CGFloat.infinity, height: .infinity))
                if CGRect(x: c.x - s.width / 2, y: c.y - s.height / 2, width: s.width, height: s.height).intersects(CGRect(origin: .zero, size: size)) {
                    onScreen.append(figure.name)
                }
            }
        }
        _ = ImageRenderer(content: canvas.frame(width: 393, height: 852)).cgImage
        #expect(!drawn.isEmpty && drawn.count < labelled, "az \(az)")
        #expect(drawn.sorted() == onScreen.sorted(), "az \(az)")
    }
}
