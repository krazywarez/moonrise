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

@Test func searchFindsByTitleBeforeEssay() {
    guard let first = Library.pages.first else { return }
    #expect(Library.search(first.title).first?.id == first.id)
    #expect(Library.search("   ").isEmpty)
}
