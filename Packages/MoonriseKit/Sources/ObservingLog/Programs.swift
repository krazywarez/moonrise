import Foundation
import Library
import SkyRenderer

/// Maps object names in log entries and program lists to catalogue IDs such as "M31" or "NGC6205".
/// Only exact matches after normalisation count.
public struct CatalogResolver: Sendable {
    /// Folded name (see `fold`) to ID.
    public var names: [String: String]

    public init(names: [String: String] = [:]) {
        self.names = names
    }

    /// Names from the programs' aliases; the first program to use a name keeps it.
    public init(programs: [ObservingProgram]) {
        var names: [String: String] = [:]
        for p in programs {
            for o in p.objects {
                for a in o.aliases where names[Self.fold(a)] == nil { names[Self.fold(a)] = o.id }
            }
        }
        self.init(names: names)
    }

    /// Messier common names from the Library.
    public static let messier = CatalogResolver(programs: [.messier])

    /// "M 31", "Messier 31" and "m031" give "M31"; "NGC 6205" gives "NGC6205". Nil when `s` is not letters then a number.
    /// Letters are ASCII, then optional spaces, then one or more `Character.isNumber` characters.
    public static func designation(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces)
        var i = t.startIndex
        while i < t.endIndex, t[i].isASCII, t[i].isLetter { t.formIndex(after: &i) }
        guard i > t.startIndex else { return nil }
        let prefix = t[..<i].uppercased()
        while i < t.endIndex, t[i] == " " { t.formIndex(after: &i) }
        var number = t[i...]
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }
        while number.count > 1, number.first == "0" { number = number.dropFirst() }
        return (prefix == "MESSIER" ? "M" : prefix) + number
    }

    /// Case, diacritics, curly apostrophes and runs of spaces ignored.
    public static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// A known name's ID, else the designation.
    public func id(for name: String) -> String? {
        names[Self.fold(name)] ?? Self.designation(name)
    }

    /// What an entry counts as: its `:CATALOG:` IDs, else the resolved name, else the folded name.
    public func keys(for o: Observation) -> [String] {
        if !o.catalog.isEmpty { return o.catalog.map { Self.designation($0) ?? $0 } }
        return [id(for: o.object) ?? Self.fold(o.object)]
    }
}

/// A list of objects to observe: the bundled Messier list, or an Org file in the log's Programs folder.
///
/// Program file format, one top-level heading per object:
///
///     #+TITLE: Autumn clusters
///     * Double Cluster
///     :PROPERTIES:
///     :CATALOG: NGC869 NGC884
///     :RA: 34.75
///     :DEC: 57.13
///     :END:
///     * M45
///
/// The heading is the object's name. `:CATALOG:` gives its IDs, else the heading is resolved as in
/// `CatalogResolver`, else the object is matched by name. `:RA:` and `:DEC:` are J2000 degrees; Messier
/// objects without them take the bundled position. Other lines and lower-level headings are ignored.
/// Without `#+TITLE:` the file name is the title.
public struct ObservingProgram: Sendable, Identifiable, Equatable {
    public struct Object: Sendable, Identifiable, Equatable {
        /// Catalogue IDs; the first is `id`. Empty when the object is matched by name.
        public var ids: [String]
        public var name: String
        /// Other names the object is logged under.
        public var aliases: [String]
        public var detail: String
        /// J2000, degrees.
        public var ra: Double?
        public var dec: Double?

        public var id: String { ids.first ?? CatalogResolver.fold(name) }
        var keys: [String] { ids.isEmpty ? [id] : ids }

        /// Applies one drawer property from a program file.
        mutating func apply(_ p: OrgProperty) {
            switch p.key {
            case ":CATALOG:":
                ids = p.value.split(separator: " ").map { CatalogResolver.designation(String($0)) ?? String($0) }
                if CatalogResolver.designation(name) == nil { aliases = [name] }
            case ":RA:": ra = Double(p.value)
            case ":DEC:": dec = Double(p.value)
            default: break
            }
        }
    }

    public var id: String
    public var title: String
    public var objects: [Object]

    public init(id: String, title: String, objects: [Object]) {
        self.id = id
        self.title = title
        self.objects = objects
    }

    /// All 110, from the Library's deep-sky pages and the sky chart's OpenNGC positions. The common name is the
    /// page subtitle before " · ". M102 is matched only by number and has no position, as on the chart: OpenNGC
    /// lists it as a duplicate of M101 (scripts/make-messier.py).
    public static let messier: ObservingProgram = {
        let positions = Dictionary(uniqueKeysWithValues: Catalog.deepSky.map { ($0.messier, $0) })
        let objects = Library.pages(in: .deepSky).compactMap { page -> (Int, Object)? in
            guard let m = page.link.messier else { return nil }
            let parts = page.subtitle.components(separatedBy: " · ")
            let alias = parts.count > 1 && m != 102 ? [parts[0]] : []
            return (m, Object(ids: ["M\(m)"], name: "M\(m)", aliases: alias, detail: page.subtitle, ra: positions[m]?.ra, dec: positions[m]?.dec))
        }
        return ObservingProgram(id: "messier", title: "Messier", objects: objects.sorted { $0.0 < $1.0 }.map(\.1))
    }()

    /// Parses a program file (format above). Names resolve against `resolver`.
    public init(org text: String, id: String, resolver: CatalogResolver = .messier) {
        var parser = ProgramFileParser(title: id, resolver: resolver)
        for line in text.components(separatedBy: "\n") {
            parser.read(line)
        }
        let title = parser.title
        var objects = parser.objects
        for i in objects.indices where objects[i].ra == nil || objects[i].dec == nil {
            if let m = Self.messier.objects.first(where: { $0.id == objects[i].id }) {
                objects[i].ra = m.ra
                objects[i].dec = m.dec
            }
        }
        self.init(id: id, title: title.isEmpty ? id : title, objects: objects)
    }
}

/// Earliest entry for each catalogue key in a log. Build it once per log and share it between programs.
public struct LogIndex: Sendable {
    public var earliest: [String: Observation]

    public init(log: [Observation], resolver: CatalogResolver) {
        var earliest: [String: Observation] = [:]
        for o in log {
            for k in resolver.keys(for: o) where o.date < earliest[k]?.date ?? .distantFuture { earliest[k] = o }
        }
        self.earliest = earliest
    }
}

/// Which objects of a program the log has, derived each time and never stored.
public struct ProgramProgress: Sendable {
    /// Earliest entry for each logged object, by object ID.
    public var first: [String: Observation]

    public var count: Int { first.count }

    public init(program: ObservingProgram, log: [Observation], resolver: CatalogResolver) {
        self.init(program: program, index: LogIndex(log: log, resolver: resolver))
    }

    public init(program: ObservingProgram, index: LogIndex) {
        var first: [String: Observation] = [:]
        for object in program.objects {
            if let o = object.keys.compactMap({ index.earliest[$0] }).min(by: { $0.date < $1.date }) { first[object.id] = o }
        }
        self.first = first
    }
}

/// Reads a program file line by line: its title, its headings, and their drawers.
private struct ProgramFileParser {
    var title: String
    let resolver: CatalogResolver
    var objects: [ObservingProgram.Object] = []
    var inDrawer = false

    init(title: String, resolver: CatalogResolver) {
        self.title = title
        self.resolver = resolver
    }

    mutating func read(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if line.lowercased().hasPrefix("#+title:") {
            title = line.dropFirst(8).trimmingCharacters(in: .whitespaces)
            return
        }
        if line.hasPrefix("* ") {
            let name = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
            let id = resolver.id(for: name)
            objects.append(ObservingProgram.Object(ids: id.map { [$0] } ?? [], name: name, aliases: [], detail: ""))
            inDrawer = false
            return
        }
        if !objects.isEmpty, trimmed == ":PROPERTIES:" {
            inDrawer = true
            return
        }
        guard inDrawer else { return }
        if trimmed == ":END:" {
            inDrawer = false
        } else if let p = OrgProperty.parse(trimmed) {
            objects[objects.count - 1].apply(p)
        }
    }
}
