import Foundation

/// Geomagnetic latitude from a centred-dipole model of Earth's field.
public enum Geomagnetic {
    /// North geomagnetic pole, IGRF-14 for 2025 (approximately 80.8° N, 72.8° W).
    public static let poleLatitude = 80.8
    public static let poleLongitude = -72.8

    /// Geomagnetic latitude in degrees for a geographic position.
    public static func latitude(_ observer: Observer) -> Double {
        let r = Double.pi / 180
        let s = sin(observer.latitude * r) * sin(poleLatitude * r)
            + cos(observer.latitude * r) * cos(poleLatitude * r) * cos((observer.longitude - poleLongitude) * r)
        return asin(max(-1, min(1, s))) / r
    }

    /// The backend's 5° band, named by its equatorward edge: 50 covers 50–55° N, -55 covers 50–55° S.
    /// Must match `bandFor` in server/src/aurora.ts.
    public static func band(_ observer: Observer) -> Int {
        let m = latitude(observer)
        let b = Int((abs(m) / 5).rounded(.down)) * 5
        return m < 0 ? -(b + 5) : b
    }

    /// Geomagnetic latitude of the auroral oval's equatorward edge for a Kp value.
    /// Must match `ovalEdge` in server/src/aurora.ts.
    public static func ovalEdge(kp: Double) -> Double {
        66.5 - 2.04 * kp
    }

    /// Lowest geomagnetic latitude (absolute) where aurora may be seen low on the poleward horizon.
    /// Must match `visibleFrom` in server/src/aurora.ts.
    public static func visibleFrom(kp: Double) -> Double {
        ovalEdge(kp: kp) - 6
    }

    /// Kp at which aurora may be seen on the horizon from here; 0 under or poleward of the quiet oval.
    public static func kpNeeded(_ observer: Observer) -> Double {
        max(0, (visibleFrom(kp: 0) - abs(latitude(observer))) / 2.04)
    }
}
