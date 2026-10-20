import Foundation

/// A property-drawer entry the app does not use, kept so saving does not drop it.
public struct OrgProperty: Sendable, Equatable, Hashable {
    /// With colons, e.g. ":TRANSPARENCY:".
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }

    var line: String { value.isEmpty ? key : "\(key) \(value)" }

    /// Splits a drawer line into key and value; nil for lines that are not a property.
    static func parse(_ line: String) -> OrgProperty? {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        guard let key = parts.first, key.count > 2, key.hasPrefix(":"), key.hasSuffix(":") else { return nil }
        return OrgProperty(key: key, value: parts.count == 2 ? parts[1] : "")
    }
}

/// One logged observation, stored as an Org file that Emacs and orgstar can read.
public struct Observation: Sendable, Identifiable, Equatable {
    public var id: String
    public var object: String
    public var date: Date
    public var place: String
    public var latitude: Double?
    public var longitude: Double?
    /// Readable names, e.g. "Naked eye" or "8-inch Dobsonian, 25 mm Plössl". Older entries have only this.
    public var equipment: String
    /// Inventory item IDs, in the order of `equipment`.
    public var equipmentIDs: [String]
    /// 1 (poor) to 5 (excellent); nil when not noted.
    public var seeing: Int?
    public var notes: String
    /// Catalogue IDs, e.g. ["M31"]; see `CatalogResolver`.
    public var catalog: [String]
    /// Seconds east of UTC that the timestamp is written in. Nil for older entries, which are read in the device's zone.
    public var utcOffset: Int?
    /// Properties added by hand, in file order.
    public var otherProperties: [OrgProperty]

    static let knownKeys: Set = [":ID:", ":CATALOG:", ":PLACE:", ":COORDINATES:", ":UTC_OFFSET:", ":EQUIPMENT:", ":EQUIPMENT_IDS:", ":SEEING:"]

    public init(id: String = UUID().uuidString, object: String, date: Date, place: String, latitude: Double? = nil, longitude: Double? = nil, equipment: String = "", equipmentIDs: [String] = [], seeing: Int? = nil, notes: String = "", catalog: [String] = [], utcOffset: Int? = nil, otherProperties: [OrgProperty] = []) {
        self.id = id
        self.object = object
        self.date = date
        self.place = place
        self.latitude = latitude
        self.longitude = longitude
        self.equipment = equipment
        self.equipmentIDs = equipmentIDs
        self.seeing = seeing
        self.notes = notes
        self.catalog = catalog
        self.utcOffset = utcOffset
        self.otherProperties = otherProperties
    }

    static func orgDate(_ zone: TimeZone) -> Date.VerbatimFormatStyle {
        .init(format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(weekday: .abbreviated) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)", locale: Locale(identifier: "en_US_POSIX"), timeZone: zone, calendar: Calendar(identifier: .gregorian))
    }

    private var zone: TimeZone { utcOffset.flatMap(TimeZone.init(secondsFromGMT:)) ?? .current }

    /// "-05:00" for -18000.
    static func offsetText(_ seconds: Int) -> String {
        let m = abs(seconds) / 60
        return String(format: "%@%02d:%02d", seconds < 0 ? "-" : "+", m / 60, m % 60)
    }

    static func offset(_ text: String) -> Int? {
        guard let m = text.wholeMatch(of: /([+-])(\d\d):(\d\d)/), let h = Int(m.2), let min = Int(m.3) else { return nil }
        return (m.1 == "-" ? -1 : 1) * (h * 3600 + min * 60)
    }

    /// Org text: one heading with an inactive timestamp, a property drawer and the notes.
    public var org: String {
        var props = [(":ID:", id)]
        if !catalog.isEmpty { props.append((":CATALOG:", catalog.joined(separator: " "))) }
        props.append((":PLACE:", place))
        if let latitude, let longitude { props.append((":COORDINATES:", String(format: "%.4f, %.4f", latitude, longitude))) }
        if let utcOffset { props.append((":UTC_OFFSET:", Self.offsetText(utcOffset))) }
        if !equipment.isEmpty { props.append((":EQUIPMENT:", equipment)) }
        if !equipmentIDs.isEmpty { props.append((":EQUIPMENT_IDS:", equipmentIDs.joined(separator: " "))) }
        if let seeing { props.append((":SEEING:", "\(seeing)/5")) }
        var lines = ["* \(object)", "[\(date.formatted(Self.orgDate(zone)))]", ":PROPERTIES:"]
        lines += props.map { "\($0.0) \($0.1)" }
        lines += otherProperties.map(\.line)
        lines.append(":END:")
        let body = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty { lines += ["", body] }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Parses the format written by `org`. Returns nil for files it did not write.
    public init?(org text: String) {
        let lines = text.components(separatedBy: "\n")
        guard let head = lines.first, head.hasPrefix("* "),
              lines.count > 1, lines[1].hasPrefix("["), lines[1].hasSuffix("]") else { return nil }
        var props: [String: String] = [:]
        var other: [OrgProperty] = []
        var i = 2
        if i < lines.count, lines[i] == ":PROPERTIES:" {
            i += 1
            while i < lines.count, lines[i] != ":END:" {
                if let p = OrgProperty.parse(lines[i]) {
                    if !Self.knownKeys.contains(p.key) { other.append(p) } else if !p.value.isEmpty { props[p.key] = p.value }
                }
                i += 1
            }
            i += 1
        }
        let offset = props[":UTC_OFFSET:"].flatMap(Self.offset)
        guard let date = try? Date(String(lines[1].dropFirst().dropLast()), strategy: Self.orgDate(offset.flatMap(TimeZone.init(secondsFromGMT:)) ?? .current).parseStrategy) else { return nil }
        let notes = lines.dropFirst(i).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let coords = props[":COORDINATES:"]?.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        self.init(
            id: props[":ID:"] ?? UUID().uuidString,
            object: String(head.dropFirst(2)),
            date: date,
            place: props[":PLACE:"] ?? "",
            latitude: coords?.count == 2 ? coords![0] : nil,
            longitude: coords?.count == 2 ? coords![1] : nil,
            equipment: props[":EQUIPMENT:"] ?? "",
            equipmentIDs: props[":EQUIPMENT_IDS:"]?.split(separator: " ").map(String.init) ?? [],
            seeing: props[":SEEING:"].flatMap { Int($0.prefix(1)) },
            notes: notes,
            catalog: props[":CATALOG:"]?.split(separator: " ").map(String.init) ?? [],
            utcOffset: offset,
            otherProperties: other
        )
    }
}

/// Observations as one Org file each in a folder (the app's Documents/Observations).
public struct ObservingLog: Sendable {
    public var folder: URL

    public init(folder: URL) { self.folder = folder }

    public func fileURL(for o: Observation) -> URL {
        let stamp = o.date.formatted(.verbatim("\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)-\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)", locale: Locale(identifier: "en_US_POSIX"), timeZone: .current, calendar: Calendar(identifier: .gregorian)))
        let slug = o.object.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }.reduce(into: "") { s, c in if !(c == "-" && s.last == "-") { s.append(c) } }
        return folder.appending(path: "\(stamp)-\(slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))).org")
    }

    public func all() -> [Observation] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "org" }
            .compactMap { (try? String(contentsOf: $0, encoding: .utf8)).flatMap(Observation.init(org:)) }
            .sorted { $0.date > $1.date }
    }

    /// Writes the observation, replacing any earlier file with the same ID. Sets `utcOffset` from the device's zone
    /// when missing, and `catalog` when the object's name resolves to an ID not already in it; a name that doesn't
    /// resolve keeps the IDs already set.
    public func save(_ o: Observation, resolver: CatalogResolver = .messier) throws {
        var o = o
        if o.utcOffset == nil { o.utcOffset = TimeZone.current.secondsFromGMT(for: o.date) }
        if let id = resolver.id(for: o.object), !o.catalog.contains(where: { (CatalogResolver.designation($0) ?? $0) == id }) { o.catalog = [id] }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try delete(id: o.id)
        try o.org.write(to: fileURL(for: o), atomically: true, encoding: .utf8)
    }

    /// User-defined program lists, one Org file each; see `ObservingProgram`.
    public var programsFolder: URL { folder.appending(path: "Programs") }

    /// Messier, then the files in `programsFolder` by title.
    public func programs() -> [ObservingProgram] {
        let files = (try? FileManager.default.contentsOfDirectory(at: programsFolder, includingPropertiesForKeys: nil)) ?? []
        let mine = files.filter { $0.pathExtension == "org" }.compactMap { url in
            (try? String(contentsOf: url, encoding: .utf8)).map { ObservingProgram(org: $0, id: url.deletingPathExtension().lastPathComponent) }
        }
        return [.messier] + mine.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public func delete(id: String) throws {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.pathExtension == "org" {
            if let text = try? String(contentsOf: f, encoding: .utf8), Observation(org: text)?.id == id {
                try FileManager.default.removeItem(at: f)
            }
        }
    }
}
