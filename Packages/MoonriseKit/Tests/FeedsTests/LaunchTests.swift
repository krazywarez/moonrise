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
    #expect(list.recent == nil)
    #expect(list.launches[0].elements == nil)
}

@Test func decodesBroadcastChannel() throws {
    // Shape of GET /v1/launches?environment=sandbox with a launch channel, 2026-10-20.
    let data = Data("""
    {"fetchedAt":"2026-10-20T12:00:00.000Z","launches":[{"id":"fake-near","name":"Test | Near","net":"2026-10-20T22:46:46Z","windowStart":null,
     "windowEnd":null,"status":"Go","statusName":"Go","provider":"X","rocket":"Rocket","mission":null,"missionType":null,"missionDescription":null,
     "orbit":null,"pad":"Pad","location":"Loc","padLatitude":null,"padLongitude":null,"elements":[],"elementsSource":null,"channelId":"U0FOREJPWDE="},
     {"id":"fake-far","name":"Test | Far","net":"2026-10-21T03:16:46Z","windowStart":null,"windowEnd":null,"status":"TBC","statusName":"TBC",
     "provider":"X","rocket":"Rocket","mission":null,"missionType":null,"missionDescription":null,"orbit":null,"pad":"Pad","location":"Loc",
     "padLatitude":null,"padLongitude":null,"elements":[],"elementsSource":null,"channelId":null}],"recent":[]}
    """.utf8)
    let list = try LaunchFeed.decode(data)
    #expect(list.launches[0].channelId == "U0FOREJPWDE=")
    #expect(list.launches[1].channelId == nil)
}

@Test func launchesURLNamesTheAPNsEnvironment() {
    let base = URL(string: "https://example.com")!
    #expect(LaunchFeed.url(base: base, environment: "sandbox").absoluteString == "https://example.com/v1/launches?environment=sandbox")
    #expect(LaunchFeed.url(base: base, environment: "production").absoluteString == "https://example.com/v1/launches?environment=production")
}

@Test func decodesRecentLaunchesWithElements() throws {
    // Shape of GET /v1/launches with launch element sets, 2026-10-19.
    let data = Data("""
    {"fetchedAt":"2026-10-19T12:00:00.000Z","launches":[],"recent":[{"id":"97c6f5e1","name":"Falcon 9 Block 5 | Starlink Group 15-25",
     "net":"2026-10-13T00:28:11Z","windowStart":null,"windowEnd":null,"status":"Success","statusName":"Launch Successful","provider":"SpaceX",
     "rocket":"Falcon 9 Block 5","mission":"Starlink Group 15-25","missionType":"Communications","missionDescription":null,"orbit":"LEO",
     "pad":"Space Launch Complex 4E","location":"Vandenberg SFB, CA, USA","padLatitude":34.632,"padLongitude":-120.611,
     "elements":[{"OBJECT_NAME":"Starlink train (Group 15-25)","NORAD_CAT_ID":66001,"EPOCH":"2026-10-18T22:10:01.123456","MEAN_MOTION":15.91,
      "ECCENTRICITY":0.0001,"INCLINATION":70.0,"RA_OF_ASC_NODE":120.5,"ARG_OF_PERICENTER":90.1,"MEAN_ANOMALY":270.2,"BSTAR":0.0012}],
     "elementsSource":"gp"}]}
    """.utf8)
    let list = try LaunchFeed.decode(data)
    let launch = try #require(list.recent?.first)
    #expect(launch.elements?.first?.OBJECT_NAME == "Starlink train (Group 15-25)")
    #expect(launch.elementsSource == "gp")
}
