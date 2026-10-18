import Foundation
import Testing
@testable import Feeds

// Fixtures saved from the mars.nasa.gov raw image feeds on 2026-10-18, trimmed.

@Test func perseveranceKeepsLeftEyeFullFramesWithoutSkycam() throws {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/m2020-raw", withExtension: "json"))
    let images = try MarsImage.decodePerseverance(Data(contentsOf: url))
    #expect(images.count == 24)
    #expect(Set(images.map(\.camera)) == ["Mastcam-Z", "Navcam"])
    #expect(images.allSatisfy { $0.sol == 2012 && $0.rover == "Perseverance" })
    #expect(zip(images, images.dropFirst()).allSatisfy { $0.taken >= $1.taken })
    #expect(images[0].image.absoluteString.hasSuffix("_1200.jpg"))
}

@Test func curiosityKeepsFullFramesOnly() throws {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/msl-raw", withExtension: "json"))
    let images = try MarsImage.decodeCuriosity(Data(contentsOf: url))
    #expect(images.count == 8)
    #expect(Set(images.map(\.camera)).isSubset(of: ["Navcam", "Front Hazcam", "Rear Hazcam"]))
    #expect(images.allSatisfy { $0.sol == 5047 })
}

@Test func parsesBothTimestampForms() {
    #expect(MarsImage.parseUTC("2026-10-18T04:09:00.977") != nil)
    #expect(MarsImage.parseUTC("2026-10-18T12:08:53.000Z") != nil)
    #expect(MarsImage.parseUTC("2026-10-18T12:08:53Z") != nil)
}
