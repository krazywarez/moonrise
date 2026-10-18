import Foundation
import Testing
@testable import ObservingLog

let when = Date(timeIntervalSince1970: 1_792_202_400) // 2026-10-17T02:00:00Z

@Test func orgRoundTrip() throws {
    let o = Observation(object: "Saturn", date: when, place: "Chicago", latitude: 41.8781, longitude: -87.6298, equipment: "10x50 binoculars", seeing: 3, notes: "Rings nearly edge-on.\n\nTitan visible to the east.")
    let text = o.org
    #expect(text.hasPrefix("* Saturn\n["))
    #expect(text.contains(":EQUIPMENT: 10x50 binoculars"))
    #expect(text.contains(":SEEING: 3/5"))
    let back = try #require(Observation(org: text))
    #expect(back.id == o.id)
    #expect(back.object == "Saturn")
    #expect(abs(back.date.timeIntervalSince(when)) < 60)
    #expect(back.latitude == 41.8781)
    #expect(back.seeing == 3)
    #expect(back.notes == o.notes)
}

@Test func minimalEntryRoundTrips() throws {
    let o = Observation(object: "M31", date: when, place: "Backyard")
    let back = try #require(Observation(org: o.org))
    #expect(back.equipment == "" && back.seeing == nil && back.notes == "")
}

@Test func folderSaveListDelete() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "obs-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let log = ObservingLog(folder: dir)
    var a = Observation(object: "Moon", date: when, place: "Chicago")
    let b = Observation(object: "Jupiter", date: when.addingTimeInterval(3600), place: "Chicago")
    try log.save(a)
    try log.save(b)
    #expect(log.all().map(\.object) == ["Jupiter", "Moon"])
    a.notes = "Earthshine."
    try log.save(a)
    #expect(log.all().count == 2)
    #expect(log.all().first { $0.id == a.id }?.notes == "Earthshine.")
    try log.delete(id: b.id)
    #expect(log.all().map(\.object) == ["Moon"])
    #expect(log.fileURL(for: a).lastPathComponent.hasSuffix("-moon.org"))
}
