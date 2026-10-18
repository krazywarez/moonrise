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
}
