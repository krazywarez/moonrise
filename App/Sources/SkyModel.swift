import CoreLocation
import Feeds
import Foundation
import Observation
import SkyEngine
import SkyRenderer

/// Serializes Astronomy Engine calls, which are not thread-safe.
actor Astronomer {
    func scene(at date: Date, from observer: Observer) throws -> SkyScene {
        try SkyScene(date: date, observer: observer)
    }

    func details(of body: Body, at date: Date, from observer: Observer) throws -> BodyDetails {
        let h = try SkyEngine.horizontal(body, at: date, from: observer, refraction: true)
        let eq = try SkyEngine.equatorial(body, at: date, from: observer)
        let i = try SkyEngine.illumination(body, at: date)
        let rs = SkyEngine.riseSet(body, after: date, from: observer)
        return BodyDetails(body: body, position: h, distanceAU: eq.distance, magnitude: i.magnitude, phaseFraction: i.phaseFraction, rise: rs.rise, set: rs.set)
    }

    func tonight(at date: Date, from observer: Observer) throws -> Tonight {
        try Tonight(at: date, from: observer)
    }
}

struct BodyDetails: Sendable {
    var body: Body
    var position: Horizontal
    var distanceAU: Double
    var magnitude: Double
    var phaseFraction: Double
    var rise: Date?
    var set: Date?
}

/// Current place, the displayed time and the scene computed for them.
@MainActor
@Observable
final class SkyModel: NSObject, CLLocationManagerDelegate {
    /// Used until a location fix arrives or when location is denied.
    static let fallback = Observer(latitude: 41.8781, longitude: -87.6298)

    private(set) var observer = SkyModel.fallback
    private(set) var hasLocation = false
    /// Name shown under the title: "Your location", a chosen city, or the fallback.
    private(set) var placeName = "Chicago (location unavailable)"
    /// Sun's altitude at the displayed time, for automatic night mode.
    private(set) var sunAltitude = 0.0
    private(set) var scene: SkyScene?
    private(set) var lastBuild: Duration = .zero
    private(set) var tonight: Tonight?
    private(set) var spaceWeather: SpaceWeather?
    private var weatherFetched: Date?
    /// Hours from now shown by the time scrubber.
    var offsetHours = 0.0 { didSet { refresh() } }
    var displayedDate: Date { .now.addingTimeInterval(offsetHours * 3600) }

    let astronomer = Astronomer()
    private let manager = CLLocationManager()
    private var building = false
    private var pending = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func start() {
        applyLocationSettings()
    }

    /// Uses the chosen city, or asks Core Location for the current position.
    func applyLocationSettings() {
        let d = UserDefaults.standard
        if d.string(forKey: SettingsKey.locationMode) == "city" {
            let lat = d.object(forKey: SettingsKey.cityLatitude) as? Double ?? Self.fallback.latitude
            let lon = d.object(forKey: SettingsKey.cityLongitude) as? Double ?? Self.fallback.longitude
            observer = Observer(latitude: lat, longitude: lon)
            placeName = d.string(forKey: SettingsKey.cityName) ?? "Chicago"
            hasLocation = true
        } else {
            if !hasLocation { placeName = "Chicago (location unavailable)" }
            manager.requestWhenInUseAuthorization()
            manager.requestLocation()
        }
        refresh()
    }

    /// Rebuilds the scene for the displayed time. Requests made during a build
    /// collapse into one rebuild when it finishes.
    func refresh() {
        guard !building else { pending = true; return }
        building = true
        let date = displayedDate, observer = observer, astronomer = astronomer
        Task {
            let clock = ContinuousClock()
            var scene: SkyScene?
            let start = clock.now
            scene = try? await astronomer.scene(at: date, from: observer)
            lastBuild = clock.now - start
            if let scene { self.scene = scene }
            if offsetHours == 0 { tonight = try? await astronomer.tonight(at: date, from: observer) }
            sunAltitude = (try? SkyEngine.horizontal(.sun, at: date, from: observer, refraction: true).altitude) ?? 0
            building = false
            if pending { pending = false; refresh() }
        }
    }

    /// SWPC asks for no more than once a minute; this checks every 10.
    func refreshSpaceWeather() async {
        if let weatherFetched, Date.now.timeIntervalSince(weatherFetched) < 600 { return }
        do {
            spaceWeather = try await SpaceWeather.fetch()
            weatherFetched = .now
        } catch {
            log.error("Space weather failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func details(of body: Body) async -> BodyDetails? {
        try? await astronomer.details(of: body, at: displayedDate, from: observer)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        Task { @MainActor in
            guard UserDefaults.standard.string(forKey: SettingsKey.locationMode) != "city" else { return }
            self.observer = Observer(latitude: c.latitude, longitude: c.longitude)
            self.hasLocation = true
            self.placeName = "Your location"
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
