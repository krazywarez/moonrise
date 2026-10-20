import Foundation

/// One label and value in an answer's result view. `alert` values are drawn in the accent red.
public struct AnswerRow: Sendable, Hashable {
    public var label: String
    public var value: String
    public var alert = false

    public init(_ label: String, _ value: String, alert: Bool = false) {
        self.label = label
        self.value = value
        self.alert = alert
    }
}

/// Times, days, durations and numbers for spoken answers and their rows.
struct Phrasing {
    var locale: Locale
    var timeZone: TimeZone
    var calendar: Calendar

    init(locale: Locale, timeZone: TimeZone) {
        self.locale = locale
        self.timeZone = timeZone
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
    }

    private var style: Date.FormatStyle { Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone) }

    /// "19:42" or "7:42 PM".
    func time(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone))
    }

    /// "today at 19:42", "tomorrow at 05:10", "Thursday at 03:12" or "on 28 October at 03:12".
    func when(_ d: Date, from now: Date) -> String {
        let at = "at \(time(d))"
        if calendar.isDate(d, inSameDayAs: now) { return "today \(at)" }
        if let next = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(d, inSameDayAs: next) { return "tomorrow \(at)" }
        if let week = calendar.date(byAdding: .day, value: 6, to: calendar.startOfDay(for: now)), d < week {
            return "\(d.formatted(style.weekday(.wide))) \(at)"
        }
        return "on \(d.formatted(style.day().month(.wide))) \(at)"
    }

    /// "19:42" today, else "Thu 22 Oct 19:42", for rows.
    func short(_ d: Date, from now: Date) -> String {
        calendar.isDate(d, inSameDayAs: now) ? time(d) : d.formatted(style.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }

    /// "11 hours, 30 minutes" (spoken) or "11 hr, 30 min" (rows).
    func duration(_ seconds: TimeInterval, spoken: Bool) -> String {
        Duration.seconds(seconds.rounded()).formatted(.units(allowed: [.days, .hours, .minutes], width: spoken ? .wide : .abbreviated, maximumUnitCount: 2).locale(locale))
    }

    func number(_ x: Double, digits: Int) -> String {
        x.formatted(.number.precision(.fractionLength(digits)).locale(locale))
    }

    func list(_ items: [String]) -> String {
        items.formatted(.list(type: .and).locale(locale))
    }
}

enum Compass {
    static func point(_ azimuth: Double) -> String {
        ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][index(azimuth)]
    }

    static func name(_ azimuth: Double) -> String {
        ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"][index(azimuth)]
    }

    private static func index(_ azimuth: Double) -> Int {
        Int(((azimuth + 22.5) / 45).rounded(.down)) % 8
    }
}
