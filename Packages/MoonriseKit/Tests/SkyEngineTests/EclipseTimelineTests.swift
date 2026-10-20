import Foundation
import Testing
@testable import SkyEngine

private let peak2027 = Date(timeIntervalSince1970: 1_817_201_220)
private let tarifa = Observer(latitude: 36.0143, longitude: -5.6044)

private func timeline(_ observer: Observer, accuracy: Double?) throws -> EclipseTimeline {
    try EclipseTimeline(try #require(LocalEclipse.at(observer, near: peak2027)), observer: observer, accuracy: accuracy)
}

private func offCues(_ t: EclipseTimeline) -> [EclipseTimeline.Cue] { t.cues.filter { $0.text.localizedCaseInsensitiveContains("glasses off") } }

@Test func glassesOffOnlyAtSecondContactWithAPreciseFix() throws {
    let t = try timeline(tarifa, accuracy: 5)
    #expect(t.glassesOffWithheld == nil)
    let off = offCues(t)
    #expect(off.count == 1)
    #expect(off.first?.date == t.eclipse.centralBegin)
    #expect(off.first?.text.contains("last bead") == true)
}

@Test func glassesOnTenSecondsBeforeThirdContact() throws {
    for accuracy in [5.0, 500, nil] {
        let t = try timeline(tarifa, accuracy: accuracy)
        let c3 = try #require(t.eclipse.centralEnd)
        let on = t.cues.filter { $0.text.hasPrefix("Glasses on") }
        #expect(on.map(\.date) == [c3.addingTimeInterval(-10)])
        #expect(on.first?.warning == true)
    }
}

@Test func noGlassesOffWithoutAPreciseFix() throws {
    let coarse = try timeline(tarifa, accuracy: 100)
    #expect(offCues(coarse).isEmpty)
    #expect(coarse.glassesOffWithheld == .imprecise)
    let city = try timeline(tarifa, accuracy: nil)
    #expect(offCues(city).isEmpty)
    #expect(city.glassesOffWithheld == .imprecise)
}

@Test func noGlassesOffForShortTotality() throws {
    var e = try #require(LocalEclipse.at(tarifa, near: peak2027))
    e.centralEnd = e.centralBegin?.addingTimeInterval(29.9)
    let t = try EclipseTimeline(e, observer: tarifa, accuracy: 5)
    #expect(offCues(t).isEmpty)
    #expect(t.glassesOffWithheld == .short)
}

@Test func partialSiteKeepsGlassesOnThroughout() throws {
    let seville = Observer(latitude: 37.3891, longitude: -5.9845) // 98% covered, no totality
    let t = try timeline(seville, accuracy: 5)
    #expect(t.eclipse.kind == "Partial")
    #expect(offCues(t).isEmpty)
    #expect(t.glassesOffWithheld == .partial)
    #expect(t.cues.first?.text.contains("keep your glasses on the whole time") == true)
}

@Test func scriptHasShadowBandAndBeadCuesInOrder() throws {
    let t = try timeline(tarifa, accuracy: 5)
    let c2 = try #require(t.eclipse.centralBegin)
    #expect(t.cues.contains { $0.date == c2.addingTimeInterval(-120) && $0.text.contains("shadow bands") })
    #expect(t.cues.contains { $0.date == c2.addingTimeInterval(-15) && $0.text.contains("Baily's beads") })
    #expect(t.cues.map(\.date) == t.cues.map(\.date).sorted())
    #expect(t.cues.first?.date == t.eclipse.partialBegin && t.cues.last?.date == t.eclipse.partialEnd)
}

@Test func rehearsalStartsThreeMinutesBeforeTotalityOrMaximum() throws {
    let t = try timeline(tarifa, accuracy: 5)
    #expect(t.rehearsalStart == t.eclipse.centralBegin?.addingTimeInterval(-180))
    let madrid = try timeline(Observer(latitude: 40.42, longitude: -3.70), accuracy: 5)
    #expect(madrid.rehearsalStart == madrid.eclipse.peak.addingTimeInterval(-180))
}

@Test func sunAtEachContact() throws {
    let t = try timeline(tarifa, accuracy: 5)
    #expect(t.contacts.map(\.name) == ["C1", "C2", "Max", "C3", "C4"])
    let c2 = t.contacts[1].sun
    // Tarifa at totality: hour angle −56°, declination +17.8°, so about 38° up and just south of east.
    #expect(abs(c2.altitude - 38) < 2)
    #expect(c2.azimuth > 92 && c2.azimuth < 98)
    let path = try t.sunPath(every: 300)
    #expect(path.first?.date == t.eclipse.partialBegin && path.last?.date == t.eclipse.partialEnd)
}
