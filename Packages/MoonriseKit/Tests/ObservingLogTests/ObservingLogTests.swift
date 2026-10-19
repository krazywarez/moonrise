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

@Test func equipmentIDsRoundTrip() throws {
    let o = Observation(object: "M13", date: when, place: "Backyard", equipment: "8-inch Dobsonian, 25 mm Plössl", equipmentIDs: ["scope-1", "ep-2"])
    #expect(o.org.contains(":EQUIPMENT: 8-inch Dobsonian, 25 mm Plössl\n:EQUIPMENT_IDS: scope-1 ep-2\n"))
    let back = try #require(Observation(org: o.org))
    #expect(back.equipment == o.equipment)
    #expect(back.equipmentIDs == ["scope-1", "ep-2"])
}

@Test func freeTextEquipmentStillParses() throws {
    let text = "* Saturn\n[2026-10-16 Fri 21:00]\n:PROPERTIES:\n:ID: abc\n:EQUIPMENT: 10x50 binoculars\n:END:\n"
    let o = try #require(Observation(org: text))
    #expect(o.equipment == "10x50 binoculars")
    #expect(o.equipmentIDs.isEmpty)
}

@Test func equipmentOrgRoundTrip() throws {
    let scope = Equipment(kind: .telescope, name: "8-inch Dobsonian", aperture: 203, focalLength: 1200, notes: "Collimated in May.")
    let text = scope.org
    #expect(text.hasPrefix("* 8-inch Dobsonian\n:PROPERTIES:\n"))
    #expect(text.contains(":TYPE: telescope\n"))
    #expect(text.contains(":APERTURE: 203 mm\n"))
    #expect(text.contains(":FOCAL_LENGTH: 1200 mm\n"))
    #expect(text.contains(":FOCAL_RATIO: f/5.9\n"))
    #expect(!text.contains(":RETIRED:"))
    let back = try #require(Equipment(org: text))
    #expect(back == scope)

    let binos = Equipment(kind: .binoculars, name: "10x50", aperture: 50, magnification: 10, fieldOfView: 6.5, retired: true)
    #expect(binos.org.contains(":MAGNIFICATION: 10x\n"))
    #expect(binos.org.contains(":FIELD_OF_VIEW: 6.5°\n"))
    #expect(binos.org.contains(":RETIRED: t\n"))
    #expect(Equipment(org: binos.org) == binos)

    let cam = Equipment(kind: .camera, name: "ZWO", sensor: "IMX585")
    #expect(Equipment(org: cam.org) == cam)
}

@Test func inventorySaveListDelete() throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "eq-\(UUID().uuidString)/Equipment.org")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let inv = EquipmentInventory(file: file)
    #expect(inv.all().isEmpty)
    var scope = Equipment(kind: .telescope, name: "Dob", aperture: 203, notes: "Line one.\n\nLine two.")
    let ep = Equipment(kind: .eyepiece, name: "25 mm Plössl", focalLength: 25, fieldOfView: 52)
    try inv.save(scope)
    try inv.save(ep)
    #expect(inv.all() == [scope, ep])
    scope.retired = true
    try inv.save(scope)
    #expect(inv.all() == [scope, ep])
    #expect(try String(contentsOf: file, encoding: .utf8).hasPrefix("#+title: Equipment\n"))
    try inv.delete(id: scope.id)
    #expect(inv.all() == [ep])
}

@Test func equipmentUsage() throws {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: 3))! }
    let log = [
        Observation(object: "Saturn", date: day(2026, 1, 10), place: "", equipmentIDs: ["scope", "ep25"], seeing: 4),
        Observation(object: "saturn ", date: day(2026, 7, 10), place: "", equipmentIDs: ["scope", "ep25"], seeing: 2),
        Observation(object: "M31", date: day(2026, 10, 10), place: "", equipmentIDs: ["scope", "ep10"]),
        Observation(object: "Moon", date: day(2026, 10, 11), place: "", latitude: -33.9, longitude: 18.4, equipmentIDs: ["scope"], seeing: 3),
        Observation(object: "Jupiter", date: day(2026, 3, 1), place: "", equipmentIDs: ["binos"]),
        Observation(object: "Mars", date: day(2026, 3, 2), place: "", equipment: "Telescope"),
    ]
    let u = EquipmentUsage(of: "scope", in: log, calendar: cal)
    #expect(u.observations == 4)
    #expect(u.first == day(2026, 1, 10))
    #expect(u.last == day(2026, 10, 11))
    #expect(u.distinctObjects == 3)
    #expect(u.topObjects.first == .init(key: "Saturn", count: 2))
    #expect(u.byMonth == [1, 0, 0, 0, 0, 0, 1, 0, 0, 2, 0, 0])
    #expect(u.bySeason == [.winter: 1, .summer: 1, .autumn: 1, .spring: 1])
    #expect(u.averageSeeing == 3)
    #expect(u.usedWith == [.init(key: "ep25", count: 2), .init(key: "ep10", count: 1)])

    let none = EquipmentUsage(of: "camera", in: log, calendar: cal)
    #expect(none.observations == 0 && none.first == nil && none.averageSeeing == nil && none.usedWith.isEmpty)
}
