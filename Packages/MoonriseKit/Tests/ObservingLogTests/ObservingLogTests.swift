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

@Test func observationKeepsHandAddedProperties() throws {
    let text = "* Saturn\n[2026-10-16 Fri 21:00]\n:PROPERTIES:\n:ID: abc\n:TRANSPARENCY: 4/5\n:PLACE: Chicago\n:CATEGORY: planet\n:BORTLE:\n:END:\n\nRings.\n"
    var o = try #require(Observation(org: text))
    o.notes = "Rings and Titan."
    let out = o.org
    #expect(out.contains(":PLACE: Chicago\n:TRANSPARENCY: 4/5\n:CATEGORY: planet\n:BORTLE:\n:END:\n"))
    #expect(Observation(org: out) == o)
}

@Test func equipmentKeepsHandAddedProperties() throws {
    let text = "* Dob\n:PROPERTIES:\n:ID: scope-1\n:TYPE: telescope\n:PURCHASED: 2019-05-02\n:APERTURE: 203 mm\n:FOCAL_RATIO: f/5.9\n:SERIAL: X123\n:END:\n"
    var scope = try #require(Equipment(org: text))
    scope.focalLength = 1200
    let out = scope.org
    #expect(out.contains(":FOCAL_RATIO: f/5.9\n:PURCHASED: 2019-05-02\n:SERIAL: X123\n:END:\n"))
    #expect(Equipment(org: out) == scope)
}

@Test func catalogAndOffsetRoundTrip() throws {
    let o = Observation(object: "M31", date: when, place: "Chicago", catalog: ["M31", "NGC224"], utcOffset: -5 * 3600)
    let text = o.org
    #expect(text.hasPrefix("* M31\n[2026-10-16 Fri 21:00]\n:PROPERTIES:\n"))
    #expect(text.contains(":CATALOG: M31 NGC224\n:PLACE: Chicago\n:UTC_OFFSET: -05:00\n"))
    #expect(Observation(org: text) == o)

    let india = try #require(Observation(org: "* M42\n[2026-10-17 Sat 07:30]\n:PROPERTIES:\n:ID: x\n:UTC_OFFSET: +05:30\n:END:\n"))
    #expect(india.date == when)
    #expect(india.utcOffset == 19_800)
    #expect(india.otherProperties.isEmpty)
}

@Test func entryWithoutOffsetReadsInDeviceZone() throws {
    let text = "* Saturn\n[2026-10-16 Fri 21:00]\n:PROPERTIES:\n:ID: abc\n:END:\n"
    let o = try #require(Observation(org: text))
    #expect(o.utcOffset == nil)
    #expect(o.date.formatted(Observation.orgDate(.current)) == "2026-10-16 Fri 21:00")
    #expect(!o.org.contains(":UTC_OFFSET:"))
}

@Test func saveStampsOffsetAndCatalog() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "obs-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let log = ObservingLog(folder: dir)
    let resolver = CatalogResolver(names: ["andromeda galaxy": "M31"])

    try log.save(Observation(id: "a", object: "Messier 31", date: when, place: ""), resolver: resolver)
    let a = try #require(log.all().first)
    #expect(a.catalog == ["M31"])
    #expect(a.utcOffset == TimeZone.current.secondsFromGMT(for: when))

    // A name that doesn't resolve keeps the IDs it was logged with; one that does replaces them.
    var b = Observation(id: "b", object: "Andromeda core", date: when, place: "", catalog: ["M31"], utcOffset: 3600)
    try log.save(b, resolver: resolver)
    b = try #require(log.all().first { $0.id == "b" })
    #expect(b.catalog == ["M31"] && b.utcOffset == 3600)
    b.object = "M 33"
    try log.save(b, resolver: resolver)
    #expect(log.all().first { $0.id == "b" }?.catalog == ["M33"])

    try log.save(Observation(id: "c", object: "Saturn", date: when, place: ""), resolver: resolver)
    #expect(log.all().first { $0.id == "c" }?.catalog == [])
}

@Test func equipmentUsageGroupsByCatalogue() throws {
    let resolver = CatalogResolver(names: ["andromeda galaxy": "M31"])
    let log = [
        Observation(object: "M31", date: when, place: "", equipmentIDs: ["scope"]),
        Observation(object: "Andromeda Galaxy", date: when, place: "", equipmentIDs: ["scope"]),
        Observation(object: "Core of Andromeda", date: when, place: "", equipmentIDs: ["scope"], catalog: ["M31"]),
        Observation(object: "Saturn", date: when, place: "", equipmentIDs: ["scope"]),
    ]
    let u = EquipmentUsage(of: "scope", in: log, resolver: resolver)
    #expect(u.distinctObjects == 2)
    #expect(u.topObjects == [.init(key: "M31", count: 3), .init(key: "Saturn", count: 1)])
}
