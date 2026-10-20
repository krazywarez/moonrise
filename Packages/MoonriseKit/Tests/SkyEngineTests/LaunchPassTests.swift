import Foundation
import Testing
@testable import SkyEngine

// CelesTrak GP for the ISS, 2026-10-18.
private let iss = OrbitalElements(name: "ISS (ZARYA)", norad: 25544, epoch: "2026-10-18T03:28:15.076416",
                                  meanMotion: 15.48918166, eccentricity: 0.000678, inclination: 51.6328,
                                  raan: 51.6259, argPerigee: 277.7856, meanAnomaly: 82.2363, bstar: 0.00014456)

@Test func visiblePassesStartAtEachEpoch() throws {
    let epoch = try #require(iss.epochDate)
    let passes = SkyEngine.visiblePasses(of: [iss], from: epoch.addingTimeInterval(-86_400), observer: chicago)
    #expect(!passes.isEmpty)
    #expect(passes.allSatisfy { $0.visible && $0.rise >= epoch && $0.rise <= epoch.addingTimeInterval(72 * 3600) })
}

@Test func visiblePassesMergeSetsInTimeOrder() throws {
    var other = iss
    other.OBJECT_NAME = "FALCON 9 R/B"
    other.MEAN_ANOMALY += 40
    let start = try #require(iss.epochDate)
    let one = SkyEngine.visiblePasses(of: [iss], from: start, observer: chicago)
    let both = SkyEngine.visiblePasses(of: [iss, other], from: start, observer: chicago)
    #expect(both.count > one.count)
    #expect(both.map(\.rise) == both.map(\.rise).sorted())
}
