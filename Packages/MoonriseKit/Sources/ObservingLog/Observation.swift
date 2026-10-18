import Foundation

/// One logged observation, stored as an Org file that Emacs and orgstar can read.
public struct Observation: Sendable, Identifiable, Equatable {
    public var id: String
    public var object: String
    public var date: Date
    public var place: String
    public var latitude: Double?
    public var longitude: Double?
    /// e.g. "Naked eye", "10x50 binoculars", "8-inch Dobsonian".
    public var equipment: String
    /// 1 (poor) to 5 (excellent); nil when not noted.
    public var seeing: Int?
    public var notes: String

    public init(id: String = UUID().uuidString, object: String, date: Date, place: String, latitude: Double? = nil, longitude: Double? = nil, equipment: String = "", seeing: Int? = nil, notes: String = "") {
        self.id = id
        self.object = object
        self.date = date
        self.place = place
        self.latitude = latitude
        self.longitude = longitude
        self.equipment = equipment
        self.seeing = seeing
        self.notes = notes
    }

    static let orgDate: Date.VerbatimFormatStyle = .init(format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(weekday: .abbreviated) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)", locale: Locale(identifier: "en_US_POSIX"), timeZone: .current, calendar: Calendar(identifier: .gregorian))

    /// Org text: one heading with an inactive timestamp, a property drawer and the notes.
    public var org: String {
        var props = [(":ID:", id), (":PLACE:", place)]
        if let latitude, let longitude { props.append((":COORDINATES:", String(format: "%.4f, %.4f", latitude, longitude))) }
        if !equipment.isEmpty { props.append((":EQUIPMENT:", equipment)) }
        if let seeing { props.append((":SEEING:", "\(seeing)/5")) }
        var lines = ["* \(object)", "[\(date.formatted(Self.orgDate))]", ":PROPERTIES:"]
        lines += props.map { "\($0.0) \($0.1)" }
        lines.append(":END:")
        let body = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty { lines += ["", body] }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Parses the format written by `org`. Returns nil for files it did not write.
    public init?(org text: String) {
        let lines = text.components(separatedBy: "\n")
        guard let head = lines.first, head.hasPrefix("* "),
              lines.count > 1, lines[1].hasPrefix("["), lines[1].hasSuffix("]"),
              let date = try? Date(String(lines[1].dropFirst().dropLast()), strategy: Self.orgDate.parseStrategy) else { return nil }
        var props: [String: String] = [:]
        var i = 2
        if i < lines.count, lines[i] == ":PROPERTIES:" {
            i += 1
            while i < lines.count, lines[i] != ":END:" {
                let parts = lines[i].split(separator: " ", maxSplits: 1).map(String.init)
                if parts.count == 2 { props[parts[0]] = parts[1] }
                i += 1
            }
            i += 1
        }
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
            seeing: props[":SEEING:"].flatMap { Int($0.prefix(1)) },
            notes: notes
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

    /// Writes the observation, replacing any earlier file with the same ID.
    public func save(_ o: Observation) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try delete(id: o.id)
        try o.org.write(to: fileURL(for: o), atomically: true, encoding: .utf8)
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
