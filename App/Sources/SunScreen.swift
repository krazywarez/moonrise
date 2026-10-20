import Charts
import CoreLocation
import Feeds
import SkyEngine
import SkyRenderer
import SwiftUI

struct SunScreen: View {
    @State private var wavelength = SolarImage.corona
    @State private var data: SunSnapshot?
    @State private var summary: String?
    @State private var failed = false
    @State private var imageID = Date.now
    @State private var picture: Picture?
    @State private var imageFailed = false

    private var kp: [KpBar] { data?.kp ?? [] }
    private var xray: [XRaySample] { data?.xray ?? [] }
    private var ovation: Ovation? { data?.ovation }

    private let ink = Color(red: 0.95, green: 0.95, blue: 0.93)
    private let accent = Color(red: 0.88, green: 0.24, blue: 0.19)
    private let background = Color.black

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Sun").font(.title.weight(.medium))
                Rectangle().fill(accent).frame(width: 48, height: 5).padding(.top, 8).padding(.bottom, 12)
                if let summary, let data {
                    Text(summary)
                    Text(SunFeeds.source(data)).font(.caption2).dimmed(0.5).padding(.top, 4)
                } else if !failed {
                    Text("Loading").font(.footnote).dimmed(0.6)
                }
                if failed {
                    Text(data == nil ? "Couldn't load space weather. Pull to retry." : "Couldn't reach NOAA. Showing the last saved data. Pull to retry.")
                        .font(.footnote).foregroundStyle(accent).padding(.top, 8)
                }
                if let scales = data?.scales {
                    section("NOAA scales", note: "Radio blackouts (R), solar radiation storms (S) and geomagnetic storms (G), each from 0 (none) to 5 (extreme).") { scalesStrip(scales) }
                }

                image.padding(.top, 24)
                Picker("Wavelength", selection: $wavelength) {
                    ForEach(SolarImage.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.top, 12)
                Text(wavelength.caption).font(.footnote).dimmed(0.75).padding(.top, 8)
                Text(SolarImage.credit).font(.caption2).dimmed(0.5).padding(.top, 4)

                section("Aurora tonight", note: "NOAA's forecast of where the aurora may be overhead in the next hour; brighter green is more likely. From a few hundred kilometres further from the pole it can still be seen low on the horizon.") { auroraMap }
                section("Solar flares, last 24 h", note: "X-rays from the Sun, measured by NOAA's GOES satellites. Spikes are flares: M and X class can disrupt radio and GPS, and the biggest can bring a storm a day or two later.") {
                    flares
                    if let p = data?.probabilities { probabilityTable(p) }
                }
                section("Geomagnetic activity (Kp)", note: "How disturbed Earth's magnetic field is, from 0 (quiet) to 9. At 5 or more it is a storm and the aurora reaches lower latitudes.") { kpChart }

                Text("The Sun as NASA's Solar Dynamics Observatory sees it now, and the space weather it sends our way: flares, magnetic storms and the aurora.")
                    .font(.footnote).dimmed(0.6).padding(.top, 24)
                Text("Space weather data: NOAA Space Weather Prediction Center. Coastlines: Natural Earth.").font(.caption2).dimmed(0.5).padding(.vertical, 16)
            }
            .padding(.horizontal, 20)
            .readableWidth()
        }
        .foregroundStyle(ink)
        .background(background.ignoresSafeArea())
        .refreshable { await load(force: true) }
        .task { await load(force: false) }
        .task(id: "\(wavelength.rawValue) \(imageID)") { await loadImage() }
    }

    private func load(force: Bool) async {
        if data == nil { show(await SunFeeds.lastSaved()) }
        if force { imageID = .now }
        let result = await SunFeeds.load(force: force)
        show(result?.snapshot)
        failed = !(result?.complete ?? false)
    }

    private func show(_ snapshot: SunSnapshot?) {
        guard let snapshot else { return }
        data = snapshot
        summary = SunFeeds.summary(snapshot)
    }

    /// An SDO image, with the time it was saved when it comes from the cache.
    private struct Picture {
        var wavelength: SolarImage
        var image: UIImage
        var loaded: Date
        var saved: Date?
    }

    /// SDO sends no-store, so the last image of each wavelength is saved to Caches for use offline.
    /// A fresh image of the same wavelength under 5 minutes old is kept.
    private func loadImage() async {
        let w = wavelength
        if let p = picture, p.wavelength == w, p.saved == nil, p.loaded > imageID, Date.now.timeIntervalSince(p.loaded) < 300 { return }
        let file = URL.cachesDirectory.appending(path: "SDO/\(w.rawValue).jpg")
        picture = nil
        imageFailed = false
        if let (data, response) = try? await URLSession.shared.data(from: w.url(size: 1024)),
           (response as? HTTPURLResponse)?.statusCode == 200, let image = UIImage(data: data) {
            picture = Picture(wavelength: w, image: image, loaded: .now)
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
            return
        }
        guard !Task.isCancelled else { return }
        if let image = UIImage(contentsOfFile: file.path(percentEncoded: false)) {
            let saved = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            picture = Picture(wavelength: w, image: image, loaded: .now, saved: saved ?? .distantPast)
        } else {
            imageFailed = true
        }
    }

    private var image: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let picture {
                    Image(uiImage: picture.image).resizable().scaledToFit()
                } else if imageFailed {
                    Color.black.overlay(Text("Image unavailable").font(.footnote).dimmed(0.6))
                } else {
                    Color.black.overlay(ProgressView().tint(ink))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .accessibilityLabel("The Sun at \(wavelength.name)")
            if let saved = picture?.saved {
                Text("Couldn't load a new image. This one was saved \(saved.formatted(.relative(presentation: .named))).")
                    .font(.caption2).foregroundStyle(accent)
            }
        }
    }

    private func scalesStrip(_ s: NOAAScales) -> some View {
        HStack(alignment: .top, spacing: 12) {
            scale("R", "Radio", s.current.r, s.past24h.r)
            Rectangle().fill(ink.opacity(0.25)).frame(width: 0.5)
            scale("S", "Radiation", s.current.s, s.past24h.s)
            Rectangle().fill(ink.opacity(0.25)).frame(width: 0.5)
            scale("G", "Geomagnetic", s.current.g, s.past24h.g)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func scale(_ letter: String, _ title: String, _ level: Int, _ past: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).dimmed(0.6)
            Text("\(letter)\(level)").font(.title.weight(.medium).monospacedDigit())
                .foregroundStyle(level >= 1 ? accent : ink)
            Text(NOAAScales.levelName(level)).font(.footnote)
            Text("24 h max \(letter)\(past)").font(.caption2).dimmed(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Flare and proton chances by UT day, under the X-ray chart.
    private func probabilityTable(_ p: SolarProbabilities) -> some View {
        let utc = TimeZone(identifier: "UTC")!
        var weekday = Date.FormatStyle().weekday(.abbreviated)
        weekday.timeZone = utc
        let issued = Date.VerbatimFormatStyle(
            format: "\(day: .defaultDigits) \(month: .abbreviated) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            locale: .current, timeZone: utc, calendar: Calendar(identifier: .gregorian)
        )
        let days = p.days.indices.map { p.issued.addingTimeInterval(Double($0) * 86_400).formatted(weekday) }
        let rows: [(String, KeyPath<SolarProbabilities.Day, Int>)] = [("C-class flare", \.c), ("M-class flare", \.m), ("X-class flare", \.x), ("Proton event", \.proton)]
        return VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Chance")
                    ForEach(days.indices, id: \.self) { Text(days[$0]).gridColumnAlignment(.trailing) }
                }
                .font(.caption2).dimmed(0.6)
                ForEach(rows, id: \.0) { row in
                    GridRow {
                        Text(row.0).dimmed(0.7)
                        ForEach(p.days.indices, id: \.self) { Text("\(p.days[$0][keyPath: row.1])%").monospacedDigit() }
                    }
                    .font(.subheadline)
                }
            }
            Text("NOAA SWPC forecast dated \(p.issued.formatted(issued)) UT, by UT day. A proton event is a solar radiation storm of S1 or more.")
                .font(.caption2).dimmed(0.6)
        }
        .padding(.top, 8)
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

/// NOAA feeds for the Sun tab and the 3D view's caption. The last complete set is saved to Application Support
/// and stands in for any feed that fails to load.
@MainActor
enum SunFeeds {
    private static let file = URL.applicationSupportDirectory.appending(path: "SunSnapshot.json")
    private static var saved: SunSnapshot?

    /// NOAA updates these every minute or so; a load within 5 minutes of the last one reuses it.
    /// `complete` is false when any feed came from the saved set, whose `fetched` date the result then carries.
    /// `nil` only when nothing loaded and nothing was saved.
    static func load(force: Bool) async -> (snapshot: SunSnapshot, complete: Bool)? {
        if !force, let hit: SunSnapshot = FeedMemo.get("sun", maxAge: 300) { return (hit, true) }
        async let k = try? SpaceWeather.fetchKpBars()
        async let x = try? XRay.fetch()
        async let o = try? Ovation.fetch()
        async let s = try? NOAAScales.fetch()
        async let p = try? SolarProbabilities.fetch()
        let (kp, xray, ovation, scales, probabilities) = await (k, x, o, s, p)
        if let kp, let xray, let ovation, let scales, let probabilities {
            let fresh = SunSnapshot(fetched: .now, kp: kp, xray: xray, ovation: ovation, scales: scales, probabilities: probabilities)
            FeedMemo.set("sun", fresh)
            saved = fresh
            let file = file
            Task.detached(priority: .utility) { try? fresh.save(to: file) }
            return (fresh, true)
        }
        let old = await lastSaved()
        guard kp != nil || xray != nil || ovation != nil || scales != nil || probabilities != nil || old != nil else { return nil }
        let merged = SunSnapshot(
            fetched: old?.fetched ?? .now,
            kp: kp ?? old?.kp ?? [],
            xray: xray ?? old?.xray ?? [],
            ovation: ovation ?? old?.ovation,
            scales: scales ?? old?.scales,
            probabilities: probabilities ?? old?.probabilities
        )
        return (merged, false)
    }

    /// The last complete set, read from disk on first use.
    static func lastSaved() async -> SunSnapshot? {
        if saved == nil {
            let file = file
            saved = await Task.detached { SunSnapshot.load(from: file) }.value
        }
        return saved
    }

    /// Summary for the last known location, or Chicago.
    static func summary(_ s: SunSnapshot, at date: Date = .now) -> String? {
        let observer = CLLocationManager().location.map { Observer(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) } ?? SkyModel.fallback
        let night = (try? Tonight(at: date, from: observer)).map { DateInterval(start: $0.start, end: $0.end) } ?? DateInterval(start: date, duration: 0)
        return SunSummary.text(
            scales: s.scales, kp: s.kp, probabilities: s.probabilities, xray: s.xray,
            geomagneticLatitude: Geomagnetic.latitude(observer), night: night, at: date
        )
    }

    /// Source and age: "NOAA SWPC, 21:13", or "NOAA SWPC data from 3 hours ago" once it is over 15 minutes old.
    static func source(_ s: SunSnapshot) -> String {
        Date.now.timeIntervalSince(s.fetched) < 900
            ? "NOAA SWPC, \(s.fetched.formatted(date: .omitted, time: .shortened))"
            : "NOAA SWPC data from \(s.fetched.formatted(.relative(presentation: .named)))"
    }
}
