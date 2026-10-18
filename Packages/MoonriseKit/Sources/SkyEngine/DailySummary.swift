import Foundation

/// The text of the daily summary notification: tonight's Moon, planets, the best satellite pass and the day's events.
public struct DailySummary: Sendable, Equatable {
    public var title: String
    public var body: String

    public static func phaseName(_ angle: Double) -> String {
        switch angle {
        case ..<10, 350...: "New moon"
        case ..<80: "Waxing crescent"
        case ..<100: "First quarter"
        case ..<170: "Waxing gibbous"
        case ..<190: "Full moon"
        case ..<260: "Waning gibbous"
        case ..<280: "Last quarter"
        default: "Waning crescent"
        }
    }

    /// Summary for the night following `date`. `passes` and `events` may cover any span; only those
    /// for this night (passes) and this calendar day or night (events) are used.
    public static func make(at date: Date, observer: Observer, passes: [SatellitePass], events: [SkyEvent],
                            locale: Locale = .current, timeZone: TimeZone = .current) throws -> DailySummary {
        let tonight = try Tonight(at: date, from: observer)
        let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let lit = Int((tonight.moonIllumination * 100).rounded())
        let title = "Tonight: \(phaseName(tonight.moonPhase).lowercased().replacingOccurrences(of: " moon", with: "")) Moon, \(lit)% lit"

        var lines: [String] = []

        let todays = events.filter { calendar.isDate($0.date, inSameDayAs: date) || ($0.date >= tonight.start && $0.date <= tonight.end) }
        if !todays.isEmpty {
            lines.append(todays.map(\.title).joined(separator: ". ") + ".")
        }

        let planets = tonight.planets.filter { $0.best != nil }.map { $0.body.rawValue.capitalized }
        if planets.isEmpty {
            lines.append("No bright planets above 10° tonight.")
        } else {
            lines.append("Up tonight: \(ListFormatter.localizedString(byJoining: planets)).")
        }

        if let pass = passes
            .filter({ $0.visible && $0.featured && $0.rise >= tonight.start.addingTimeInterval(-3600) && $0.rise <= tonight.end })
            .max(by: { $0.maxAltitude < $1.maxAltitude }) {
            let when = pass.rise.formatted(time) + (calendar.isDate(pass.rise, inSameDayAs: date) ? "" : " tomorrow")
            lines.append("\(pass.displayName) passes at \(when), \(Int(pass.maxAltitude.rounded()))° high.")
        }

        if let sunset = tonight.sunset {
            lines.append("Sunset \(sunset.formatted(time)).")
        }

        return DailySummary(title: title, body: lines.joined(separator: " "))
    }
}
