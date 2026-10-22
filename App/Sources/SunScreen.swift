import Charts
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
    @State private var solarWind: SolarWind?
    @State private var regions: [SolarRegion] = []
    @State private var forecast: SunForecast?
    @AppStorage("sunRegionLabels") private var regionLabels = true
    @Environment(\.dynamicTypeSize) private var typeSize

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
                    Text(SunFeeds.source(data)).font(.caption).dimmed(0.5).padding(.top, 4)
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
                if !regions.isEmpty {
                    Toggle("Region numbers", isOn: $regionLabels).font(.footnote).tint(accent).padding(.top, 8)
                }
                Text(wavelength.caption).font(.footnote).dimmed(0.75).padding(.top, 8)
                Text(SolarImage.credit).font(.caption2).dimmed(0.5).padding(.top, 4)

                section("The Sun here today", note: "When the Sun rises and sets where you are, and the soft light of the golden and blue hours.") { SunToday(ink: ink, accent: accent) }
                section("Aurora tonight", note: "NOAA's forecast of where the aurora may be overhead in the next hour; brighter green is more likely. From a few hundred kilometres further from the pole it can still be seen low on the horizon.") { auroraMap }
                if let solarWind {
                    section("Solar wind", note: "Measured 1.5 million km sunward of Earth, 30 to 60 minutes before it arrives. When Bz, the north–south part of its magnetic field, turns strongly negative (south), aurora often follows.") { solarWindPanel(solarWind) }
                }
                if let f = forecast, !f.enlil.isEmpty {
                    section("Solar wind forecast", note: "NOAA's WSA-Enlil model of the solar wind speed at Earth, in km/s, for the coming days. Shaded: a coronal mass ejection arriving, which can bring a storm.") { EnlilChart(points: f.enlil, ink: ink, accent: accent) }
                }
                if let f = forecast, !f.ccor2.isEmpty {
                    section("Coronagraph", note: "The Sun's outer corona from NOAA's CCOR-2 on SOLAR-1, with the bright disk blocked. Coronal mass ejections show as expanding clouds.") { CoronagraphLoop(frames: f.ccor2, ink: ink, accent: accent) }
                }
                section("Solar flares, last 24 h", note: "X-rays from the Sun, measured by NOAA's GOES satellites. Spikes are flares: M and X class can disrupt radio and GPS, and the biggest can bring a storm a day or two later.") {
                    flares
                    if let p = data?.probabilities { probabilityTable(p) }
                }
                if let c = forecast?.cycle {
                    section("Solar cycle 25", note: "Monthly sunspot numbers since the cycle began in December 2019 (bars), smoothed (red), and NOAA's prediction with its range.") { CycleChart(cycle: c, ink: ink, accent: accent) }
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
        if data == nil { await show(SunFeeds.lastSaved()) }
        if let apiBase { solarWind = (try? await SolarWind.fetch(base: apiBase)) ?? solarWind }
        regions = (try? await SolarRegion.fetch()) ?? regions
        if let apiBase { forecast = (try? await SunForecast.fetch(base: apiBase)) ?? forecast }
        if force { imageID = .now }
        let result = await SunFeeds.load(force: force)
        await show(result?.snapshot)
        failed = !(result?.complete ?? false)
    }

    private func show(_ snapshot: SunSnapshot?) async {
        guard let snapshot else { return }
        data = snapshot
        summary = await SunFeeds.summary(snapshot)
    }

    /// An SDO image, with the frame's time when it comes from the cache because nothing loaded (`saved`) or because
    /// SDO's latest frame was not usable (`frame`).
    private struct Picture {
        var wavelength: SolarImage
        var image: UIImage
        var loaded: Date
        var saved: Date?
        var frame: Date?
    }

    /// SDO sends no-store, so the last usable image of each wavelength is saved to Caches for use offline, dated with
    /// the frame's time. When the latest frame is black or partly covered, the saved one or one from SDO's archive is
    /// shown instead. A fresh image of the same wavelength under 5 minutes old is kept.
    private func loadImage() async {
        let w = wavelength
        if let p = picture, p.wavelength == w, p.saved == nil, p.loaded > imageID, Date.now.timeIntervalSince(p.loaded) < 300 { return }
        let file = URL.cachesDirectory.appending(path: "SDO/\(w.rawValue).jpg")
        picture = nil
        imageFailed = false
        if let (data, response) = try? await URLSession.shared.data(from: w.url(size: 1024)),
           let http = response as? HTTPURLResponse, http.statusCode == 200, let image = UIImage(data: data) {
            if w.isUsable(data) {
                picture = Picture(wavelength: w, image: await decoded(image), loaded: .now)
                let modified = http.value(forHTTPHeaderField: "Last-Modified").flatMap { try? Date($0, strategy: .http) }
                save(data, time: modified ?? .now, to: file)
                return
            }
            var frame = savedFrame(file, w)
            if frame == nil, let found = await w.lastUsableFrame() {
                frame = found
                save(found.data, time: found.time, to: file)
            }
            guard !Task.isCancelled else { return }
            if let frame, let saved = UIImage(data: frame.data) {
                picture = Picture(wavelength: w, image: await decoded(saved), loaded: .now, frame: frame.time)
            } else {
                picture = Picture(wavelength: w, image: await decoded(image), loaded: .now)
            }
            return
        }
        guard !Task.isCancelled else { return }
        if let frame = savedFrame(file, w), let image = UIImage(data: frame.data) {
            picture = Picture(wavelength: w, image: await decoded(image), loaded: .now, saved: frame.time)
        } else {
            imageFailed = true
        }
    }

    /// The image decoded off the main thread, so its first draw does not decode the JPEG there.
    private func decoded(_ image: UIImage) async -> UIImage {
        await image.byPreparingForDisplay() ?? image
    }

    /// The saved image and its frame time, if it is usable: images saved before the check may be black.
    private func savedFrame(_ file: URL, _ w: SolarImage) -> (data: Data, time: Date)? {
        guard let data = try? Data(contentsOf: file), w.isUsable(data) else { return nil }
        let time = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return (data, time ?? .distantPast)
    }

    private func save(_ data: Data, time: Date, to file: URL) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: file.path(percentEncoded: false))
    }

    /// "16:26 UT", with the day when it is not today in UT.
    private func universalTime(_ date: Date) -> String {
        let utc = TimeZone(identifier: "UTC")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let format: Date.FormatString = calendar.isDate(date, inSameDayAs: .now)
            ? "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)"
            : "\(day: .defaultDigits) \(month: .abbreviated) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)"
        return date.formatted(Date.VerbatimFormatStyle(format: format, locale: .current, timeZone: utc, calendar: calendar)) + " UT"
    }

    private var image: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let picture {
                    Image(uiImage: picture.image).resizable().scaledToFit()
                        .overlay { if regionLabels { regionOverlay(at: picture.frame ?? picture.saved ?? picture.loaded) } }
                } else if imageFailed {
                    Color.black.overlay(Text("Image unavailable").font(.footnote).dimmed(0.6))
                } else {
                    Color.black.overlay(ProgressView().tint(ink))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .accessibilityLabel("The Sun at \(wavelength.name)")
            if let saved = picture?.saved {
                Text("Couldn't load a new image. This one is from \(saved.formatted(.relative(presentation: .named))).")
                    .font(.caption2).foregroundStyle(accent)
            } else if let frame = picture?.frame {
                Text("Latest complete frame from \(universalTime(frame))").font(.caption).dimmed(0.6)
            }
        }
    }

    /// NOAA region numbers where each region is at `date`, from SWPC's daily report turned with the Sun.
    private func regionOverlay(at date: Date) -> some View {
        GeometryReader { g in
            let r = wavelength.diskRadius * g.size.width
            ForEach(regions) { region in
                if let p = region.disk(at: date) {
                    Text(String(region.number))
                        .font(.system(size: 10, weight: .medium)).monospacedDigit()
                        .foregroundStyle(.white).shadow(color: .black, radius: 2)
                        .position(x: g.size.width / 2 + p.x * r, y: g.size.height / 2 - p.y * r - 10)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Three columns, stacked at accessibility text sizes.
    private func scalesStrip(_ s: NOAAScales) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            scale("R", "Radio", s.current.r, s.past24h.r)
            Rectangle().fill(ink.opacity(0.25)).frame(width: stacked ? nil : 0.5, height: stacked ? 0.5 : nil)
            scale("S", "Radiation", s.current.s, s.past24h.s)
            Rectangle().fill(ink.opacity(0.25)).frame(width: stacked ? nil : 0.5, height: stacked ? 0.5 : nil)
            scale("G", "Geomagnetic", s.current.g, s.past24h.g)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func scale(_ letter: String, _ title: String, _ level: Int, _ past: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).dimmed(0.6)
            Text("\(letter)\(level)").font(.title.weight(.medium).monospacedDigit())
                .foregroundStyle(level >= 1 ? accent : ink)
            Text(NOAAScales.levelName(level)).font(.footnote)
            Text("24 h max \(letter)\(past)").font(.caption).dimmed(0.6)
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

    /// The Sky tab's place.
    private var observer: (lat: Double, lon: Double) {
        let o = SkyModel.shared.observer
        return (o.latitude, o.longitude)
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
                ForEach(XRay.maxima(xray)) { s in
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
            // The whole day, not just the first and last 5-minute maxima.
            .chartXScale(domain: xray[0].time...last.time)
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

    private func solarWindPanel(_ w: SolarWind) -> some View {
        let n = { (v: Double?, f: Int) in v.map { $0.formatted(.number.precision(.fractionLength(f))) } ?? "–" }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 20) {
                stat("Speed, km/s", n(w.speed, 0))
                stat("Density, /cm³", n(w.density, 1))
                stat("Bz, nT", n(w.bz, 1))
                stat("Field, nT", n(w.bt, 1))
            }
            Chart(w.series.filter { $0.bz != nil }) { p in
                LineMark(x: .value("Time", p.t), y: .value("Bz", p.bz ?? 0)).foregroundStyle(ink)
                RuleMark(y: .value("Zero", 0)).foregroundStyle(ink.opacity(0.3))
                RuleMark(y: .value("Strong south", -10)).foregroundStyle(accent.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            }
            .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(ink.opacity(0.15)); AxisValueLabel().foregroundStyle(ink.opacity(0.6)) } }
            .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 2)) { _ in AxisValueLabel(format: .dateTime.hour()).foregroundStyle(ink.opacity(0.6)) } }
            .frame(height: 110)
            Text("Bz over 6 hours, 5-minute means. Dashed: −10 nT. From \(w.source), \(w.observedAt.formatted(date: .omitted, time: .shortened)).")
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

    /// Summary for the Sky tab's place and night. A night that has ended is worked out again on the `Astronomer` actor.
    static func summary(_ s: SunSnapshot, at date: Date = .now) async -> String? {
        let sky = SkyModel.shared, observer = sky.observer
        var tonight = sky.tonight
        if tonight.map({ $0.end <= date }) ?? true { tonight = try? await sky.astronomer.tonight(at: date, from: observer) }
        let night = tonight.map { DateInterval(start: $0.start, end: $0.end) } ?? DateInterval(start: date, duration: 0)
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
