import Charts
import CoreLocation
import Feeds
import SkyRenderer
import SwiftUI

struct SunScreen: View {
    @State private var wavelength = SolarImage.corona
    @State private var kp: [KpBar] = []
    @State private var xray: [XRaySample] = []
    @State private var ovation: Ovation?
    @State private var failed = false
    @State private var imageID = Date.now

    private let ink = Color(red: 0.95, green: 0.95, blue: 0.93)
    private let accent = Color(red: 0.88, green: 0.24, blue: 0.19)
    private let background = Color.black

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Sun").font(.title.weight(.medium))
                Rectangle().fill(accent).frame(width: 48, height: 5).padding(.top, 8).padding(.bottom, 12)
                Text("The Sun as NASA's Solar Dynamics Observatory sees it now, and the space weather it sends our way: flares, magnetic storms and the aurora.")
                    .font(.subheadline).dimmed(0.75).padding(.bottom, 16)

                image
                Picker("Wavelength", selection: $wavelength) {
                    ForEach(SolarImage.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.top, 12)
                Text(wavelength.caption).font(.footnote).dimmed(0.75).padding(.top, 8)
                Text(SolarImage.credit).font(.caption2).dimmed(0.5).padding(.top, 4)

                section("Aurora tonight", note: "NOAA's forecast of where the aurora may be overhead in the next hour; brighter green is more likely. From a few hundred kilometres further from the pole it can still be seen low on the horizon.") { auroraMap }
                section("Solar flares, last 24 h", note: "X-rays from the Sun, measured by NOAA's GOES satellites. Spikes are flares: M and X class can disrupt radio and GPS, and the biggest can bring a storm a day or two later.") { flares }
                section("Geomagnetic activity (Kp)", note: "How disturbed Earth's magnetic field is, from 0 (quiet) to 9. At 5 or more it is a storm and the aurora reaches lower latitudes.") { kpChart }

                if failed {
                    Text("Couldn't load space weather. Pull to retry.").font(.footnote).foregroundStyle(accent).padding(.top, 12)
                }
                Text("Space weather data: NOAA Space Weather Prediction Center. Coastlines: Natural Earth.").font(.caption2).dimmed(0.5).padding(.vertical, 16)
            }
            .padding(.horizontal, 20)
            .readableWidth()
        }
        .foregroundStyle(ink)
        .background(background.ignoresSafeArea())
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        imageID = .now
        async let k = try? SpaceWeather.fetchKpBars()
        async let x = try? XRay.fetch()
        async let o = try? Ovation.fetch()
        let (kpResult, xrayResult, ovationResult) = await (k, x, o)
        kp = kpResult ?? kp
        xray = xrayResult ?? xray
        ovation = ovationResult ?? ovation
        failed = kpResult == nil || xrayResult == nil || ovationResult == nil
    }

    private var image: some View {
        AsyncImage(url: wavelength.url(size: 1024)) { phase in
            switch phase {
            case .success(let img): img.resizable().scaledToFit()
            case .failure: Color.black.overlay(Text("Image unavailable").font(.footnote).dimmed(0.6))
            default: Color.black.overlay(ProgressView().tint(ink))
            }
        }
        .id(imageID)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("The Sun at \(wavelength.name)")
    }

    private func section(_ title: String, note: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption2.weight(.medium)).textCase(.uppercase).tracking(0.8).dimmed(0.6)
            if let note { Text(note).font(.footnote).dimmed(0.75) }
            content()
        }
        .padding(.top, 24)
    }

    /// Last known location, or Chicago.
    private var observer: (lat: Double, lon: Double) {
        let c = CLLocationManager().location?.coordinate
        return (c?.latitude ?? 41.8781, c?.longitude ?? -87.6298)
    }

    @ViewBuilder
    private var auroraMap: some View {
        if let ovation {
            AuroraMap(cells: ovation.cells.map { GridValue(lon: $0.lon, lat: $0.lat, value: $0.probability) }, observer: observer, ink: ink)
                .accessibilityElement()
                .accessibilityLabel(auroraDescription(ovation))
            Text("Chance of visible aurora overhead, OVATION model, for \(ovation.forecastTime.formatted(date: .omitted, time: .shortened)). Brighter green is more likely.")
                .font(.caption2).dimmed(0.6)
        } else {
            Text("Loading").font(.footnote).dimmed(0.6)
        }
    }

    /// Highest aurora probability at or poleward of the observer's latitude in their hemisphere.
    private func auroraDescription(_ o: Ovation) -> String {
        let lat = observer.lat
        let near = o.cells.filter { abs($0.lat - lat) <= 5 && (($0.lat >= 0) == (lat >= 0)) }.map(\.probability).max() ?? 0
        return "Aurora forecast map. Highest chance within 5 degrees of your latitude: \(Int(near)) percent."
    }

    @ViewBuilder
    private var flares: some View {
        if let last = xray.last {
            let peak = xray.max { $0.flux < $1.flux }!
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                stat("Now", XRay.flareClass(last.flux))
                stat("24 h peak", XRay.flareClass(peak.flux))
                stat("Peak at", peak.time.formatted(date: .omitted, time: .shortened))
            }
            Chart {
                ForEach(xray) { s in
                    LineMark(x: .value("Time", s.time), y: .value("Flux", s.flux))
                        .foregroundStyle(ink)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
                ForEach([("C", 1e-6), ("M", 1e-5), ("X", 1e-4)], id: \.0) { c in
                    RuleMark(y: .value("Class", c.1))
                        .foregroundStyle(c.0 == "C" ? ink.opacity(0.25) : accent.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            Text(c.0).font(.caption2).dimmed(0.7)
                        }
                }
            }
            .chartYScale(domain: 1e-8...1e-3, type: .log)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                    AxisGridLine().foregroundStyle(ink.opacity(0.15))
                    AxisValueLabel(format: .dateTime.hour()).foregroundStyle(ink.opacity(0.6))
                }
            }
            .frame(height: 160)
        } else {
            Text("Loading").font(.footnote).dimmed(0.6)
        }
    }

    @ViewBuilder
    private var kpChart: some View {
        if kp.isEmpty {
            Text("Loading").font(.footnote).dimmed(0.6)
        } else {
            Chart(kp) { bar in
                BarMark(x: .value("Start", bar.start, unit: .hour), y: .value("Kp", bar.kp), width: .ratio(0.8))
                    .foregroundStyle(bar.kp >= 5 ? accent : ink.opacity(bar.predicted ? 0.3 : 0.85))
            }
            .chartYScale(domain: 0...9)
            .chartYAxis {
                AxisMarks(values: [0, 3, 5, 7, 9]) { v in
                    AxisGridLine().foregroundStyle(ink.opacity(0.15))
                    AxisValueLabel().foregroundStyle(ink.opacity(0.6))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine().foregroundStyle(ink.opacity(0.15))
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated)).foregroundStyle(ink.opacity(0.6))
                }
            }
            .frame(height: 140)
            Text("Solid: observed. Faint: forecast. Red: storm level (Kp 5 or more).")
                .font(.caption2).dimmed(0.6)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).dimmed(0.6)
            Text(value).font(.title3.weight(.medium).monospacedDigit())
        }
    }
}
