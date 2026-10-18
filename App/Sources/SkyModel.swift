import CoreLocation
import Feeds
import Foundation
import Library
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
    private(set) var passes: [SatellitePass] = []
    private var elements: [OrbitalElements] = []
    private var elementsFetched: Date?
    private var weatherFetched: Date?
    /// Hours from now shown by the time scrubber.
    var offsetHours = 0.0 { didSet { refresh() } }
    /// Year shown instead of this one (astronomical numbering: 0 is 1 BCE), or nil for now.
    var historicalYear: Int? { didSet { refresh(); poleStar = historicalYear.flatMap { _ in SkyModel.poleStar(at: displayedDate, south: observer.latitude < 0) } } }
    /// Brightest-nearest star to the visible celestial pole in the historical year, and its distance from the pole.
    private(set) var poleStar: (name: String, degrees: Double)?
    var displayedDate: Date {
        let d = Date.now.addingTimeInterval(offsetHours * 3600)
        guard let y = historicalYear else { return d }
        return SkyModel.date(d, inYear: y)
    }

    /// The same month, day and time in year `y` (Julian calendar before 1582, as Foundation's Gregorian calendar does).
    static func date(_ d: Date, inYear y: Int) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        var c = calendar.dateComponents([.month, .day, .hour, .minute, .second], from: d)
        c.era = y > 0 ? 1 : 0
        c.year = y > 0 ? y : 1 - y
        return calendar.date(from: c) ?? d
    }

    /// The star brighter than magnitude 3.7 (so Thuban, 3.65, counts) closest to the north (or south) celestial pole at `date`.
    static func poleStar(at date: Date, south: Bool) -> (name: String, degrees: Double)? {
        let best = Catalog.stars.filter { $0.magnitude < 3.7 }.map { star -> (Star, Double) in
            let dec = SkyEngine.equatorOfDate(j2000: star.position(at: date), at: date).dec
            return (star, south ? 90 + dec : 90 - dec)
        }.min { $0.1 < $1.1 }
        guard let (star, d) = best else { return nil }
        return (Library.page(hr: star.hr)?.title ?? formerPoleStars[star.hr] ?? "HR \(star.hr)", d)
    }

    /// Stars near the north celestial pole between 3000 BCE and 3000 CE that have no Library page.
    static let formerPoleStars = [5291: "Thuban", 5563: "Kochab", 5735: "Pherkad", 8974: "Errai", 8162: "Alderamin"]

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
        AuroraAlerts.shared.update(observer: observer)
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
            if offsetHours == 0, historicalYear == nil { tonight = try? await astronomer.tonight(at: date, from: observer) }
            sunAltitude = (try? SkyEngine.horizontal(.sun, at: date, from: observer, refraction: true).altitude) ?? 0
            building = false
            if pending { pending = false; refresh() }
        }
    }

    private struct SatelliteList: Decodable { var satellites: [OrbitalElements] }

    /// Orbital elements from the backend (refreshed hourly), then passes for the next three days.
    func refreshPasses() async {
        if elementsFetched.map({ Date.now.timeIntervalSince($0) > 3600 }) ?? true, let apiBase {
            if let (data, _) = try? await URLSession.shared.data(from: apiBase.appending(path: "v1/satellites")),
               let list = try? JSONDecoder().decode(SatelliteList.self, from: data), !list.satellites.isEmpty {
                elements = list.satellites
                elementsFetched = .now
            }
        }
        let elements = elements, observer = observer
        passes = await Task.detached {
            elements.flatMap { SkyEngine.passes(of: $0, from: .now, hours: 72, observer: observer) }.sorted { $0.rise < $1.rise }
        }.value
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
