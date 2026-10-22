import Feeds
import Library
import SkyRenderer
import SwiftUI
import UserNotifications

/// UserDefaults keys shared by the settings screen and the models that read them.
enum SettingsKey {
    static let locationMode = "locationMode" // "current" or "city"
    static let cityName = "cityName"
    static let cityLatitude = "cityLatitude"
    static let cityLongitude = "cityLongitude"
    static let nightMode = "nightMode" // "off", "on" or "auto"
    static let onboarded = "onboarded"
    /// Whether the Sky tab is currently drawn in night mode (written by the Sky tab).
    static let nightActive = "nightActive"
    static let dailySummary = "dailySummary"
    /// Local alerts 15 minutes before visible ISS passes.
    static let issPasses = "issPassAlerts"
    /// Sky culture id, or "western" for the IAU constellations.
    static let skyCulture = "skyCulture"
    /// Minutes after local midnight.
    static let dailySummaryMinutes = "dailySummaryMinutes"
    /// Messier objects on the sky chart.
    static let showDeepSky = "showDeepSky"
    static let showMilkyWay = "showMilkyWay"
    /// HorizonProfile.stored: 36 skyline altitudes.
    static let horizonProfile = "horizonProfile"
    /// Cloud forecasts from Apple Weather; off unless turned on.
    static let cloudForecast = "cloudForecast"
    /// The eclipse eye-safety note has been shown before a countdown or rehearsal.
    static let eclipseSafetyShown = "eclipseSafetyShown"
    /// Camera filter cues in the eclipse-day countdown.
    static let eclipsePhotographer = "eclipsePhotographer"
}

struct City: Hashable, Identifiable {
    var name: String
    var latitude: Double
    var longitude: Double
    var id: String { name }

    static let all: [City] = [
        City(name: "Anchorage", latitude: 61.218, longitude: -149.900),
        City(name: "Auckland", latitude: -36.849, longitude: 174.763),
        City(name: "Berlin", latitude: 52.520, longitude: 13.405),
        City(name: "Buenos Aires", latitude: -34.604, longitude: -58.382),
        City(name: "Cairo", latitude: 30.044, longitude: 31.236),
        City(name: "Cape Town", latitude: -33.925, longitude: 18.424),
        City(name: "Chicago", latitude: 41.878, longitude: -87.630),
        City(name: "Denver", latitude: 39.739, longitude: -104.990),
        City(name: "Honolulu", latitude: 21.307, longitude: -157.858),
        City(name: "Houston", latitude: 29.760, longitude: -95.370),
        City(name: "London", latitude: 51.507, longitude: -0.128),
        City(name: "Los Angeles", latitude: 34.052, longitude: -118.244),
        City(name: "Mexico City", latitude: 19.433, longitude: -99.133),
        City(name: "Mumbai", latitude: 19.076, longitude: 72.878),
        City(name: "New York", latitude: 40.713, longitude: -74.006),
        City(name: "Paris", latitude: 48.857, longitude: 2.352),
        City(name: "Reykjavík", latitude: 64.147, longitude: -21.942),
        City(name: "Santiago", latitude: -33.449, longitude: -70.669),
        City(name: "São Paulo", latitude: -23.551, longitude: -46.633),
        City(name: "Seattle", latitude: 47.606, longitude: -122.332),
        City(name: "Singapore", latitude: 1.352, longitude: 103.820),
        City(name: "Stockholm", latitude: 59.329, longitude: 18.069),
        City(name: "Sydney", latitude: -33.869, longitude: 151.209),
        City(name: "Tokyo", latitude: 35.676, longitude: 139.650),
        City(name: "Toronto", latitude: 43.653, longitude: -79.383),
    ]
}

/// Privacy policy served by the backend.
let privacyPolicyURL = URL(string: "https://krz.sh/privacy/moonrise/")!

struct SettingsScreen: View {
    @AppStorage(SettingsKey.locationMode) private var locationMode = "current"
    @AppStorage(SettingsKey.cityName) private var cityName = "Chicago"
    @AppStorage(SettingsKey.cityLatitude) private var cityLatitude = 41.878
    @AppStorage(SettingsKey.cityLongitude) private var cityLongitude = -87.630
    @AppStorage(SettingsKey.nightMode) private var nightMode = "auto"
    @AppStorage(SettingsKey.skyCulture) private var skyCulture = "western"
    @AppStorage(SettingsKey.showDeepSky) private var showDeepSky = true
    @AppStorage(SettingsKey.showMilkyWay) private var showMilkyWay = true
    @AppStorage(SettingsKey.onboarded) private var onboarded = true
    @Environment(\.dismiss) private var dismiss
    @State private var alerts = AuroraAlerts.shared
    @AppStorage(SettingsKey.dailySummary) private var dailySummary = false
    @AppStorage(SettingsKey.issPasses) private var issPasses = false
    @AppStorage(SettingsKey.dailySummaryMinutes) private var dailySummaryMinutes = DailySummaryNotifications.defaultMinutes
    @State private var summaryStatus: String?
    @State private var issStatus: String?
    @AppStorage(SettingsKey.cloudForecast) private var cloudForecast = false
    var onChange: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Location") {
                    Picker("Sky for", selection: $locationMode) {
                        Text("Current location").tag("current")
                        Text("A city").tag("city")
                    }
                    if locationMode == "city" {
                        Picker("City", selection: $cityName) {
                            ForEach(City.all) { Text($0.name).tag($0.name) }
                        }
                    }
                }
                Section {
                    Toggle("Aurora alerts", isOn: Binding(
                        get: { alerts.enabled },
                        set: { on in Task { await alerts.setEnabled(on) } }
                    ))
                    Toggle("News alerts", isOn: Binding(
                        get: { alerts.news },
                        set: { on in Task { await alerts.setNews(on) } }
                    ))
                    if alerts.enabled || alerts.news {
                        Button("Send a test alert") { Task { await alerts.sendTest() } }
                    }
                    if let status = alerts.status {
                        Text(status).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Alerts")
                } footer: {
                    Text("Aurora alerts tell you when the aurora may be visible from your area at night. News alerts send three of the day's space headlines at 9 a.m. For these, Moonrise sends our server this device's notification token, a 5° band of geomagnetic latitude, your time zone offset and which alerts are on, not your location.")
                }
                Section {
                    Toggle("Daily summary", isOn: Binding(
                        get: { dailySummary },
                        set: { on in Task { await setDailySummary(on) } }
                    ))
                    if dailySummary {
                        DatePicker("Time", selection: summaryTime, displayedComponents: .hourAndMinute)
                    }
                    if let summaryStatus {
                        Text(summaryStatus).font(.footnote).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("A note each day with the Moon, the planets up that night, the best satellite pass and any events. It is worked out on this device; nothing is sent to our server.")
                }
                Section {
                    Toggle("ISS passes", isOn: Binding(
                        get: { issPasses },
                        set: { on in Task { await setISSPasses(on) } }
                    ))
                    if let issStatus {
                        Text(issStatus).font(.footnote).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("An alert 15 minutes before the International Space Station crosses your sky while you can see it. Worked out on this device; nothing is sent to our server.")
                }
                Section {
                    Toggle("Cloud forecasts", isOn: $cloudForecast)
                } footer: {
                    Text(LocalizedStringKey("Shows cloud for tonight, satellite passes and events. To get the forecast, Moonrise sends Apple's weather service your location rounded to about 10 km. [Privacy policy](\(privacyPolicyURL.absoluteString)#cloud-forecasts)"))
                }
                Section {
                    Picker("Constellations", selection: $skyCulture) {
                        Text("Western (IAU)").tag("western")
                        ForEach(Catalog.skyCultures) { Text($0.name).tag($0.id) }
                    }
                    Toggle("Messier objects", isOn: $showDeepSky)
                    Toggle("Milky Way", isOn: $showMilkyWay)
                    NavigationLink("Horizon") { HorizonEditor() }
                    Picker("Night mode", selection: $nightMode) {
                        Text("Off").tag("off")
                        Text("On").tag("on")
                        Text("After dark").tag("auto")
                    }
                } header: {
                    Text("Display")
                } footer: {
                    Text("Constellations from other cultures come from Stellarium's sky cultures and are drawn over the same stars; figures with stars fainter than the app's catalogue are shortened. Messier objects are galaxies, clusters and nebulae, drawn with atlas symbols; most need binoculars. The Milky Way is from ESA's Gaia (ESA/Gaia/DPAC, CC BY-SA 3.0 IGO). Night mode draws the sky in red to keep your eyes adapted to the dark. After dark turns it on once the Sun is 12° below the horizon.")
                }
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.versionString)
                    Button("Show the introduction again") {
                        dismiss()
                        // After the sheet has gone, so the full-screen introduction can present.
                        Task { try? await Task.sleep(for: .milliseconds(600)); onboarded = false }
                    }
                    NavigationLink("Credits and licences") { CreditsScreen() }
                    Link("Privacy policy", destination: privacyPolicyURL)
                }
                #if DEBUG
                SampleActivitiesSection()
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onChange(of: cityName) {
                if let c = City.all.first(where: { $0.name == cityName }) {
                    cityLatitude = c.latitude
                    cityLongitude = c.longitude
                }
                onChange()
            }
            .onChange(of: locationMode) { onChange() }
            .onChange(of: cloudForecast) { if !cloudForecast { SavedForecast.delete() } }
        }
    }

    private var summaryTime: Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(Double(dailySummaryMinutes) * 60) },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                dailySummaryMinutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }

    private func setISSPasses(_ on: Bool) async {
        if on {
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else {
                issStatus = "Notifications are off for Moonrise. Turn them on in the Settings app."
                return
            }
        }
        issStatus = nil
        issPasses = on
    }

    private func setDailySummary(_ on: Bool) async {
        if on {
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else {
                summaryStatus = "Notifications are off for Moonrise. Turn them on in the Settings app."
                return
            }
        }
        summaryStatus = nil
        dailySummary = on
    }
}

struct CreditsScreen: View {
    private struct Credit: Hashable {
        var name: String
        var detail: String
    }

    private let software: [Credit] = [
        Credit(name: "Astronomy Engine", detail: "Don Cross. MIT licence."),
        Credit(name: "Yale Bright Star Catalogue, 5th ed.", detail: "Hoffleit & Warren (1991), via VizieR V/50."),
        Credit(name: "Constellation lines", detail: "Marc van der Sluys, ConstellationLines (doi:10.5281/zenodo.10397192). CC BY 4.0."),
        Credit(name: "Coastlines", detail: "Natural Earth. Public domain."),
        Credit(name: "Messier objects", detail: "Mattia Verga, OpenNGC. CC BY-SA 4.0."),
        Credit(name: "Spacecraft trajectories", detail: "NASA/JPL Horizons."),
    ]

    private let feeds: [Credit] = [
        Credit(name: "Space weather and aurora forecast", detail: "NOAA Space Weather Prediction Center."),
        Credit(name: "Images of the Sun", detail: "Courtesy of NASA/SDO and the AIA, EVE, and HMI science teams."),
        Credit(name: "Launch schedule", detail: "The Space Devs, Launch Library 2."),
        Credit(name: "Deep Space Network status", detail: "NASA/JPL, DSN Now."),
        Credit(name: "Satellite orbits", detail: "CelesTrak."),
        Credit(name: "Mars rover raw images", detail: "NASA/JPL-Caltech, with MSSS and ASU for some cameras."),
        Credit(name: "Space news headlines", detail: "Spaceflight News API, The Space Devs. Articles belong to their publishers."),
    ]

    /// Every distinct image credit used by the Library, grouped by licence.
    private var imageCredits: [(licence: String, credits: [String])] {
        let images = Library.pages.compactMap(\.image)
        let grouped = Dictionary(grouping: images, by: \.licence)
        return grouped.keys.sorted().map { licence in
            (licence, Array(Set(grouped[licence]!.map(\.credit))).sorted())
        }
    }

    var body: some View {
        List {
            Section("Data and software") {
                ForEach(software, id: \.self) { row($0) }
            }
            Section("Live data") {
                ForEach(feeds, id: \.self) { row($0) }
            }
            Section("Sky cultures") {
                ForEach(Catalog.skyCultures) { c in
                    Link(destination: c.source) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name)
                            Text("Stellarium sky cultures. \(c.licence)").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            ForEach(imageCredits, id: \.licence) { group in
                Section("Library images: \(group.licence)") {
                    ForEach(group.credits, id: \.self) { Text($0).font(.footnote) }
                }
            }
            Section {
                Text("Each Library page lists its sources, and each image links to the page it is published on. CC BY images are used under the Creative Commons Attribution 4.0 licence; ESA images marked CC BY-SA 3.0 IGO under that licence. NASA does not endorse this app.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Credits and licences")
    }

    private func row(_ c: Credit) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(c.name)
            Text(c.detail).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

extension Bundle {
    var versionString: String {
        let v = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }
}
