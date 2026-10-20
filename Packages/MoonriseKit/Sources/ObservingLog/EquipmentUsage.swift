import Foundation

/// How one inventory item has been used across the log.
public struct EquipmentUsage: Sendable, Equatable {
    public struct Tally: Sendable, Equatable {
        public var key: String
        public var count: Int
    }

    public enum Season: String, Sendable, CaseIterable {
        case winter, spring, summer, autumn
        public var title: String { rawValue.capitalized }
    }

    public var observations: Int
    public var first: Date?
    public var last: Date?
    public var distinctObjects: Int
    /// Object names, most observed first.
    public var topObjects: [Tally]
    /// Observations in each calendar month, January first.
    public var byMonth: [Int]
    /// Meteorological seasons for the observer's hemisphere (southern when latitude is negative).
    public var bySeason: [Season: Int]
    /// Mean of the observations with seeing noted.
    public var averageSeeing: Double?
    /// IDs of other items logged alongside this one, most frequent first.
    public var usedWith: [Tally]

    /// Usage of the item `id` in `log`. `calendar` decides month and season boundaries. Objects are counted by
    /// catalogue ID where `resolver` finds one, else by name.
    public init(of id: String, in log: [Observation], calendar: Calendar = .current, resolver: CatalogResolver = .messier) {
        let mine = log.filter { $0.equipmentIDs.contains(id) }
        observations = mine.count
        first = mine.map(\.date).min()
        last = mine.map(\.date).max()

        var objects: [String: (name: String, count: Int)] = [:]
        for o in mine {
            let name = o.object.trimmingCharacters(in: .whitespaces)
            let key = resolver.keys(for: o)[0]
            objects[key, default: (key == CatalogResolver.fold(name) ? name : key, 0)].count += 1
        }
        distinctObjects = objects.count
        topObjects = objects.values.map { Tally(key: $0.name, count: $0.count) }.sorted(by: Self.order)

        var months = Array(repeating: 0, count: 12)
        var seasons: [Season: Int] = [:]
        for o in mine {
            let m = calendar.component(.month, from: o.date)
            months[m - 1] += 1
            seasons[Self.season(month: m, southern: (o.latitude ?? 0) < 0), default: 0] += 1
        }
        byMonth = months
        bySeason = seasons

        let seeing = mine.compactMap(\.seeing)
        averageSeeing = seeing.isEmpty ? nil : Double(seeing.reduce(0, +)) / Double(seeing.count)

        var others: [String: Int] = [:]
        for o in mine { for other in Set(o.equipmentIDs) where other != id { others[other, default: 0] += 1 } }
        usedWith = others.map { Tally(key: $0.key, count: $0.value) }.sorted(by: Self.order)
    }

    static func order(_ a: Tally, _ b: Tally) -> Bool {
        a.count != b.count ? a.count > b.count : a.key < b.key
    }

    static func season(month: Int, southern: Bool) -> Season {
        let north: Season = switch month {
        case 12, 1, 2: .winter
        case 3...5: .spring
        case 6...8: .summer
        default: .autumn
        }
        guard southern else { return north }
        return switch north {
        case .winter: .summer
        case .spring: .autumn
        case .summer: .winter
        case .autumn: .spring
        }
    }
}
