import Foundation
import Testing
@testable import Answers
@testable import Feeds
import Library
@testable import SkyEngine

private let chicagoPlace = Place(latitude: 41.878, longitude: -87.630, name: "Your location", kind: .located)
private let central = TimeZone(identifier: "America/Chicago")!
private let gb = Locale(identifier: "en_GB")
/// 18:00 CDT, 18 October 2026.
private let evening = Date(timeIntervalSince1970: 1_792_364_400)

@Test func placeRoundsAndRoundTrips() throws {
    let p = Place(latitude: 41.8781, longitude: -87.6298, name: "Your location", kind: .located)
    #expect(p.latitude == 41.9)
    #expect(p.longitude == -87.6)
    let defaults = try #require(UserDefaults(suiteName: "AnswersTests.place"))
    defaults.removePersistentDomain(forName: "AnswersTests.place")
    #expect(Place.saved(in: defaults) == nil)
    p.save(to: defaults)
    #expect(Place.saved(in: defaults) == p)
}

@Test func placeNotes() {
    #expect(chicagoPlace.note == nil)
    #expect(Place(latitude: 52.52, longitude: 13.405, name: "Berlin", kind: .city).note == "For Berlin.")
    #expect(Place.fallback.note == "For Chicago; open Moonrise to set your location.")
    #expect(Place.fallback.label == "Chicago")
    #expect(chicagoPlace.label == "Your location")
}

@Test func compass() {
    #expect(Compass.point(0) == "N")
    #expect(Compass.point(135) == "SE")
    #expect(Compass.point(350) == "N")
    #expect(Compass.name(240) == "southwest")
    #expect(Compass.name(270) == "west")
}

@Test func moonAnswer() throws {
    let a = try MoonAnswer(at: evening, locale: gb, timeZone: central)
    let angle = try SkyEngine.moonPhase(at: evening)
    #expect(a.phaseName == DailySummary.phaseName(angle))
    #expect(a.waxing == (angle < 180))
    let lit = Int((try SkyEngine.illumination(.moon, at: evening).phaseFraction * 100).rounded())
    #expect(a.spoken.hasPrefix("\(a.phaseName), \(lit)% lit. \(MoonAnswer.quarterName(a.nextQuarter)) "))
    let time = a.nextQuarterDate.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: gb, timeZone: central))
    #expect(a.spoken.hasSuffix(" at \(time)."))
    #expect(a.rows.count == 3)
}

@Test func spokenDays() {
    let p = Phrasing(locale: gb, timeZone: central)
    #expect(p.when(evening.addingTimeInterval(3600), from: evening) == "today at 19:00")
    #expect(p.when(evening.addingTimeInterval(12 * 3600), from: evening) == "tomorrow at \(p.time(evening.addingTimeInterval(12 * 3600)))")
    // Tuesday 20 October.
    #expect(p.when(evening.addingTimeInterval(48 * 3600), from: evening) == "Tuesday at 18:00")
    #expect(p.when(evening.addingTimeInterval(10 * 86_400), from: evening) == "on 28 October at 18:00")
}

@Test func tonightAnswer() throws {
    let a = try TonightAnswer(at: evening, place: chicagoPlace, locale: gb, timeZone: central)
    let t = try Tonight(at: evening, from: chicagoPlace.observer)
    #expect(a.planets.map(\.name) == t.planets.filter { $0.best != nil }.map { $0.body.rawValue.capitalized })
    #expect(a.spoken.contains("Sunset 18:"))
    #expect(a.heading == "Tonight · Your location")
    #expect(a.rows.count <= 4)
    #expect(a.rows.last?.label == "Sun")
    if let first = a.planets.first { #expect(a.spoken.hasPrefix("Up tonight: \(first.name)")) }

    let berlin = Place(latitude: 52.52, longitude: 13.405, name: "Berlin", kind: .city)
    let b = try TonightAnswer(at: evening, place: berlin, locale: gb, timeZone: central)
    #expect(b.spoken.hasSuffix(" For Berlin."))
}

private func pass(_ name: String, rise: TimeInterval, alt: Double, visible: Bool) -> SatellitePass {
    SatellitePass(name: name, rise: evening.addingTimeInterval(rise), set: evening.addingTimeInterval(rise + 360), peak: evening.addingTimeInterval(rise + 180),
                  maxAltitude: alt, riseAzimuth: 240, setAzimuth: 60, visible: visible, featured: true)
}

@Test func passAnswerPrefersVisible() {
    let dull = pass("ISS (ZARYA)", rise: 1800, alt: 20, visible: false)
    let bright = pass("ISS (ZARYA)", rise: 5400, alt: 54.4, visible: true)
    let a = PassAnswer(satellite: .iss, passes: [dull, bright], at: evening, place: chicagoPlace, locale: gb, timeZone: central)
    #expect(a.pass == bright)
    #expect(a.spoken == "The ISS rises today at 19:30 in the southwest, 54° high. Visible to the eye.")
    #expect(a.rows.count == 4)
    #expect(!a.rows[0].alert)
}

@Test func passAnswerWithoutVisiblePass() {
    let dull = pass("HST", rise: 40_000, alt: 20, visible: false)
    let a = PassAnswer(satellite: .hubble, passes: [dull], at: evening, place: Place.fallback, locale: gb, timeZone: central)
    let time = Phrasing(locale: gb, timeZone: central).time(dull.rise)
    #expect(a.spoken == "No visible Hubble passes in the next three days. The next one rises tomorrow at \(time) in the southwest, 20° high. For Chicago; open Moonrise to set your location.")
    let none = PassAnswer(satellite: .tiangong, passes: [], at: evening, place: chicagoPlace, locale: gb, timeZone: central)
    #expect(none.pass == nil)
    #expect(none.spoken == "No Tiangong passes above 10° in the next three days.")
}

@Test func passSoonIsAnAlert() {
    let a = PassAnswer(satellite: .iss, passes: [pass("ISS (ZARYA)", rise: 600, alt: 40, visible: true)], at: evening, place: chicagoPlace, locale: gb, timeZone: central)
    #expect(a.rows[0].alert)
}

@Test func satelliteIDs() {
    #expect(Satellite.allCases.map(\.rawValue) == [25544, 48274, 20580])
    #expect(Set(Satellite.allCases.map(\.rawValue)) == OrbitalElements.featuredIDs)
}

private func launches(_ json: String) throws -> [Launch] {
    try LaunchFeed.decode(Data(#"{"fetchedAt":null,"launches":[\#(json)]}"#.utf8)).launches
}

private let bandwagon = #"""
{"id":"a","name":"Falcon 9 Block 5 | Bandwagon 5","net":"2026-10-19T10:30:00Z","status":"Go","statusName":"Go for Launch","provider":"SpaceX",
 "rocket":"Falcon 9 Block 5","mission":"Bandwagon 5","pad":"Space Launch Complex 40","location":"Cape Canaveral SFS, FL, USA"}
"""#

@Test func launchAnswer() throws {
    let done = #"{"id":"b","name":"Electron | X","net":"2026-10-18T22:00:00Z","status":"Success","statusName":"Launch Successful","provider":"Rocket Lab","rocket":"Electron","pad":"LC-1B","location":"Mahia"}"#
    let a = LaunchAnswer(launches: try launches(done + "," + bandwagon), at: evening, locale: gb, timeZone: central)
    #expect(a.launch?.id == "a")
    #expect(a.spoken == "Falcon 9 Block 5, Bandwagon 5, from Cape Canaveral SFS in 11 hours, 30 minutes. Status: Go for Launch.")
    #expect(a.rows.map(\.label) == ["Rocket", "Mission", "From", "Launch"])
    #expect(!a.rows[3].alert)

    let hold = bandwagon.replacingOccurrences(of: #""status":"Go","statusName":"Go for Launch""#, with: #""status":"Hold","statusName":"On Hold""#)
    #expect(LaunchAnswer(launches: try launches(hold), at: evening, locale: gb, timeZone: central).rows[3].alert)
    #expect(LaunchAnswer(launches: [], at: evening, locale: gb, timeZone: central).spoken == "No upcoming launches are scheduled.")
}

@Test func auroraAnswer() {
    let quiet = SpaceWeather(kpNow: 3.33, observedAt: evening, kpNext24h: 4.67)
    let a = AuroraAnswer(weather: quiet, place: chicagoPlace, locale: gb, timeZone: central)
    #expect(!a.possible)
    #expect(a.spoken == "Kp 3.3, quiet. Up to Kp 4.7 in the next 24 hours. Aurora unlikely here. You'd need about Kp 5.")
    #expect(a.footnote == "NOAA SWPC · 18:00")

    let storm = SpaceWeather(kpNow: 6, observedAt: evening, kpNext24h: nil)
    let s = AuroraAnswer(weather: storm, place: chicagoPlace, locale: gb, timeZone: central)
    #expect(s.possible)
    #expect(s.spoken == "Kp 6.0, G2 storm. Aurora possible low on the northern horizon.")
    #expect(s.rows[0].alert)

    let hobart = Place(latitude: -42.88, longitude: 147.33, name: "Hobart", kind: .city)
    #expect(AuroraAnswer(weather: storm, place: hobart, locale: gb, timeZone: central).spoken.contains("southern horizon"))

    let quito = Place(latitude: -0.18, longitude: -78.47, name: "Quito", kind: .city)
    #expect(AuroraAnswer(weather: quiet, place: quito, locale: gb, timeZone: central).spoken.contains("Aurora is out of reach this far from the poles."))
}

@Test func probeAnswer() throws {
    let a = try ProbeAnswer(probe: .voyager1, at: evening, locale: gb)
    // Voyager 1 is about 170 AU out in late 2026.
    #expect(a.fromEarthKm > 24e9 && a.fromEarthKm < 26.5e9, "\(a.fromEarthKm)")
    #expect(abs(a.lightTime - a.fromEarthKm / 299_792.458) < 1)
    #expect(a.spoken.hasPrefix("Voyager 1 is 2"))
    #expect(a.spoken.contains(" billion km from Earth. Its signal takes 2"))
    #expect(!a.spoken.contains("prediction"))
    #expect(try ProbeAnswer(probe: .pioneer10, at: evening, locale: gb).spoken.hasSuffix("Contact was lost, so this is a prediction."))
    #expect(Probe.allCases.count == 5)
}

@Test func lookUpAnswer() throws {
    let a = LookUpAnswer(page: try #require(Library.page(id: "ori")))
    #expect(a.spoken.hasPrefix("Orion: The Hunter. Abbreviation: Ori."))
    #expect(a.rows.count == 3)
    let m1 = LookUpAnswer(page: try #require(Library.page(id: "m1")))
    #expect(m1.spoken.hasPrefix("M1: Crab Nebula, supernova remnant in Taurus."))
}

@Test func skyTargets() throws {
    #expect(try #require(Library.page(id: "ori")).skyTarget == Tour.Target(constellation: "Ori"))
    #expect(try #require(Library.page(body: "jupiter")).skyTarget == Tour.Target(body: "jupiter"))
    #expect(try #require(Library.page(body: "moon")).skyTarget == Tour.Target(body: "moon"))
    #expect(try #require(Library.page(id: "sirius")).skyTarget?.hr != nil)
    #expect(try #require(Library.page(id: "sun")).skyTarget == nil)
    #expect(try #require(Library.page(body: "pluto")).skyTarget == nil)
    #expect(try #require(Library.page(id: "m42")).skyTarget == nil)
    #expect(Library.pages.filter { $0.skyTarget != nil }.count == 88 + 50 + 8)
}
