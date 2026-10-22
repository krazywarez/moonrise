import Foundation

/// Report fields kept as Org properties, so the files stay readable in Emacs and orgstar.
public enum ReportKind: String, Sendable, CaseIterable {
    case variable, comet, meteors
}

extension Observation {
    public static let reportKey = ":REPORT:"

    /// The value of a property the app does not otherwise use; setting "" removes it.
    public subscript(property key: String) -> String {
        get { otherProperties.first { $0.key == key }?.value ?? "" }
        set {
            let value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if let i = otherProperties.firstIndex(where: { $0.key == key }) {
                if value.isEmpty { otherProperties.remove(at: i) } else { otherProperties[i].value = value }
            } else if !value.isEmpty {
                otherProperties.append(OrgProperty(key: key, value: value))
            }
        }
    }

    public var report: ReportKind? {
        get { ReportKind(rawValue: self[property: Self.reportKey]) }
        set { self[property: Self.reportKey] = newValue?.rawValue ?? "" }
    }

    /// :DESIGNATION: if set, else the object name.
    var designation: String {
        let d = self[property: ":DESIGNATION:"]
        return d.isEmpty ? object : d
    }
}

/// Julian date (UT) of `date`.
func julianDate(_ date: Date) -> Double { date.timeIntervalSince1970 / 86_400 + 2_440_587.5 }

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// AAVSO Visual File Format (AAVSO Manual for Visual Observing of Variable Stars, chapter 7): one line per estimate,
/// NAME,DATE,MAG,COMMENTCODE,COMP1,COMP2,CHART,NOTES with JD dates and "na" for missing fields.
/// Properties: :MAGNITUDE: ("10.9", or "<11.1" fainter than), :COMPARISON: (one or two comparison star labels),
/// :CHART:, :COMMENT_CODE:.
public enum AAVSOVisual {
    public static func file(_ log: [Observation], observerCode: String, software: String) -> String {
        var lines = ["#TYPE=VISUAL", "#OBSCODE=\(observerCode.uppercased())", "#SOFTWARE=\(software)", "#DELIM=,", "#DATE=JD", "#OBSTYPE=Visual",
                     "#NAME,DATE,MAG,COMMENTCODE,COMP1,COMP2,CHART,NOTES"]
        for o in log.filter({ $0.report == .variable }).sorted(by: { $0.date < $1.date }) {
            let mag = o[property: ":MAGNITUDE:"]
            guard !mag.isEmpty else { continue }
            let comps = o[property: ":COMPARISON:"].split(separator: " ").map(String.init)
            lines.append([
                clean(o.designation.uppercased()),
                String(format: "%.4f", julianDate(o.date)),
                clean(mag),
                field(o[property: ":COMMENT_CODE:"]),
                field(comps.first ?? ""),
                field(comps.dropFirst().first ?? ""),
                field(o[property: ":CHART:"]),
                field(String(o.notes.prefix(100))),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: ",", with: ";").replacingOccurrences(of: "#", with: "").components(separatedBy: .newlines).joined(separator: " ")
    }

    private static func field(_ s: String) -> String {
        let c = clean(s).trimmingCharacters(in: .whitespaces)
        return c.isEmpty ? "na" : c
    }
}

/// ICQ 80-column visual format, as COBS imports it (cobs.si/help/icq_format). Properties: :DESIGNATION: ("C/2023 A3",
/// "12P"), :METHOD: (S, M, B, I), :MAGNITUDE: ("7.8", "7.8:" uncertain, "[12.0" not seen), :REFERENCE: (e.g. TK),
/// :APERTURE: cm, :INSTRUMENT: (B binoculars, L reflector, R refractor, T Schmidt-Cassegrain, E eye), :FOCAL_RATIO:,
/// :POWER:, :COMA: arcmin, :DC: (0–9, "5/" for 5–6), :TAIL: degrees, :PA: degrees.
public enum ICQ {
    public static func file(_ log: [Observation], observerCode: String) -> String {
        log.filter { $0.report == .comet }.sorted { $0.date < $1.date }.compactMap { line($0, observerCode: observerCode) }.map { $0 + "\n" }.joined()
    }

    public static func line(_ o: Observation, observerCode: String) -> String? {
        guard let id = designation(o.designation), let mag = magnitude(o[property: ":MAGNITUDE:"]) else { return nil }
        var row = Array(repeating: Character(" "), count: 80)
        func put(_ s: String, _ from: Int, _ to: Int, right: Bool = false) {
            let width = to - from + 1
            let text = String(s.prefix(width))
            let padded = right ? String(repeating: " ", count: width - text.count) + text : text + String(repeating: " ", count: width - text.count)
            for (i, c) in padded.enumerated() { row[from - 1 + i] = c }
        }
        put(id, 1, 11)
        let d = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: o.date)
        let day = Double(d.day!) + (Double(d.hour!) * 3600 + Double(d.minute!) * 60 + Double(d.second!)) / 86_400
        put(String(format: "%04d %02d %05.2f", d.year!, d.month!, (day * 100).rounded(.down) / 100), 12, 24)
        put(o[property: ":METHOD:"].uppercased(), 27, 27)
        put(mag, 28, 33)
        put(o[property: ":REFERENCE:"].uppercased(), 34, 35)
        if let a = Double(o[property: ":APERTURE:"]) { put(String(format: "%.1f", a), 36, 40, right: true) }
        put(o[property: ":INSTRUMENT:"].uppercased(), 41, 41)
        if let f = Double(o[property: ":FOCAL_RATIO:"]) { put(String(Int((f / 2).rounded()) * 2), 42, 43, right: true) }
        if let p = Int(o[property: ":POWER:"]) { put(String(p), 44, 47, right: true) }
        if let c = Double(o[property: ":COMA:"]) { put(String(format: "%4.1f", c), 50, 53) }
        put(o[property: ":DC:"], 56, 57)
        // Degrees with the decimal point in column 61; from 10° the whole number reaches into column 59.
        if let t = Double(o[property: ":TAIL:"]) { t < 10 ? put(String(format: "%.2f", t), 60, 63) : put(String(format: "%.0f.", t), 58, 61, right: true) }
        if let pa = Double(o[property: ":PA:"]) { put(String(Int((pa / 2).rounded()) * 2 % 360), 65, 67, right: true) }
        put("ICQ XX", 69, 74)
        put(observerCode.uppercased(), 76, 80)
        return String(row).replacing(/\s+$/, with: "")
    }

    /// Columns 1–11: "12P" → " 12", "C/2023 A3" → "   2023A3", "P/2010 H2" → "  P2010H2".
    static func designation(_ s: String) -> String? {
        let t = s.uppercased().replacingOccurrences(of: " ", with: "")
        if let m = t.wholeMatch(of: /(\d{1,3})P(?:\/.*)?/) {
            return String(repeating: " ", count: 3 - m.1.count) + m.1
        }
        if let m = t.wholeMatch(of: /([CP])\/(\d{4})([A-Z])(\d{1,2})(?:-([A-Z]))?/) {
            return "  " + (m.1 == "P" ? "P" : " ") + m.2 + m.3 + m.4 + String(repeating: " ", count: 2 - m.4.count) + (m.5.map { String($0).lowercased() } ?? "")
        }
        return nil
    }

    /// Columns 28–33, decimal point in column 31.
    static func magnitude(_ s: String) -> String? {
        guard let m = s.trimmingCharacters(in: .whitespaces).wholeMatch(of: /(\[)?\s*(-?\d{1,2}(?:\.\d)?)\s*(:)?/), let v = Double(m.2) else { return nil }
        let number = String(format: "%.1f", v)
        return (m.1 == nil ? " " : "[") + String(repeating: " ", count: max(0, 4 - number.count)) + number + (m.3 == nil ? " " : ":")
    }
}

/// IMO Visual Meteor Database CSV, semicolon-separated: a sessions file and a rates file (column names as
/// imo-vmdb reads them). One observation is one session with one counting period. Properties: :MINUTES: (effective
/// observing time), :LIMITING_MAG:, :CLOUD: (percent of the field obstructed), :COUNTS: ("ORI 12 SPO 4", IAU codes),
/// :ELEVATION: metres, :COUNTRY:.
public enum IMOReport {
    public static func files(_ log: [Observation], observerName: String, defaultCountry: String) -> (sessions: String, rates: String) {
        var sessions = ["session_id;observer_name;latitude;longitude;elevation;country;location_name"]
        var rates = ["rate_id;session_id;shower;period_start;period_end;freq;lim_magn;t_eff;f"]
        var rate = 0
        for (n, o) in log.filter({ $0.report == .meteors }).sorted(by: { $0.date < $1.date }).enumerated() {
            guard let lat = o.latitude, let lon = o.longitude, let minutes = Double(o[property: ":MINUTES:"]), minutes > 0,
                  let lm = Double(o[property: ":LIMITING_MAG:"]) else { continue }
            let session = n + 1
            let country = o[property: ":COUNTRY:"].isEmpty ? defaultCountry : o[property: ":COUNTRY:"]
            let km = (Double(o[property: ":ELEVATION:"]) ?? 0) / 1000
            sessions.append([String(session), clean(observerName), String(format: "%.4f", lat), String(format: "%.4f", lon), String(format: "%.3f", km),
                             clean(country), clean(o.place)].joined(separator: ";"))
            let cloud = min(Double(o[property: ":CLOUD:"]) ?? 0, 90)
            let end = o.date.addingTimeInterval(minutes * 60)
            for (shower, count) in counts(o[property: ":COUNTS:"]) {
                rate += 1
                rates.append([String(rate), String(session), shower, stamp(o.date), stamp(end), String(count), String(format: "%.2f", lm),
                              String(format: "%.3f", minutes / 60), String(format: "%.2f", 1 / (1 - cloud / 100))].joined(separator: ";"))
            }
        }
        return (sessions.joined(separator: "\n") + "\n", rates.joined(separator: "\n") + "\n")
    }

    /// "ORI 12 SPO 4" → [("ORI", 12), ("SPO", 4)].
    static func counts(_ s: String) -> [(String, Int)] {
        let parts = s.uppercased().split(whereSeparator: { $0 == " " || $0 == "," })
        return stride(from: 0, to: parts.count - 1, by: 2).compactMap { i in
            Int(parts[i + 1]).map { (String(parts[i]), $0) }
        }
    }

    static func stamp(_ d: Date) -> String {
        d.formatted(Date.VerbatimFormatStyle(format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)",
                                             locale: Locale(identifier: "en_US_POSIX"), timeZone: .gmt, calendar: utc))
    }

    private static func clean(_ s: String) -> String { s.replacingOccurrences(of: ";", with: ",").components(separatedBy: .newlines).joined(separator: " ") }
}
