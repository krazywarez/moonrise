import CoreLocation
import Foundation
import Observation
import SkyEngine
import SkyRenderer

/// Current place and the scene computed for it. Scenes are built off the main
/// thread one at a time, since Astronomy Engine is not thread-safe.
@MainActor
@Observable
final class SkyModel: NSObject, CLLocationManagerDelegate {
    /// Used until a location fix arrives or when location is denied.
    static let fallback = Observer(latitude: 41.8781, longitude: -87.6298)

    private(set) var observer = SkyModel.fallback
    private(set) var hasLocation = false
    private(set) var scene: SkyScene?
    private(set) var lastBuild: Duration = .zero

    private let manager = CLLocationManager()
    private var building = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
        refresh()
    }

    func refresh(at date: Date = .now) {
        guard !building else { return }
        building = true
        let observer = observer
        Task.detached(priority: .userInitiated) {
            let clock = ContinuousClock()
            var scene: SkyScene?
            let elapsed = clock.measure { scene = try? SkyScene(date: date, observer: observer) }
            await MainActor.run {
                self.scene = scene
                self.lastBuild = elapsed
                self.building = false
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        Task { @MainActor in
            self.observer = Observer(latitude: c.latitude, longitude: c.longitude)
            self.hasLocation = true
            self.refresh()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in log.error("Location failed: \(error.localizedDescription, privacy: .public)") }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if [.authorizedWhenInUse, .authorizedAlways].contains(status) { self.manager.requestLocation() }
        }
    }
}
