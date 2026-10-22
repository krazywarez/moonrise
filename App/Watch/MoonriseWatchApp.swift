import CoreLocation
import SkyEngine
import SkyRenderer
import SwiftUI

@main
struct MoonriseWatchApp: App {
    var body: some Scene {
        WindowGroup { TonightView() }
    }
}

/// Moon phase, sunset and sunrise, and the planets up tonight.
struct TonightView: View {
    @State private var location = WatchLocation()
    @State private var tonight: Tonight?
    @State private var eclipse: WatchEclipse?
    @State private var haptics = EclipseHaptics()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let t = tonight {
                    HStack(spacing: 10) {
                        MoonDisc(fraction: t.moonIllumination, waxing: t.moonPhase < 180)
                            .frame(width: 44, height: 44)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading) {
                            Text(DailySummary.phaseName(t.moonPhase)).font(.headline)
                            Text("\(Int((t.moonIllumination * 100).rounded()))% lit").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    if let eclipse { EclipseSection(eclipse: eclipse, haptics: haptics).padding(.vertical, 4) }
                    if let s = t.sunset { row("Sunset", time(s)) }
                    if let r = t.sunrise { row("Sunrise", time(r)) }
                    Text("Planets").font(.footnote.weight(.medium)).foregroundStyle(.secondary).padding(.top, 4)
                    let up = t.planets.filter { $0.best != nil }
                    if up.isEmpty { Text("None well placed tonight").font(.footnote) }
                    ForEach(up, id: \.body) { p in
                        row(p.body.rawValue.capitalized, p.best.map { "best \(time($0.date))" } ?? "")
                    }
                    if !location.located {
                        Text("Using Chicago until location is allowed.").font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Tonight")
        .task(id: location.observer) {
            let observer = location.observer
            tonight = await Task.detached { try? Tonight(at: .now, from: observer) }.value
            eclipse = await Task.detached { WatchEclipse.next(from: .now, observer: observer) }.value
        }
        .onAppear { location.start() }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
        .font(.footnote)
    }

    private func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }
}

@MainActor
@Observable
final class WatchLocation: NSObject, CLLocationManagerDelegate {
    private(set) var observer = Observer(latitude: 41.8781, longitude: -87.6298)
    private(set) var located = false
    private let manager = CLLocationManager()

    func start() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        Task { @MainActor in
            observer = Observer(latitude: c.latitude, longitude: c.longitude)
            located = true
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.manager.requestLocation() }
    }
}
