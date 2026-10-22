import Foundation
import Testing
@testable import SkyRenderer

@Test func horizonProfileInterpolatesAndStores() throws {
    var h = HorizonProfile()
    #expect(h.isFlat)
    h.altitudes[9] = 20  // 90°, east
    #expect(h.altitude(at: 90) == 20)
    #expect(h.altitude(at: 95) == 10)
    #expect(h.altitude(at: 85) == 10)
    #expect(h.altitude(at: 450) == 20)
    #expect(h.altitude(at: -270) == 20)
    #expect(HorizonProfile(stored: h.stored) == h)
    #expect(HorizonProfile(stored: "1,2") == nil)
}
