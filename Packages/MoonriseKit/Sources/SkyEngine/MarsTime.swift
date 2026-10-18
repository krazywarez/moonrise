import Foundation

/// Mars Coordinated Time and rover local times, after NASA GISS Mars24 (Allison & McEwen 2000).
public enum MarsTime {
    public struct Rover: Sendable, Identifiable {
        public var name: String
        public var site: String
        /// East longitude in degrees.
        public var longitude: Double
        /// Mars Sol Date of the landing sol's local midnight (sol 0).
        public var landingSol: Int
        public var id: String { name }

        public static let active: [Rover] = [
            Rover(name: "Perseverance", site: "Jezero Crater", longitude: 77.45, landingSol: 52304),
            Rover(name: "Curiosity", site: "Gale Crater", longitude: 137.44, landingSol: 49269),
        ]
    }

    /// TT − UTC: 32.184 s plus 37 leap seconds (none since 2017).
    static let ttMinusUTC = 69.184

    /// Mars Sol Date.
    public static func msd(_ date: Date) -> Double {
        let jdTT = (date.timeIntervalSince1970 + ttMinusUTC) / 86_400 + 2_440_587.5
        return (jdTT - 2_405_522.0028779) / 1.0274912517
    }

    /// Local mean solar time in hours (0..<24) at an east longitude.
    public static func localMeanTime(_ date: Date, eastLongitude: Double) -> Double {
        let mtc = (msd(date) * 24).truncatingRemainder(dividingBy: 24)
        let t = (mtc + eastLongitude / 15).truncatingRemainder(dividingBy: 24)
        return t < 0 ? t + 24 : t
    }

    /// Mission sol number (sol 0 is the landing sol).
    public static func sol(_ date: Date, rover: Rover) -> Int {
        Int((msd(date) + rover.longitude / 360).rounded(.down)) - rover.landingSol
    }

    public static func format(hours: Double) -> String {
        let total = Int(hours * 60)
        return String(format: "%02d:%02d", total / 60 % 24, total % 60)
    }
}
