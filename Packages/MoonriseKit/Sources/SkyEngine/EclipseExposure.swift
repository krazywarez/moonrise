import Foundation

/// Exposure times for eclipse photography from F. Espenak's Solar Eclipse Exposure Guide (NASA GSFC, 1996):
/// t = f² / (ISO × 2^Q), with Q the subject's brightness exponent.
public enum EclipseExposure {
    public struct Subject: Sendable, Identifiable {
        public var name: String
        public var q: Int
        /// Partial phases are photographed through the filter; everything else only in totality.
        public var filtered: Bool
        public var id: String { name }
    }

    public static let partial = [
        Subject(name: "Partial phases, ND 4.0 filter", q: 11, filtered: true),
        Subject(name: "Partial phases, ND 5.0 filter", q: 8, filtered: true),
    ]

    public static let totality = [
        Subject(name: "Baily's beads", q: 11, filtered: false),
        Subject(name: "Chromosphere", q: 10, filtered: false),
        Subject(name: "Prominences", q: 9, filtered: false),
        Subject(name: "Corona, 0.1 solar radii", q: 7, filtered: false),
        Subject(name: "Corona, 0.2 solar radii; diamond ring", q: 5, filtered: false),
        Subject(name: "Corona, 0.5 solar radii", q: 3, filtered: false),
        Subject(name: "Corona, 1 solar radius", q: 1, filtered: false),
        Subject(name: "Corona, 2 solar radii", q: 0, filtered: false),
        Subject(name: "Corona, 4 solar radii", q: -1, filtered: false),
        Subject(name: "Corona, 8 solar radii", q: -3, filtered: false),
    ]

    public static let credit = "After F. Espenak, Solar Eclipse Exposure Guide (NASA GSFC, 1996)."

    /// Seconds.
    public static func time(fNumber: Double, iso: Double, q: Int) -> Double {
        fNumber * fNumber / (iso * pow(2, Double(q)))
    }

    /// Whole-stop shutter speeds in seconds, as in the guide.
    static let speeds: [Double] = [1 / 4000, 1 / 2000, 1 / 1000, 1 / 500, 1 / 250, 1 / 125, 1 / 60, 1 / 30, 1 / 15, 1 / 8, 1 / 4, 1 / 2, 1, 2, 4, 8, 15, 30, 60, 120]

    /// The nearest whole-stop speed, "1/250" or "2 s"; nil outside 1/4000 to 2 minutes.
    public static func shutter(fNumber: Double, iso: Double, q: Int) -> String? {
        let t = time(fNumber: fNumber, iso: iso, q: q)
        guard t >= speeds.first! / 1.5, t <= speeds.last! * 1.5,
              let s = speeds.min(by: { abs(log2($0 / t)) < abs(log2($1 / t)) }) else { return nil }
        return s < 1 ? "1/\(Int((1 / s).rounded()))" : "\(Int(s)) s"
    }
}
