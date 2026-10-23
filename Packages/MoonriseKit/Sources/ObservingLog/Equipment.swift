import Foundation

/// One item of the user's gear. The inventory is one Org file with a heading per item.
public struct Equipment: Sendable, Identifiable, Equatable, Hashable {
    public enum Kind: String, Sendable, CaseIterable, Identifiable {
        case telescope, binoculars, mount, eyepiece, barlow, camera, filter, other
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .telescope: "Telescope"
            case .binoculars: "Binoculars"
            case .mount: "Mount"
            case .eyepiece: "Eyepiece"
            case .barlow: "Barlow"
            case .camera: "Camera"
            case .filter: "Filter"
            case .other: "Other"
            }
        }

        /// The spec fields that apply to this kind, in display order.
        public var specs: [Spec] {
            switch self {
            case .telescope: [.aperture, .focalLength]
            case .binoculars: [.magnification, .aperture, .fieldOfView]
            case .eyepiece: [.focalLength, .fieldOfView]
            case .barlow: [.magnification]
            case .camera: [.sensor]
            case .mount, .filter, .other: []
            }
        }
    }

    public enum Spec: Sendable {
        case aperture, focalLength, magnification, fieldOfView, sensor
    }

    public var id: String
    public var kind: Kind
    public var name: String
    /// Millimetres.
    public var aperture: Double?
    /// Millimetres.
    public var focalLength: Double?
    /// Binocular power, or the Barlow factor.
    public var magnification: Double?
    /// Degrees: true field for binoculars, apparent field for eyepieces.
    public var fieldOfView: Double?
    public var sensor: String
    public var notes: String
    /// Retired items stay in the inventory for old entries but leave the picker.
    public var retired: Bool
    /// Properties added by hand, in file order.
    public var otherProperties: [OrgProperty]

    static let knownKeys: Set = [":ID:", ":TYPE:", ":APERTURE:", ":FOCAL_LENGTH:", ":FOCAL_RATIO:", ":MAGNIFICATION:", ":FIELD_OF_VIEW:", ":SENSOR:", ":RETIRED:"]

    public init(id: String = UUID().uuidString, kind: Kind, name: String, aperture: Double? = nil, focalLength: Double? = nil, magnification: Double? = nil, fieldOfView: Double? = nil, sensor: String = "", notes: String = "", retired: Bool = false, otherProperties: [OrgProperty] = []) {
        self.id = id
        self.kind = kind
        self.name = name
        self.aperture = aperture
        self.focalLength = focalLength
        self.magnification = magnification
        self.fieldOfView = fieldOfView
        self.sensor = sensor
        self.notes = notes
        self.retired = retired
        self.otherProperties = otherProperties
    }

    /// Focal length over aperture, when both are known.
    public var focalRatio: Double? {
        guard let aperture, let focalLength, aperture > 0 else { return nil }
        return focalLength / aperture
    }

    static func number(_ x: Double) -> String {
        x.formatted(.number.precision(.fractionLength(0...1)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }

    /// Org text for this item: a heading, a property drawer and the notes.
    public var org: String {
        var props = [(":ID:", id), (":TYPE:", kind.rawValue)]
        if let aperture { props.append((":APERTURE:", "\(Self.number(aperture)) mm")) }
        if let focalLength { props.append((":FOCAL_LENGTH:", "\(Self.number(focalLength)) mm")) }
        if let focalRatio { props.append((":FOCAL_RATIO:", "f/\(Self.number(focalRatio))")) }
        if let magnification { props.append((":MAGNIFICATION:", "\(Self.number(magnification))x")) }
        if let fieldOfView { props.append((":FIELD_OF_VIEW:", "\(Self.number(fieldOfView))°")) }
        if !sensor.isEmpty { props.append((":SENSOR:", sensor)) }
        if retired { props.append((":RETIRED:", "t")) }
        var lines = ["* \(name)", ":PROPERTIES:"]
        lines += props.map { "\($0.0) \($0.1)" }
        lines += otherProperties.map(\.line)
        lines.append(":END:")
        let body = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty { lines += ["", body] }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Parses one heading in the format written by `org`. Returns nil without a heading or an ID.
    public init?(org text: String) {
        let lines = text.components(separatedBy: "\n")
        guard let head = lines.first, head.hasPrefix("* ") else { return nil }
        let (props, other, i) = OrgProperty.drawer(in: lines, at: 1, known: Self.knownKeys)
        guard let id = props[":ID:"] else { return nil }
        func leadingNumber(_ key: String) -> Double? {
            props[key].flatMap { Double($0.prefix { $0.isNumber || $0 == "." }) }
        }
        self.init(
            id: id,
            kind: props[":TYPE:"].flatMap(Kind.init(rawValue:)) ?? .other,
            name: String(head.dropFirst(2)),
            aperture: leadingNumber(":APERTURE:"),
            focalLength: leadingNumber(":FOCAL_LENGTH:"),
            magnification: leadingNumber(":MAGNIFICATION:"),
            fieldOfView: leadingNumber(":FIELD_OF_VIEW:"),
            sensor: props[":SENSOR:"] ?? "",
            notes: lines.dropFirst(i).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            retired: props[":RETIRED:"] == "t",
            otherProperties: other
        )
    }
}

/// The inventory as a single Org file (the app's Documents/Equipment.org).
public struct EquipmentInventory: Sendable {
    public var file: URL

    public init(file: URL) { self.file = file }

    public func all() -> [Equipment] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        var chunks: [[String]] = []
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("* ") { chunks.append([line]) } else if !chunks.isEmpty { chunks[chunks.count - 1].append(line) }
        }
        return chunks.compactMap { Equipment(org: $0.joined(separator: "\n")) }
    }

    /// Writes the item, replacing any earlier item with the same ID.
    public func save(_ item: Equipment) throws {
        var items = all()
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item } else { items.append(item) }
        try write(items)
    }

    public func delete(id: String) throws {
        try write(all().filter { $0.id != id })
    }

    private func write(_ items: [Equipment]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = (["#+title: Equipment\n"] + items.map(\.org)).joined(separator: "\n")
        try text.write(to: file, atomically: true, encoding: .utf8)
    }
}
