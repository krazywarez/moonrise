import Foundation
import SkyEngine
import Testing
@testable import Library
@testable import SkyRenderer

// Checks every bundled page against the rules in docs/library-content.org.

let allowedLicences: Set<String> = ["Public domain", "CC BY 4.0", "CC BY-SA 3.0 IGO"]

@Test func idsAreUnique() {
    let ids = Library.pages.map(\.id)
    #expect(Set(ids).count == ids.count, "duplicates: \(Dictionary(grouping: ids, by: { $0 }).filter { $1.count > 1 }.keys.sorted())")
}

@Test(arguments: Library.pages)
func pageFollowsTheBrief(_ p: LibraryPage) {
    #expect(!p.title.isEmpty && !p.subtitle.isEmpty, "\(p.id): title/subtitle")
    #expect((1...5).contains(p.sources.count), "\(p.id): \(p.sources.count) sources")
    #expect((3...9).contains(p.facts.count), "\(p.id): \(p.facts.count) facts")
    for f in p.facts {
        #expect(p.sources.indices.contains(f.source), "\(p.id): fact '\(f.label)' cites missing source \(f.source)")
    }
    #expect(!p.sources.contains { $0.url.host()?.contains("wikipedia.org") == true }, "\(p.id): Wikipedia as a source")
    #expect((120...300).contains(p.wordCount), "\(p.id): essay \(p.wordCount) words")
    if let image = p.image {
        #expect(allowedLicences.contains(image.licence), "\(p.id): licence \(image.licence)")
        #expect(image.url.scheme == "https", "\(p.id): image URL")
        #expect(!image.credit.isEmpty, "\(p.id): image credit")
    } else {
        #expect([.constellations, .stars, .missions, .rockets].contains(p.section), "\(p.id): missing image")
    }
}

@Test(arguments: Library.pages)
func linksPointAtThingsTheAppKnows(_ p: LibraryPage) {
    let l = p.link
    if let body = l.body { #expect(Body(rawValue: body) != nil, "\(p.id): body \(body)") }
    if let c = l.constellation { #expect(constellationNames[c] != nil, "\(p.id): constellation \(c)") }
    if let hr = l.hr { #expect(Catalog.stars.contains { $0.hr == hr }, "\(p.id): HR \(hr)") }
    if let m = l.messier { #expect((1...110).contains(m), "\(p.id): M\(m)") }
    if let s = l.spacecraft { #expect(Spacecraft.all.contains { $0.name == s }, "\(p.id): spacecraft \(s)") }
}

@Test func chartMessierObjectsOpenTheirPages() {
    for o in Catalog.deepSky {
        #expect(Library.page(id: o.page)?.link.messier == o.messier, "M\(o.messier): page \(o.page)")
    }
}

@Test func searchFindsByTitleBeforeEssay() {
    guard let first = Library.pages.first else { return }
    #expect(Library.search(first.title).first?.id == first.id)
    #expect(Library.search("   ").isEmpty)
}

@Test func searchMatchesFoldedStringContains() {
    let index = Library.pages.map { p in
        (p, Library.fold(p.title + "\n" + p.subtitle), Library.fold(p.essay + "\n" + p.facts.map(\.value).joined(separator: "\n")))
    }
    func reference(_ query: String) -> [String] {
        let q = Library.fold(query.trimmingCharacters(in: .whitespaces))
        guard !q.isEmpty else { return [] }
        let strong = index.filter { $0.1.contains(q) || $0.0.id == q }
        let weak = index.filter { !($0.1.contains(q) || $0.0.id == q) && $0.2.contains(q) }
        return (strong + weak).map(\.0.id)
    }
    let queries = [
        "a", "m", "z", "q", "x", "1", ".", "-", "–", "°", "(",
        "Señor", "señor", "SENOR", "Cygnus", "cygnus", "CYGNUS", "Cýgnus", "Méchain", "Ångström", "Tycho Brahe", "Kuiper",
        "andromeda galaxy", "  Orion Nebula  ", "great red spot", "black hole", "light-years", "main sequence", "Hubble's",
        "zzzz", "xyzzy", "qqqq q",
        "M1", "M31", "m42", "M 13", "Messier 101", "NGC 224", "HR 2491",
        "α", "α Centauri", "Alpha Centauri", "β", "ω Centauri", "Omega", "ε Eridani", "η Carinae", "Σ", "σ",
        Library.pages[0].id, Library.pages.last!.id,
    ] + stride(from: 0, to: Library.pages.count, by: 10).map { Library.pages[$0].title }
    for q in queries {
        #expect(Library.search(q).map(\.id) == reference(q), "\(q)")
    }
}

@Test func scaleObjectsComeFromPages() {
    let objects = Library.scaleObjects
    #expect(objects.first?.name == "ISS")
    #expect(objects.last?.name == "Observable universe")
    #expect(objects.contains { $0.name == "Earth" && abs($0.meters - 12_742_000) < 1 })
    #expect(objects.contains { $0.page == "arcturus" })
    #expect(objects.contains { $0.page == "m31" })
    #expect(Set(objects.map(\.name)).count == objects.count)
    for o in objects where o.page != nil { #expect(Library.page(id: o.page!) != nil, "\(o.name)") }
}

@Test func scaleSizeFormats() {
    #expect(Library.formatSize(109) == "109 m")
    #expect(Library.formatSize(12_742_000) == "12,742 km")
    #expect(Library.formatSize(2 * 30.07 * 1.495978707e11) == "60.1 AU")
    #expect(Library.formatSize(100_000 * 9.4607e15) == "100,000 light-years")
    #expect(Library.formatSize(93e9 * 9.4607e15) == "93 billion light-years")
}

@Test func toursPointAtKnownThings() {
    #expect(Tour.all.count == 4)
    let constellations = Set(Catalog.constellations.map(\.id))
    let stars = Set(Catalog.stars.map(\.hr))
    for tour in Tour.all {
        #expect(!tour.steps.isEmpty)
        for step in tour.steps {
            let t = step.target
            #expect([t.constellation != nil, t.hr != nil, t.body != nil].filter { $0 }.count == 1, "\(tour.id) \(step.title)")
            if let c = t.constellation { #expect(constellations.contains(c), "\(c)") }
            if let hr = t.hr { #expect(stars.contains(hr), "\(hr)") }
            if let p = step.page { #expect(Library.page(id: p) != nil, "\(p)") }
        }
    }
    #expect(Set(Tour.all.flatMap(\.months)) == Set(1...12))
}

@Test func toursStartWithTheSeason() {
    #expect(Tour.ordered(month: 1).first?.id == "winter")
    #expect(Tour.ordered(month: 7).first?.id == "summer")
    #expect(Tour.ordered(month: 11).map(\.id) == ["autumn", "winter", "spring", "summer"])
}

@Test func storiesMatchSpacecraftAndPages() {
    #expect(MissionStory.all.count == 5)
    let craft = Set(Spacecraft.all.map(\.name))
    for s in MissionStory.all {
        #expect(craft.contains(s.spacecraft), "\(s.spacecraft)")
        #expect(Library.page(id: s.page)?.link.spacecraft == s.spacecraft, "\(s.page)")
        let days = s.chapters.map(\.day)
        #expect(days == days.sorted(), "\(s.page) chapters out of order")
        // After launch, every chapter falls within the trajectory data (which starts up to 30 days after launch).
        let craftData = Spacecraft.all.first { $0.name == s.spacecraft }!
        for c in s.chapters.dropFirst() { #expect(craftData.position(at: c.day) != nil, "\(s.page) \(c.date)") }
    }
}

@Test func relatedPages() throws {
    let saturn = try #require(Library.page(id: "saturn"))
    let related = saturn.related().map(\.id)
    #expect(related.contains("titan"))
    #expect(related.contains("cassini-huygens"))
    #expect(!related.contains("saturn"))
    #expect(related.count <= 10)
    #expect(Library.page(id: "europa")!.related().first?.id == "jupiter")
}
