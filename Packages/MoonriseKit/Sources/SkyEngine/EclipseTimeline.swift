import Foundation

/// One site's contacts, the Sun's position at each, and the spoken cue script for eclipse day.
public struct EclipseTimeline: Sendable {
    /// The glasses-off cue needs at least this much computed totality…
    public static let minimumTotality: TimeInterval = 30
    /// …and a location fix better than this, metres.
    public static let maximumAccuracy = 100.0

    public struct Contact: Sendable {
        public var name: String
        public var date: Date
        public var sun: Horizontal
    }

    public enum Haptic: Sendable {
        case tap, double, long
    }

    public struct Cue: Sendable, Equatable {
        public var date: Date
        public var text: String
        public var haptic: Haptic
        /// Shown in red.
        public var warning: Bool
    }

    /// Why there is no glasses-off cue.
    public enum Withheld: Sendable, Equatable {
        /// No totality here.
        case partial
        /// Under `minimumTotality`.
        case short
        /// No fix, or one worse than `maximumAccuracy`.
        case imprecise
        /// The Sun is below the horizon at second contact.
        case sunDown
    }

    public var eclipse: LocalEclipse
    public var observer: Observer
    /// C1, C2, Max, C3, C4; C2 and C3 only for a total or annular eclipse.
    public var contacts: [Contact]
    public var cues: [Cue]
    public var glassesOffWithheld: Withheld?

    /// `accuracy`: horizontal accuracy of the location fix in metres, or nil for a chosen place.
    public init(_ eclipse: LocalEclipse, observer: Observer, accuracy: Double?) throws {
        self.eclipse = eclipse
        self.observer = observer
        var named = [("C1", eclipse.partialBegin)]
        if let c2 = eclipse.centralBegin { named.append(("C2", c2)) }
        named.append(("Max", eclipse.peak))
        if let c3 = eclipse.centralEnd { named.append(("C3", c3)) }
        named.append(("C4", eclipse.partialEnd))
        contacts = try named.map { Contact(name: $0.0, date: $0.1, sun: try SkyEngine.horizontal(.sun, at: $0.1, from: observer, refraction: true)) }

        if eclipse.kind != "Total" {
            glassesOffWithheld = .partial
        } else if let b = eclipse.centralBegin, let e = eclipse.centralEnd, e.timeIntervalSince(b) < Self.minimumTotality {
            glassesOffWithheld = .short
        } else if accuracy.map({ $0 >= Self.maximumAccuracy }) ?? true {
            glassesOffWithheld = .imprecise
        } else if contacts[1].sun.altitude <= 0 {
            glassesOffWithheld = .sunDown
        }
        cues = Self.script(eclipse, withheld: glassesOffWithheld).sorted { $0.date < $1.date }
    }

    static func script(_ e: LocalEclipse, withheld: Withheld?) -> [Cue] {
        func cue(_ date: Date, _ text: String, _ haptic: Haptic = .tap, warning: Bool = false) -> Cue {
            Cue(date: date, text: text, haptic: haptic, warning: warning)
        }
        var cues: [Cue] = []
        guard e.kind == "Total", let c2 = e.centralBegin, let c3 = e.centralEnd else {
            let annular = e.kind == "Annular"
            cues.append(cue(e.partialBegin, "First contact. This eclipse is \(annular ? "annular" : "partial") here, so keep your glasses on the whole time.", warning: true))
            if annular, let c2 = e.centralBegin, let c3 = e.centralEnd {
                cues.append(cue(c2, "The ring of the Sun is complete. Glasses stay on.", .long))
                cues.append(cue(c3, "The ring is breaking. Glasses stay on."))
            } else {
                cues.append(cue(e.peak.addingTimeInterval(-60), "One minute to maximum eclipse."))
                cues.append(cue(e.peak, "Maximum eclipse, \(Int((e.obscuration * 100).rounded())) percent of the Sun covered. Glasses stay on.", .long))
            }
            cues.append(cue(e.partialEnd, "Last contact. The eclipse is over."))
            return cues
        }
        cues.append(cue(e.partialBegin, "First contact. The Moon is starting to cover the Sun. Keep your glasses on whenever you look at it."))
        if c2.timeIntervalSince(e.partialBegin) > 360 { cues.append(cue(c2.addingTimeInterval(-300), "Five minutes to totality.")) }
        cues.append(cue(c2.addingTimeInterval(-120), "Two minutes. Lay out a white sheet and watch it for shadow bands."))
        cues.append(cue(c2.addingTimeInterval(-60), "One minute to totality. Glasses stay on.", .double))
        cues.append(cue(c2.addingTimeInterval(-15), "Watch for Baily's beads and the diamond ring, through your glasses.", .double))
        for n in 1...5 { cues.append(cue(c2.addingTimeInterval(-Double(n)), "\(n)")) }
        switch withheld {
        case nil:
            cues.append(cue(c2, "Totality. Once no sunlight shows through your glasses, not even one bead, glasses off.", .long))
        case .short:
            cues.append(cue(c2, "Totality here is under \(Int(Self.minimumTotality)) seconds. Keep your glasses on.", .long, warning: true))
        case .imprecise:
            cues.append(cue(c2, "Totality is due, but your position is not precise enough to call it. Keep your glasses on.", .long, warning: true))
        case .sunDown, .partial:
            cues.append(cue(c2, "Keep your glasses on.", .long, warning: true))
        }
        let duration = c3.timeIntervalSince(c2)
        if duration >= 60 { cues.append(cue(c3.addingTimeInterval(-30), "Thirty seconds of totality left.")) }
        cues.append(cue(c3.addingTimeInterval(-15), "Glasses on, and filters back on cameras and binoculars.", .long, warning: true))
        cues.append(cue(c3, "Third contact. Beads and the diamond ring on the other side, through your glasses.", .double))
        cues.append(cue(c3.addingTimeInterval(30), "Watch the white sheet for shadow bands again."))
        cues.append(cue(e.partialEnd, "Last contact. The eclipse is over."))
        return cues
    }

    /// Where rehearsal mode sets its clock: three minutes before totality, or before maximum elsewhere.
    public var rehearsalStart: Date { (eclipse.kind == "Total" ? eclipse.centralBegin ?? eclipse.peak : eclipse.peak).addingTimeInterval(-180) }

    /// The Sun's position from first to last contact, every `step` seconds, ending at last contact.
    public func sunPath(every step: TimeInterval) throws -> [(date: Date, sun: Horizontal)] {
        var dates = Array(stride(from: eclipse.partialBegin, to: eclipse.partialEnd, by: step))
        dates.append(eclipse.partialEnd)
        return try dates.map { ($0, try SkyEngine.horizontal(.sun, at: $0, from: observer, refraction: true)) }
    }
}
