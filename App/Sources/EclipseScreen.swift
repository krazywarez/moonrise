import ActivityKit
import SkyEngine
import SkyRenderer
import SwiftUI

/// Map of a total or annular eclipse's path, with timings at greatest eclipse and for the observer.
struct EclipseScreen: View {
    var date: Date
    var observer: Observer
    var placeName: String
    @State private var path: EclipsePath?
    @State private var local: LocalEclipse?
    @State private var timeline: EclipseTimeline?
    @State private var loaded = false
    @State private var location = EclipseLocation()
    /// Time zone at the site, from Apple Maps; times are also given in UTC, and only in UTC when this is unknown.
    @State private var zone: TimeZone?
    @State private var city: String?
    @State private var day: Day?
    @State private var activityNote: String?
    @AppStorage(SettingsKey.locationMode) private var locationMode = "current"
    @Environment(\.dismiss) private var dismiss

    /// The latest precise fix, or the place the screen was opened for (a chosen city, or the last coarse fix).
    private var site: Observer { locationMode == "city" ? observer : location.fix?.observer ?? observer }

    private let ink = Color(red: 0.95, green: 0.95, blue: 0.93)
    private let accent = Color(red: 0.88, green: 0.24, blue: 0.19)

    private enum Day: Identifiable {
        case live, rehearsal
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let path {
                        EclipseMap(path: path, observer: site, ink: ink, accent: accent)
                            .aspectRatio(1.6, contentMode: .fit)
                            .accessibilityLabel("Map of the path of the eclipse")
                        facts(path)
                    } else if loaded {
                        Text("This eclipse is partial everywhere, so there is no path to map.").font(.footnote).dimmed(0.7)
                    } else {
                        ProgressView().tint(ink).frame(maxWidth: .infinity, minHeight: 200)
                    }
                    if loaded { here }
                    if let timeline {
                        SunDiagram(timeline: timeline, ink: ink, accent: accent)
                        dayTools(timeline)
                    }
                }
                .padding(20)
                .readableWidth()
            }
            .background(Color.black.ignoresSafeArea())
            .foregroundStyle(ink)
            .navigationTitle(path.map { "\($0.kind) solar eclipse" } ?? "Solar eclipse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fullScreenCover(item: $day) { d in
                EclipseDayScreen(date: date, observer: observer, placeName: placeName, zone: zone, rehearsal: d == .rehearsal, location: location)
            }
        }
        .task {
            let date = date
            path = await Task.detached { EclipsePath.compute(near: date) }.value
            loaded = true
        }
        .task(id: site) {
            let date = date, site = site, accuracy = locationMode == "city" ? nil : location.fix?.accuracy
            (local, timeline) = await Task.detached {
                let l = LocalEclipse.at(site, near: date)
                return (l, l.flatMap { try? EclipseTimeline($0, observer: site, accuracy: accuracy) })
            }.value
        }
        .task(id: [(site.latitude * 10).rounded(), (site.longitude * 10).rounded()]) {
            if let s = await EclipseLocation.site(at: site) { (zone, city) = s }
        }
        .onAppear { if locationMode != "city" { location.start() } }
        .onDisappear { if locationMode != "city" { location.stop() } }
    }

    private func facts(_ p: EclipsePath) -> some View {
        let middle = p.points.min { abs($0.date.timeIntervalSince(p.peak)) < abs($1.date.timeIntervalSince(p.peak)) }
        var rows: [(String, String)] = [
            ("Date", p.peak.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: .gmt))),
            ("Greatest eclipse", "\(p.peak.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: .gmt))) UTC at \(latLon(p.greatest))"),
        ]
        if let d = p.centralDuration { rows.append(("\(p.kind == "Total" ? "Totality" : "Annularity") there", minutes(d))) }
        if let m = middle { rows.append(("Path width there", "\(Int(m.widthKm.rounded())) km")) }
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            ForEach(rows, id: \.0) { r in
                GridRow { Text(r.0).dimmed(0.7); Text(r.1).monospacedDigit() }.font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private var here: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(placeLabel).font(.caption2.weight(.medium)).textCase(.uppercase).tracking(0.8).dimmed(0.6)
            if let l = local {
                let central = l.kind == "Total" ? "Totality" : "Annular phase"
                let zones = [zone, .gmt].compactMap { $0 }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("")
                        if let zone { Text("Local, \(utcOffset(zone, at: l.peak))").dimmed(0.6) }
                        Text("UTC").dimmed(0.6)
                    }
                    .font(.caption)
                    GridRow { Text("Begins").dimmed(0.7); ForEach(zones, id: \.self) { Text(time(l.partialBegin, $0)) } }
                    if let b = l.centralBegin, let e = l.centralEnd {
                        GridRow { Text("\(central) begins").dimmed(0.7); ForEach(zones, id: \.self) { Text(time(b, $0)) } }
                        GridRow { Text("\(central) ends").dimmed(0.7); ForEach(zones, id: \.self) { Text(time(e, $0)) } }
                    }
                    GridRow { Text("Maximum").dimmed(0.7); ForEach(zones, id: \.self) { Text(time(l.peak, $0)) } }
                    GridRow { Text("Ends").dimmed(0.7); ForEach(zones, id: \.self) { Text(time(l.partialEnd, $0)) } }
                }
                .font(.subheadline.monospacedDigit())
                if let b = l.centralBegin, let e = l.centralEnd {
                    Text("\(central) lasts \(minutes(e.timeIntervalSince(b))).").font(.subheadline)
                }
                Text("\(Int((l.obscuration * 100).rounded()))% of the Sun covered at maximum.").font(.subheadline)
                if zone == nil {
                    Text("Local time at this site needs a connection to look up, so times are in UTC.").font(.footnote).dimmed(0.7)
                }
                if l.peakAltitude < 10 {
                    Text("The Sun is low at maximum (\(Int(l.peakAltitude.rounded()))°). Find a clear horizon.").font(.footnote).dimmed(0.7)
                }
            } else {
                Text("Not visible from here.").font(.subheadline).dimmed(0.7)
            }
            Text("Never look at the Sun without certified eclipse glasses, except during totality itself.")
                .font(.footnote).foregroundStyle(accent).padding(.top, 6)
        }
    }

    private func dayTools(_ t: EclipseTimeline) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Eclipse day").font(.caption2.weight(.medium)).textCase(.uppercase).tracking(0.8).dimmed(0.6)
            if t.eclipse.partialEnd > .now {
                Button("Start the countdown") { day = .live }
                Button("Show contact times on the Lock Screen") { scheduleActivity(t) }
            }
            Button("Rehearse from three minutes before \(t.eclipse.kind == "Total" ? "totality" : "maximum")") { day = .rehearsal }
            if let activityNote { Text(activityNote).font(.footnote).dimmed(0.7) }
            Text("The countdown speaks each cue and taps at the contacts while Moonrise is open, and keeps the screen on.")
                .font(.footnote).dimmed(0.7)
        }
        .tint(accent)
    }

    /// Adds a Live Activity that appears 30 minutes before first contact, or now if that has passed.
    private func scheduleActivity(_ t: EclipseTimeline) {
        let e = t.eclipse
        let attributes = EclipseActivityAttributes(
            kind: e.kind, site: locationMode == "city" ? placeName : city ?? "your location",
            c1: e.partialBegin, c2: e.centralBegin, peak: e.peak, c3: e.centralEnd, c4: e.partialEnd, timeZone: zone?.identifier
        )
        let content = ActivityContent(state: EclipseActivityAttributes.ContentState(), staleDate: e.partialEnd)
        let start = e.partialBegin.addingTimeInterval(-1800)
        let clock = { (d: Date, date: Date.FormatStyle.DateStyle) in
            d.formatted(Date.FormatStyle(date: date, time: .shortened, timeZone: zone ?? .gmt)) + (zone == nil ? " UTC" : "")
        }
        Task {
            for a in Activity<EclipseActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
            do {
                if start > .now {
                    let alert = AlertConfiguration(title: "\(e.kind) eclipse today", body: "First contact at \(clock(e.partialBegin, .omitted)).", sound: .default)
                    _ = try Activity.request(attributes: attributes, content: content, style: .standard, alertConfiguration: alert, start: start)
                    activityNote = "It will appear on the Lock Screen on \(clock(start, .abbreviated)), 30 minutes before first contact."
                } else {
                    _ = try Activity.request(attributes: attributes, content: content)
                    activityNote = "Contact times are on the Lock Screen."
                }
            } catch {
                activityNote = "Could not add it to the Lock Screen: \(error.localizedDescription)"
            }
        }
    }

    private var placeLabel: String {
        if locationMode != "city", let fix = location.fix { return "From your location, ±\(Int(fix.accuracy.rounded())) m" }
        return "From \(placeName)"
    }

    /// To the nearest second in `zone`.
    private func time(_ d: Date, _ zone: TimeZone) -> String {
        Date(timeIntervalSinceReferenceDate: d.timeIntervalSinceReferenceDate.rounded()).formatted(Date.FormatStyle(date: .omitted, time: .standard, timeZone: zone))
    }

    private func minutes(_ s: TimeInterval) -> String { "\(Int(s) / 60) m \(Int(s) % 60) s" }

    private func latLon(_ p: (lat: Double, lon: Double)) -> String {
        String(format: "%.1f°%@, %.1f°%@", abs(p.lat), p.lat >= 0 ? "N" : "S", abs(p.lon), p.lon >= 0 ? "E" : "W")
    }
}

/// Equirectangular map around the path: coastlines, the band between the limits, and the centre line.
struct EclipseMap: View {
    var path: EclipsePath
    var observer: Observer
    var ink: Color
    var accent: Color

    var body: some View {
        Canvas { context, size in
            let centers = path.points.map(\.center)
            let lats = centers.map(\.lat), lons = centers.map(\.lon)
            let latRange = (lats.min()! - 8)...(lats.max()! + 8)
            let lonRange = (lons.min()! - 10)...(lons.max()! + 10)
            func pt(_ lat: Double, _ lon: Double) -> CGPoint {
                CGPoint(x: (lon - lonRange.lowerBound) / (lonRange.upperBound - lonRange.lowerBound) * size.width,
                        y: (latRange.upperBound - lat) / (latRange.upperBound - latRange.lowerBound) * size.height)
            }

            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(ink.opacity(0.04)))
            var grid = Path()
            for lat in stride(from: -80.0, through: 80, by: 10) where latRange.contains(lat) {
                grid.move(to: pt(lat, lonRange.lowerBound)); grid.addLine(to: pt(lat, lonRange.upperBound))
            }
            for lon in stride(from: -180.0, through: 180, by: 10) where lonRange.contains(lon) {
                grid.move(to: pt(latRange.lowerBound, lon)); grid.addLine(to: pt(latRange.upperBound, lon))
            }
            context.stroke(grid, with: .color(ink.opacity(0.08)), lineWidth: 0.5)

            var coast = Path()
            for line in Coastline.lines {
                var pen = false
                for p in line {
                    let q = pt(p.lat, p.lon)
                    if pen { coast.addLine(to: q) } else { coast.move(to: q); pen = true }
                }
            }
            context.stroke(coast, with: .color(ink.opacity(0.55)), lineWidth: 0.8)

            let limits = path.points.compactMap { p in p.north.flatMap { n in p.south.map { (n, $0) } } }
            if limits.count > 1 {
                var band = Path()
                band.move(to: pt(limits[0].0.lat, limits[0].0.lon))
                for l in limits.dropFirst() { band.addLine(to: pt(l.0.lat, l.0.lon)) }
                for l in limits.reversed() { band.addLine(to: pt(l.1.lat, l.1.lon)) }
                band.closeSubpath()
                context.fill(band, with: .color(accent.opacity(0.4)))
            }
            var center = Path()
            center.addLines(centers.map { pt($0.lat, $0.lon) })
            context.stroke(center, with: .color(accent), lineWidth: 1.2)

            let g = pt(path.greatest.lat, path.greatest.lon)
            context.stroke(Path(ellipseIn: CGRect(x: g.x - 5, y: g.y - 5, width: 10, height: 10)), with: .color(ink), lineWidth: 1.5)
            if latRange.contains(observer.latitude), lonRange.contains(observer.longitude) {
                let o = pt(observer.latitude, observer.longitude)
                context.fill(Path(ellipseIn: CGRect(x: o.x - 4, y: o.y - 4, width: 8, height: 8)), with: .color(ink))
                context.draw(Text("You").font(.caption2).foregroundStyle(ink), at: CGPoint(x: o.x, y: o.y - 11))
            }
        }
        .overlay(alignment: .bottomLeading) {
            Text("Shaded: where the eclipse is \(path.kind.lowercased()). Ring: greatest eclipse.")
                .font(.caption2).dimmed(0.7).padding(6)
        }
    }
}

/// The Sun's path across the sky from first to last contact: altitude against compass bearing,
/// with a line every fist width (about 10° at arm's length) above the horizon.
struct SunDiagram: View {
    var timeline: EclipseTimeline
    var ink: Color
    var accent: Color

    var body: some View {
        let path = (try? timeline.sunPath(every: 300)) ?? []
        let key = timeline.contacts.first { $0.name == (timeline.eclipse.kind == "Total" ? "C2" : "Max") } ?? timeline.contacts[0]
        VStack(alignment: .leading, spacing: 8) {
            Canvas { context, size in draw(path, context: &context, size: size) }
                .frame(height: 180)
                .accessibilityHidden(true)
            Text("At \(timeline.eclipse.kind == "Total" ? "totality" : "maximum") the Sun is \(Int(key.sun.altitude.rounded()))° up, about \(Int((key.sun.altitude / 10).rounded())) fists above the horizon at arm's length, bearing \(Int(key.sun.azimuth.rounded()))° \(compass(key.sun.azimuth)). Check that no trees or buildings will be in the way.")
                .font(.footnote).dimmed(0.8)
        }
    }

    private func draw(_ samples: [(date: Date, sun: Horizontal)], context: inout GraphicsContext, size: CGSize) {
        guard let first = samples.first else { return }
        // Azimuths unwrapped so a path through north stays continuous.
        func unwrap(_ a: Double) -> Double { first.sun.azimuth + remainder(a - first.sun.azimuth, 360) }
        let az = samples.map { unwrap($0.sun.azimuth) }
        let mid = (az.min()! + az.max()!) / 2, half = max(45, (az.max()! - az.min()!) / 2 + 20)
        let top = min(90, ((samples.map(\.sun.altitude).max() ?? 0) / 10).rounded(.up) * 10 + 10)
        let base = size.height - 16
        func pt(_ alt: Double, _ azimuth: Double) -> CGPoint {
            CGPoint(x: (azimuth - (mid - half)) / (2 * half) * size.width, y: base - max(alt, 0) / top * (base - 8))
        }

        var grid = Path()
        for alt in stride(from: 10.0, through: top, by: 10) {
            grid.move(to: pt(alt, mid - half)); grid.addLine(to: pt(alt, mid + half))
        }
        context.stroke(grid, with: .color(ink.opacity(0.12)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
        for alt in stride(from: 20.0, through: top, by: 20) {
            context.draw(Text("\(Int(alt))°").font(.system(size: 9)).foregroundStyle(ink.opacity(0.5)), at: pt(alt, mid - half), anchor: .bottomLeading)
        }
        var horizon = Path()
        horizon.move(to: CGPoint(x: 0, y: base)); horizon.addLine(to: CGPoint(x: size.width, y: base))
        context.stroke(horizon, with: .color(ink.opacity(0.6)), lineWidth: 1)
        for bearing in stride(from: ((mid - half) / 45).rounded(.up) * 45, through: mid + half, by: 45) {
            context.draw(Text(compass(bearing)).font(.system(size: 10)).foregroundStyle(ink.opacity(0.7)), at: CGPoint(x: pt(0, bearing).x, y: base + 8))
        }

        var arc = Path()
        arc.addLines(zip(samples, az).map { pt($0.0.sun.altitude, $0.1) })
        context.stroke(arc, with: .color(ink.opacity(0.5)), lineWidth: 1)
        for c in timeline.contacts where c.name == "C1" || c.name == "C4" || c.name == (timeline.eclipse.kind == "Total" ? "C2" : "Max") {
            let p = pt(c.sun.altitude, unwrap(c.sun.azimuth))
            let key = c.name == "C2" || c.name == "Max"
            context.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(key ? accent : ink))
            context.draw(Text(c.name == "C2" ? "Totality" : c.name).font(.system(size: 10)).foregroundStyle(ink), at: CGPoint(x: p.x, y: p.y - 11))
        }
    }

    private func compass(_ azimuth: Double) -> String {
        let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let a = (azimuth.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return points[Int(((a + 11.25) / 22.5).rounded(.down)) % 16]
    }
}
