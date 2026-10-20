import CoreLocation
import MapKit
import Observation
import SkyEngine

/// Continuous best-accuracy fixes while an eclipse screen is open: near the edge of the path a contact moves
/// about 4 s per kilometre.
@MainActor
@Observable
final class EclipseLocation: NSObject, CLLocationManagerDelegate {
    struct Fix: Equatable {
        var observer: Observer
        /// Horizontal accuracy, metres.
        var accuracy: Double
    }

    private(set) var fix: Fix?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last, l.horizontalAccuracy >= 0 else { return }
        let fix = Fix(
            observer: Observer(latitude: l.coordinate.latitude, longitude: l.coordinate.longitude, height: l.verticalAccuracy >= 0 ? l.ellipsoidalAltitude : 0),
            accuracy: l.horizontalAccuracy
        )
        Task { @MainActor in self.fix = fix }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in log.error("Eclipse location failed: \(error.localizedDescription, privacy: .public)") }
    }

    /// The time zone at `observer` from Apple Maps, or nil offline.
    static func timeZone(at observer: Observer) async -> TimeZone? {
        guard let request = MKReverseGeocodingRequest(location: CLLocation(latitude: observer.latitude, longitude: observer.longitude)) else { return nil }
        return try? await request.mapItems.first?.timeZone
    }
}

/// "UTC+2" for a zone's offset at `date`.
func utcOffset(_ zone: TimeZone, at date: Date) -> String {
    let s = zone.secondsFromGMT(for: date)
    let h = abs(s) / 3600, m = abs(s) % 3600 / 60
    return "UTC\(s < 0 ? "−" : "+")\(h)\(m == 0 ? "" : String(format: ":%02d", m))"
}
