import Foundation
import Testing
@testable import ObservingLog

@Test func designations() {
    #expect(CatalogResolver.designation("M31") == "M31")
    #expect(CatalogResolver.designation("M 31") == "M31")
    #expect(CatalogResolver.designation(" messier 31 ") == "M31")
    #expect(CatalogResolver.designation("M031") == "M31")
    #expect(CatalogResolver.designation("NGC 6205") == "NGC6205")
    #expect(CatalogResolver.designation("ic434") == "IC434")
    #expect(CatalogResolver.designation("Saturn") == nil)
    #expect(CatalogResolver.designation("M31 and M32") == nil)
}

@Test func messierNamesResolve() {
    let r = CatalogResolver.messier
    for name in ["M31", "M 31", "Messier 31", "Andromeda Galaxy", "andromeda  galaxy"] {
        #expect(r.id(for: name) == "M31", "\(name)")
    }
    #expect(r.id(for: "Ptolemy’s Cluster") == "M7")
    #expect(r.id(for: "Winnecke 4") == "M40")
    #expect(r.id(for: "M102") == "M102")
    #expect(r.id(for: "Identity disputed") == nil)
    #expect(r.id(for: "Saturn") == nil)
}

@Test func messierProgramHasAll110() throws {
    let p = ObservingProgram.messier
    #expect(p.objects.map(\.id) == (1...110).map { "M\($0)" })
    let m31 = try #require(p.objects.first { $0.id == "M31" })
    #expect(m31.aliases == ["Andromeda Galaxy"])
    #expect(m31.ra != nil && m31.dec != nil)
    // M102 has no position: OpenNGC lists it as a duplicate of M101 (see scripts/make-messier.py).
    let m102 = try #require(p.objects.first { $0.id == "M102" })
    #expect(m102.ra == nil && m102.dec == nil && m102.aliases.isEmpty)
    #expect(p.objects.filter { $0.ra == nil }.count == 1)
}

@Test func programFromOrg() throws {
    let text = """
    #+TITLE: Autumn clusters
    Open clusters for a small refractor.

    * Double Cluster
    :PROPERTIES:
    :CATALOG: NGC869 NGC884
    :RA: 34.75
    :DEC: 57.13
    :END:
    Two clusters in one field.
    ** Notes
    * M 45
    * Pleiades
    * Stock 2
    * Kemble's Cascade
    """
    let p = ObservingProgram(org: text, id: "autumn-clusters")
    #expect(p.title == "Autumn clusters")
    #expect(p.objects.map(\.id) == ["NGC869", "M45", "M45", "STOCK2", "kemble's cascade"])
    #expect(p.objects.map(\.name) == ["Double Cluster", "M 45", "Pleiades", "Stock 2", "Kemble's Cascade"])
    #expect(p.objects[0].ra == 34.75 && p.objects[0].dec == 57.13)
    #expect(p.objects[0].aliases == ["Double Cluster"])
    // Messier objects take their position from the bundled catalogue.
    #expect(p.objects[1].ra == ObservingProgram.messier.objects[44].ra)
    #expect(p.objects[3].ra == nil)

    #expect(ObservingProgram(org: "* M13\n", id: "globulars").title == "globulars")

    let r = CatalogResolver(programs: [.messier, p])
    #expect(r.id(for: "double cluster") == "NGC869")
    #expect(r.id(for: "Andromeda Galaxy") == "M31")
}

@Test func programsFolder() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "obs-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let log = ObservingLog(folder: dir)
    #expect(log.programs().map(\.id) == ["messier"])
    try FileManager.default.createDirectory(at: log.programsFolder, withIntermediateDirectories: true)
    try "#+TITLE: Globulars\n* M13\n* M92\n".write(to: log.programsFolder.appending(path: "globulars.org"), atomically: true, encoding: .utf8)
    try "notes".write(to: log.programsFolder.appending(path: "readme.txt"), atomically: true, encoding: .utf8)
    #expect(log.programs().map(\.title) == ["Messier", "Globulars"])
    // Program files are not log entries.
    #expect(log.all().isEmpty)
}

@Test func progressCountsEachObjectOnce() throws {
    let resolver = CatalogResolver.messier
    let early = when.addingTimeInterval(-86_400)
    let log = [
        Observation(object: "Andromeda Galaxy", date: when, place: ""),
        Observation(object: "M 31", date: early, place: ""),
        Observation(object: "Dust lanes", date: when, place: "", catalog: ["M32"]),
        Observation(object: "Saturn", date: when, place: ""),
        Observation(object: "Kemble's Cascade", date: when, place: ""),
    ]
    let progress = ProgramProgress(program: .messier, log: log, resolver: resolver)
    #expect(progress.count == 2)
    #expect(progress.first["M31"]?.date == early)
    #expect(progress.first["M32"] != nil)

    let mine = ObservingProgram(org: "* Kemble’s Cascade\n* M31\n", id: "mine")
    #expect(ProgramProgress(program: mine, log: log, resolver: resolver).count == 2)
}
