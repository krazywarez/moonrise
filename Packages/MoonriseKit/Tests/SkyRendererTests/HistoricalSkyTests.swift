import Foundation
import Testing
@testable import SkyEngine
@testable import SkyRenderer

/// The date `years` Julian years from J2000.
private func epoch(_ years: Double) -> Date { SkyEngine.j2000.addingTimeInterval(years * 365.25 * 86_400) }

private func poleDistance(hr: Int, at date: Date) throws -> Double {
    let star = try #require(Catalog.stars.first { $0.hr == hr })
    return 90 - SkyEngine.equatorOfDate(j2000: star.position(at: date), at: date).dec
}

@Test func polarisClosestAround2100() throws {
    #expect(try poleDistance(hr: 424, at: epoch(0)) < 0.8)
    #expect(try poleDistance(hr: 424, at: epoch(100)) < 0.55)
    #expect(try poleDistance(hr: 424, at: epoch(-2000)) > 10) // year 1
}

@Test func thubanWasThePoleStar() throws {
    // Thuban (α Dra, HR 5291) was within about a tenth of a degree of the pole around 2800 BCE.
    #expect(try poleDistance(hr: 5291, at: epoch(-4800)) < 1)
    #expect(try poleDistance(hr: 5291, at: epoch(0)) > 20)
}

@Test func arcturusProperMotion() throws {
    let arcturus = try #require(Catalog.stars.first { $0.hr == 5340 })
    let now = arcturus.position(at: epoch(0)), later = arcturus.position(at: epoch(2000))
    let dRA = (later.ra - now.ra) * cos(now.dec * .pi / 180), dDec = later.dec - now.dec
    // 2.28″/yr total, so about 1.27° in 2000 years.
    #expect(abs((dRA * dRA + dDec * dDec).squareRoot() - 1.27) < 0.02)
}
