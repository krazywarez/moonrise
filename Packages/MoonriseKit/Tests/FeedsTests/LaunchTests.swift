import Foundation
import Testing
@testable import Feeds

@Test func decodesBackendLaunches() throws {
    // Shape of GET /v1/launches from the local Worker, 2026-10-17.
    let data = Data("""
    {"fetchedAt":"2026-10-17T23:54:22.559Z","launches":[{"id":"3b430f81","name":"Falcon 9 Block 5 | Bandwagon 5","net":"2026-10-19T10:30:00Z",
     "windowStart":"2026-10-19T10:30:00Z","windowEnd":"2026-10-19T11:30:00Z","status":"Go","statusName":"Go for Launch","provider":"SpaceX",
     "rocket":"Falcon 9 Block 5","mission":"Bandwagon 5","missionType":"Dedicated Rideshare","missionDescription":"Rideshare.","orbit":"LEO",
     "pad":"Space Launch Complex 40","location":"Cape Canaveral SFS, FL, USA","padLatitude":28.56194122,"padLongitude":-80.57735736},
     {"id":"x","name":"Electron | HawkEye","net":"2026-10-21T05:00:00Z","windowStart":null,"windowEnd":null,"status":"TBC","statusName":"To Be Confirmed",
     "provider":"Rocket Lab","rocket":"Electron","mission":null,"missionType":null,"missionDescription":null,"orbit":null,"pad":"LC-1B","location":"Mahia","padLatitude":null,"padLongitude":null}]}
    """.utf8)
    let list = try LaunchFeed.decode(data)
    #expect(list.launches.count == 2)
    #expect(list.launches[0].rocket == "Falcon 9 Block 5")
    #expect(list.launches[0].net == (try Date("2026-10-19T10:30:00Z", strategy: .iso8601)))
    #expect(list.launches[1].mission == nil)
    #expect(list.fetchedAt != nil)
}
