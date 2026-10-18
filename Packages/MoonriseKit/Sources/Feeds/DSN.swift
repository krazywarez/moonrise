import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// NASA's Deep Space Network Now feed: what each antenna is talking to.
public struct DSNStatus: Sendable {
    public struct Link: Sendable, Hashable {
        /// Display name, e.g. "Voyager 1".
        public var spacecraft: String
        public var receiving: Bool
        public var sending: Bool
        /// Bits per second of the active downlink, if any.
        public var downlinkRate: Double?
        /// Round-trip light time in seconds, if reported.
        public var roundTrip: Double?
    }

    public struct Dish: Sendable, Identifiable {
        public var name: String
        public var station: String
        public var activity: String
        public var links: [Link]
        public var id: String { name }
    }

    public var updated: Date
    public var dishes: [Dish]

    public static let url = URL(string: "https://eyes.nasa.gov/dsn/data/dsn.xml")!

    public static func fetch(session: URLSession = .shared) async throws -> DSNStatus {
        try decode(await session.data(from: url).0)
    }

    public static func decode(_ data: Data) throws -> DSNStatus {
        let p = Parser()
        let xml = XMLParser(data: data)
        xml.delegate = p
        guard xml.parse() else { throw xml.parserError ?? CocoaError(.coderReadCorrupt) }
        return DSNStatus(updated: p.updated, dishes: p.dishes)
    }

    public static func displayName(_ code: String) -> String {
        dsnSpacecraftNames[code.lowercased()] ?? code
    }

    final class Parser: NSObject, XMLParserDelegate {
        var updated = Date.distantPast
        var dishes: [Dish] = []
        var station = ""
        var current: Dish?
        var signals: [String: (down: Bool, up: Bool, rate: Double?)] = [:]
        var rtlt: [String: Double] = [:]

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
            switch name {
            case "station":
                station = a["friendlyName"] ?? a["name"] ?? ""
                if let ms = a["timeUTC"].flatMap(Double.init) { updated = Date(timeIntervalSince1970: ms / 1000) }
            case "dish":
                current = Dish(name: a["name"] ?? "", station: station, activity: a["activity"] ?? "", links: [])
                signals = [:]
                rtlt = [:]
            case "downSignal", "upSignal":
                guard let sc = a["spacecraft"], !sc.isEmpty else { return }
                let active = a["active"] == "true"
                var s = signals[sc] ?? (false, false, nil)
                if name == "downSignal" {
                    s.down = s.down || active
                    if active, let r = a["dataRate"].flatMap(Double.init), r > 0 { s.rate = r }
                } else {
                    s.up = s.up || active
                }
                signals[sc] = s
            case "target":
                if let n = a["name"], let t = a["rtlt"].flatMap(Double.init), t > 0 { rtlt[n] = t }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            guard name == "dish", var dish = current else { return }
            dish.links = signals
                .filter { $0.value.down || $0.value.up }
                .map { code, s in
                    Link(spacecraft: DSNStatus.displayName(code), receiving: s.down, sending: s.up, downlinkRate: s.rate, roundTrip: rtlt[code])
                }
                .sorted { $0.spacecraft < $1.spacecraft }
            dishes.append(dish)
            current = nil
        }
    }
}
