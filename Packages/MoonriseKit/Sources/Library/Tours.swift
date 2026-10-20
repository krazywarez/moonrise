import Foundation

/// A guided walk around one season's evening sky.
public struct Tour: Sendable, Decodable, Identifiable {
    public struct Target: Sendable, Decodable, Hashable {
        /// IAU abbreviation, e.g. "Ori".
        public var constellation: String?
        public var hr: Int?
        /// Body raw value, e.g. "jupiter".
        public var body: String?

        public init(constellation: String? = nil, hr: Int? = nil, body: String? = nil) {
            self.constellation = constellation
            self.hr = hr
            self.body = body
        }
    }

    public struct Step: Sendable, Decodable, Hashable {
        public var title: String
        public var target: Target
        public var text: String
        /// Library page to open, when it is not the target's own page.
        public var page: String?
    }

    public var id: String
    public var title: String
    /// Months (1–12) when the tour's stars are up in the evening (the same in both hemispheres).
    public var months: [Int]
    public var intro: String
    public var steps: [Step]

    public static let all: [Tour] = {
        let url = Bundle.module.url(forResource: "tours", withExtension: "json", subdirectory: "tours")!
        return try! JSONDecoder().decode([Tour].self, from: Data(contentsOf: url))
    }()

    /// Tours in order from the one for `month` onwards.
    public static func ordered(month: Int) -> [Tour] {
        let start = all.firstIndex { $0.months.contains(month) } ?? 0
        return Array(all[start...] + all[..<start])
    }
}

extension Tour.Step {
    /// The step's own Library page, else the target's.
    public var libraryPage: LibraryPage? {
        if let page { return Library.page(id: page) }
        if let hr = target.hr { return Library.page(hr: hr) }
        if let c = target.constellation { return Library.page(constellation: c) }
        if let b = target.body { return Library.page(body: b) }
        return nil
    }
}
