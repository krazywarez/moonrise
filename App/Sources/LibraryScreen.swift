import CoreLocation
import Library
import SkyEngine
import SkyRenderer
import SwiftUI

private let ink = Color(red: 0.95, green: 0.95, blue: 0.93)
private let accent = Color(red: 0.88, green: 0.24, blue: 0.19)
private let pageBackground = Color.black
private let tile = Color(white: 0.08)

/// The observer from Settings (a chosen city) or the last known location, else Chicago.
private func libraryObserver() -> Observer {
    let d = UserDefaults.standard
    if d.string(forKey: SettingsKey.locationMode) == "city", d.object(forKey: SettingsKey.cityLatitude) != nil {
        return Observer(latitude: d.double(forKey: SettingsKey.cityLatitude), longitude: d.double(forKey: SettingsKey.cityLongitude))
    }
    if let c = CLLocationManager().location?.coordinate { return Observer(latitude: c.latitude, longitude: c.longitude) }
    return Observer(latitude: 41.8781, longitude: -87.6298)
}

/// What is well placed tonight, for the Library's front page and the Constellations section.
private struct TonightPicks: Sendable {
    var planet: Featured?
    var constellations: [LibraryPage] = []

    struct Featured: Sendable {
        var page: LibraryPage
        var best: Date
        var altitude: Double
    }

    static func compute() -> TonightPicks {
        let observer = libraryObserver()
        guard let t = try? Tonight(at: .now, from: observer) else { return TonightPicks() }
        var picks = TonightPicks()
        if let p = t.planets.first(where: { $0.best != nil }), let best = p.best, let page = Library.page(body: p.body.rawValue) {
            picks.planet = Featured(page: page, best: best.date, altitude: best.position.altitude)
        }
        // Constellations whose stars are on average more than 25° up two hours into the night.
        let when = t.start.addingTimeInterval(2 * 3600)
        let scored: [(LibraryPage, Double)] = Catalog.constellations.compactMap { c in
            guard let page = Library.page(constellation: c.id) else { return nil }
            let stars = Set(c.lines.joined()).compactMap { Catalog.starsByHR[$0] }
            guard !stars.isEmpty else { return nil }
            let alts = SkyEngine.horizontal(j2000: stars.map { $0.position(at: when) }, at: when, from: observer).map(\.altitude)
            return (page, alts.reduce(0, +) / Double(alts.count))
        }
        picks.constellations = scored.filter { $0.1 > 25 }.sorted { $0.1 > $1.1 }.map(\.0)
        return picks
    }
}

// MARK: - Front page

struct LibraryScreen: View {
    @State private var query = ""
    @State private var router = Router.shared
    @State private var picks = TonightPicks()

    private var rows: [(String, LibrarySection, [LibraryPage])] {
        let constellations = picks.constellations.isEmpty ? Library.pages(in: .constellations) : picks.constellations
        let all: [(String, LibrarySection, [LibraryPage])] = [
            ("Sun and planets", .planets, Library.pages(in: .sun) + Library.pages(in: .planets)),
            (picks.constellations.isEmpty ? "Constellations" : "Constellations up tonight", .constellations, Array(constellations.prefix(12))),
            ("Brightest stars", .stars, Array(Library.pages(in: .stars).prefix(12))),
            ("Moons", .moons, Library.pages(in: .moons)),
            ("Deep sky", .deepSky, Array(Library.pages(in: .deepSky).filter { $0.image != nil }.prefix(12))),
            ("Missions", .missions, Array(Library.pages(in: .missions).reversed().prefix(12))),
            ("Exoplanets", .exoplanets, Library.pages(in: .exoplanets)),
            ("Rockets", .rockets, Library.pages(in: .rockets).filter { $0.image != nil }),
            ("Dwarf planets", .dwarfPlanets, Library.pages(in: .dwarfPlanets)),
        ]
        return all.filter { !$0.2.isEmpty }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Library").font(.title.weight(.medium))
                        Rectangle().fill(accent).frame(width: 48, height: 5).padding(.top, 8).padding(.bottom, 14)
                        searchField
                    }
                    .padding(.horizontal, 20)

                    if query.isEmpty {
                        if let p = picks.planet { featured(p).padding(.horizontal, 20).padding(.top, 18) }
                        CardRow(title: "Explore") { exploreCards }
                        ForEach(rows, id: \.0) { title, section, pages in
                            CardRow(title: title, section: section) {
                                ForEach(pages) { PageCard(page: $0) }
                            }
                        }
                        Text("Pages draw on NASA, ESA, ESO, the IAU and other sources, listed on each page.")
                            .font(.caption2).dimmed(0.5).padding(20)
                    } else {
                        searchResults
                    }
                }
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(pageBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .foregroundStyle(ink)
        .tint(ink)
        .onChange(of: router.libraryQuery, initial: true) {
            if let q = router.libraryQuery { query = q; router.libraryQuery = nil }
        }
        .task {
            if picks.planet == nil, picks.constellations.isEmpty {
                picks = await Task.detached { TonightPicks.compute() }.value
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").dimmed(0.6).accessibilityHidden(true)
            TextField("Search 370 pages: Saturn, Orion, M42", text: $query)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").dimmed(0.6) }
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 12))
    }

    private var searchResults: some View {
        let results = Library.search(query)
        return LazyVStack(alignment: .leading, spacing: 0) {
            if results.isEmpty {
                Text("Nothing matches \u{201C}\(query)\u{201D}.").font(.subheadline).dimmed(0.7).padding(.top, 20)
            }
            ForEach(results) { page in
                NavigationLink { LibraryPageView(page: page) } label: { PageListRow(page: page, showSection: true) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func featured(_ p: TonightPicks.Featured) -> some View {
        NavigationLink { LibraryPageView(page: p.page) } label: {
            ZStack(alignment: .bottomLeading) {
                PageThumb(page: p.page, large: true)
                    .frame(height: 210)
                    .frame(maxWidth: .infinity)
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 3) {
                    Text("UP TONIGHT").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(accent)
                    Text(p.page.title).font(.title2.weight(.medium))
                    Text("Best around \(p.best.formatted(date: .omitted, time: .shortened)), \(Int(p.altitude.rounded()))° up. \(p.page.subtitle).")
                        .font(.footnote).dimmed(0.85).lineLimit(2)
                }
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Up tonight: \(p.page.title)")
    }

    @ViewBuilder
    private var exploreCards: some View {
        ExploreCard(title: "Timeline of exploration", subtitle: "From Sputnik to today", symbol: "clock.arrow.circlepath", tint: Color(red: 0.12, green: 0.16, blue: 0.24)) {
            ExplorationTimeline()
        }
        ExploreCard(title: "Scale of the universe", subtitle: "The ISS to the cosmos", symbol: "circle.dotted.circle", tint: Color(red: 0.1, green: 0.1, blue: 0.18)) {
            ScaleScreen(ink: ink, accent: accent)
        }
        if !Library.pages(in: .rockets).isEmpty {
            ExploreCard(title: "Rockets to scale", subtitle: "\(Library.pages(in: .rockets).count) rockets side by side", symbol: "chart.bar.xaxis", tint: Color(red: 0.2, green: 0.1, blue: 0.08)) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Every rocket in the Library at the same scale, shortest to tallest. Scroll sideways; tap one to read about it.")
                        .font(.subheadline).dimmed(0.75).padding(.horizontal, 20)
                    RocketLineup(highlight: nil, ink: ink, accent: accent)
                }
                .padding(.vertical, 12)
                    .background(Color.black.ignoresSafeArea())
                    .navigationTitle("Rockets to scale")
            }
        }
    }
}

// MARK: - Building blocks

/// A titled, horizontally scrolling row of cards, with See all when it belongs to a section.
private struct CardRow<Content: View>: View {
    var title: String
    var section: LibrarySection?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                if let section {
                    NavigationLink { SectionScreen(section: section) } label: {
                        HStack(spacing: 3) {
                            Text("See all \(Library.pages(in: section).count)")
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }
                        .font(.subheadline)
                        .dimmed(0.7)
                    }
                    .accessibilityLabel("See all \(section.title)")
                }
            }
            .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) { content }
                    .padding(.horizontal, 20)
            }
            .scrollClipDisabled()
        }
        .padding(.top, 26)
    }
}

/// A page as a card: picture or drawing, title, up to two lines of subtitle.
struct PageCard: View {
    var page: LibraryPage
    var width: CGFloat = 150

    var body: some View {
        NavigationLink { LibraryPageView(page: page) } label: {
            VStack(alignment: .leading, spacing: 4) {
                PageThumb(page: page)
                    .frame(width: width, height: width * 0.72)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Text(page.title).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(page.subtitle).font(.caption).dimmed(0.65).lineLimit(2, reservesSpace: true)
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ExploreCard<Destination: View>: View {
    var title: String
    var subtitle: String
    var symbol: String
    var tint: Color
    @ViewBuilder var destination: Destination

    var body: some View {
        NavigationLink { destination } label: {
            VStack(alignment: .leading, spacing: 4) {
                ZStack {
                    tint
                    Image(systemName: symbol).font(.system(size: 34, weight: .light)).foregroundStyle(ink.opacity(0.9))
                }
                .frame(width: 190, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                Text(title).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(subtitle).font(.caption).dimmed(0.65).lineLimit(1)
            }
            .frame(width: 190, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The page's photo, or a drawing in its place: a disc for bodies and stars, the figure for constellations.
struct PageThumb: View {
    var page: LibraryPage
    var large = false

    var body: some View {
        ZStack {
            tile
            if let image = page.image {
                // Library of Congress scans carry a frame and colour bars; crop to the plate.
                RemoteImage(url: image.url, points: large ? 640 : 260) { fallback }
                    .scaleEffect(image.url.host() == "tile.loc.gov" ? 1.45 : 1)
            } else {
                fallback
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var fallback: some View {
        let d = page.drawing
        switch d?.kind {
        case "planet", "exoplanet":
            GeometryReader { g in
                let r = min(g.size.width, g.size.height) * 0.32
                ZStack {
                    if d?.rings == true {
                        Ellipse().stroke((Color(hex: d?.color) ?? ink).opacity(0.7), lineWidth: 2)
                            .frame(width: r * 4.2, height: r * 0.9).rotationEffect(.degrees(-14))
                    }
                    Circle().fill(Color(hex: d?.color) ?? ink.opacity(0.5)).frame(width: 2 * r, height: 2 * r)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case "constellation":
            ConstellationFigure(id: page.link.constellation, ink: ink).padding(large ? 20 : 6)
        case "star":
            let c = starColor(d?.colorIndex ?? 0.6)
            ZStack {
                Circle().fill(RadialGradient(colors: [c.opacity(0.55), c.opacity(0)], center: .center, startRadius: 4, endRadius: large ? 90 : 46))
                    .frame(width: large ? 180 : 92, height: large ? 180 : 92)
                Circle().fill(c).frame(width: large ? 30 : 16, height: large ? 30 : 16)
                    .shadow(color: c, radius: 6)
            }
        default:
            Image(systemName: symbol).font(.system(size: 28, weight: .light)).dimmed(0.6)
        }
    }

    private var symbol: String {
        switch page.section {
        case .missions: "antenna.radiowaves.left.and.right"
        case .rockets: "airplane.departure"
        case .deepSky: "sparkles"
        default: "circle"
        }
    }

    /// Star tint from B−V colour index.
    private func starColor(_ bv: Double) -> Color {
        let t = min(max((bv + 0.3) / 2.0, 0), 1)
        return Color(red: 0.62 + 0.38 * t, green: 0.76 - 0.12 * t, blue: 1.0 - 0.62 * t)
    }
}

struct PageListRow: View {
    var page: LibraryPage
    var showSection = false

    var body: some View {
        HStack(spacing: 12) {
            PageThumb(page: page)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(page.title).font(.body)
                Text(showSection ? "\(page.section.title) · \(page.subtitle)" : page.subtitle).font(.caption).dimmed(0.65).lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).dimmed(0.4)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(ink.opacity(0.12)).frame(height: 0.5) }
        .contentShape(Rectangle())
    }
}

// MARK: - Section

struct SectionScreen: View {
    var section: LibrarySection
    @State private var tonight: [LibraryPage] = []

    private var pages: [LibraryPage] { Library.pages(in: section) }

    private var intro: String {
        switch section {
        case .sun: "Our star."
        case .planets: "The eight planets, from Mercury out to Neptune."
        case .dwarfPlanets: "Worlds big enough to be round that haven't cleared their orbits."
        case .moons: "The major moons of the solar system, by planet."
        case .constellations: "The 88 official star patterns, with the ones up tonight first."
        case .stars: "The brightest stars in the night sky, brightest first."
        case .deepSky: "Galaxies, nebulae and star clusters from Messier's catalogue."
        case .exoplanets: "Planets around other stars, from the first finds to Webb targets."
        case .missions: "Spacecraft that changed what we know, newest first."
        case .rockets: "Launch vehicles past and present."
        }
    }

    private static let zodiac = ["Ari", "Tau", "Gem", "Cnc", "Leo", "Vir", "Lib", "Sco", "Sgr", "Cap", "Aqr", "Psc"]

    /// Card rows for big sections; small sections are one grid.
    private var groups: [(String, [LibraryPage])] {
        switch section {
        case .constellations:
            return [("Up tonight", Array(tonight.prefix(14))),
                    ("Zodiac", Self.zodiac.compactMap { Library.page(constellation: $0) })]
        case .stars:
            return [("Brightest", Array(pages.prefix(12)))]
        case .deepSky:
            let by: (Set<String>) -> [LibraryPage] = { types in pages.filter { types.contains($0.drawing?.type ?? "") } }
            return [("Galaxies", by(["galaxy"])), ("Nebulae", by(["nebula", "planetary", "supernova-remnant"])),
                    ("Globular clusters", by(["globular"])), ("Open clusters", by(["open"]))]
        case .moons:
            var order: [String] = []
            var byPlanet: [String: [LibraryPage]] = [:]
            for p in pages {
                let planet = p.id == "moon" ? "Earth" : (p.subtitle.components(separatedBy: " of ").last ?? "Other")
                if byPlanet[planet] == nil { order.append(planet) }
                byPlanet[planet, default: []].append(p)
            }
            return order.map { (byPlanet[$0]!.count == 1 && $0 == "Earth" ? "Earth" : "Moons of \($0)", byPlanet[$0]!) }
        case .missions:
            let byDecade = Dictionary(grouping: pages) { p in p.drawing?.launch.map { "\($0.prefix(3))0s" } ?? "Other" }
            return byDecade.keys.sorted(by: >).map { ($0, byDecade[$0]!.reversed()) }
        case .rockets:
            return [("Flying now", pages.filter { $0.drawing?.status != "retired" }), ("Retired", pages.filter { $0.drawing?.status == "retired" })]
        default:
            return []
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(section.title).font(.title.weight(.medium))
                    Rectangle().fill(accent).frame(width: 48, height: 5).padding(.top, 8).padding(.bottom, 12)
                    Text(intro).font(.subheadline).dimmed(0.75)
                }
                .padding(.horizontal, 20)

                if groups.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14, alignment: .top)], spacing: 18) {
                        ForEach(pages) { PageCard(page: $0, width: 160) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                } else {
                    ForEach(groups.filter { !$0.1.isEmpty }, id: \.0) { title, items in
                        CardRow(title: title) { ForEach(items) { PageCard(page: $0) } }
                    }
                    if pages.count > 12 {
                        Text("All, A to Z").font(.headline).padding(.horizontal, 20).padding(.top, 30).padding(.bottom, 4)
                        LazyVStack(spacing: 0) {
                            ForEach(pages.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) { page in
                                NavigationLink { LibraryPageView(page: page) } label: { PageListRow(page: page) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .foregroundStyle(ink)
        .background(pageBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if section == .constellations, tonight.isEmpty {
                tonight = await Task.detached { TonightPicks.compute().constellations }.value
            }
        }
    }
}

// MARK: - Page

struct LibraryPageView: View {
    var page: LibraryPage

    /// Up to three facts short enough to show as chips.
    private var keyFacts: [LibraryPage.Fact] {
        Array(page.facts.filter { $0.value.count <= 26 && !["Abbreviation", "Genitive", "Colour index (B−V)", "Spectral type"].contains($0.label) }.prefix(3))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let image = page.image {
                    hero(image)
                } else {
                    plainHeader.padding(.top, 8)
                }

                VStack(alignment: .leading, spacing: 0) {
                    if !keyFacts.isEmpty { chips.padding(.top, 16) }
                    actions.padding(.top, 12)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(page.paragraphs, id: \.self) { Text($0).font(.body).lineSpacing(3) }
                    }
                    .padding(.top, 20)

                    if page.image != nil, page.drawing != nil {
                        PageDrawing(page: page, ink: ink, accent: accent).padding(.top, 24)
                    }
                }
                .padding(.horizontal, 20)
                .readableWidth()

                let related = page.related()
                if !related.isEmpty {
                    CardRow(title: "Related") { ForEach(related) { PageCard(page: $0, width: 130) } }
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text("Facts").font(.headline).padding(.top, 30).padding(.bottom, 10)
                    facts
                    sources.padding(.top, 24).padding(.bottom, 32)
                }
                .padding(.horizontal, 20)
                .readableWidth()
            }
        }
        .ignoresSafeArea(.container, edges: page.image == nil ? [] : .top)
        .foregroundStyle(ink)
        .background(pageBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func hero(_ image: LibraryPage.Image) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Color(white: 0.06)
                    .frame(height: 340)
                    .overlay {
                        RemoteImage(url: image.url, points: 900) { ProgressView().tint(ink) }
                    }
                    .clipped()
                    .accessibilityLabel(image.caption)
                LinearGradient(colors: [.clear, .black], startPoint: .init(x: 0.5, y: 0.45), endPoint: .bottom)
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(page.section.title).font(.caption2.weight(.medium)).textCase(.uppercase).tracking(0.8).dimmed(0.75)
                    Text(page.title).font(.largeTitle.weight(.medium))
                    Text(page.subtitle).font(.subheadline).dimmed(0.85)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(image.caption).font(.caption).dimmed(0.6)
                Link(destination: image.page) {
                    Text("\(image.credit) · \(image.licence)").font(.caption2).dimmed(0.45)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
    }

    private var plainHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(page.section.title).font(.caption2.weight(.medium)).textCase(.uppercase).tracking(0.8).dimmed(0.6)
            Text(page.title).font(.largeTitle.weight(.medium)).padding(.top, 4)
            Text(page.subtitle).font(.subheadline).dimmed(0.75).padding(.top, 2)
            Rectangle().fill(accent).frame(width: 48, height: 5).padding(.top, 10).padding(.bottom, 16)
            PageDrawing(page: page, ink: ink, accent: accent)
        }
        .padding(.horizontal, 20)
        .readableWidth()
    }

    private var chips: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(keyFacts, id: \.self) { f in
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.label).font(.caption2).dimmed(0.6).lineLimit(2)
                    Text(f.value).font(.footnote.weight(.medium).monospacedDigit()).lineLimit(2)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        let story = MissionStory.story(page: page.id)
        let globe = page.drawing?.kind == "planet"
        if story != nil || globe {
            HStack(spacing: 8) {
                if globe {
                    NavigationLink { GlobeView(page: page, credit: GlobeMaps.credit[page.id]) } label: { pill("View as a globe", "globe") }
                }
                if let story {
                    NavigationLink { StoryScreen(story: story) } label: { pill("Follow the mission", "point.topleft.down.to.point.bottomright.curvepath") }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func pill(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .overlay(Capsule().stroke(ink.opacity(0.35), lineWidth: 0.5))
    }

    private var facts: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            ForEach(page.facts, id: \.self) { f in
                GridRow(alignment: .firstTextBaseline) {
                    Text(f.label).font(.footnote).dimmed(0.6)
                    Text(f.value).font(.subheadline.monospacedDigit())
                }
                .accessibilityElement(children: .combine)
                Divider().overlay(ink.opacity(0.15))
            }
        }
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sources").font(.caption2.weight(.medium)).textCase(.uppercase).tracking(0.8).dimmed(0.6)
            ForEach(Array(page.sources.enumerated()), id: \.offset) { i, s in
                Link(destination: s.url) {
                    Text("\(i + 1). \(s.title)").font(.caption).underline().dimmed(0.8).multilineTextAlignment(.leading)
                }
            }
        }
    }
}
