import Feeds
import SkyEngine
import SwiftUI

/// Tonight's details: moon, planets, sun and space weather.
struct TodaySheet: View {
    @Bindable var model: SkyModel
    var ink: Color
    var background: Color

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let t = model.tonight {
                    section("Tonight") { Text(t.moonAndDarkness()).font(.subheadline.monospacedDigit()) }
                    section("Moon") { moon(t) }
                    section("Planets tonight") { planets(t) }
                    section("Sun") { sun(t) }
                }
                section("Satellite passes") { satellites }
                section("Space weather") { weather }
                Text("Space weather data: NOAA Space Weather Prediction Center.")
                    .font(.caption2).dimmed(0.5).padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
        }
        .foregroundStyle(ink)
        .presentationBackground(background)
        .task { await model.refreshPasses() }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption2.weight(.medium)).textCase(.uppercase).tracking(0.8).dimmed(0.6)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(ink.opacity(0.25)).frame(height: 0.5) }
    }

    private func moon(_ t: Tonight) -> some View {
        let quarter = switch t.nextQuarter.quarter {
        case .new: "New moon"
        case .firstQuarter: "First quarter"
        case .full: "Full moon"
        case .lastQuarter: "Last quarter"
        }
        return rows([
            ("Illuminated", "\(Int((t.moonIllumination * 100).rounded()))%, \(t.moonPhase < 180 ? "waxing" : "waning")"),
            (quarter, t.nextQuarter.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())),
        ])
    }

    private func planets(_ t: Tonight) -> some View {
        rows(t.planets.map { p in
            let name = p.body.rawValue.capitalized
            guard let best = p.best else { return (name, "not well placed tonight") }
            var parts: [String] = []
            if p.now.altitude > 0 {
                parts.append(String(format: "up now, %.0f° %@", p.now.altitude, compass(p.now.azimuth)))
            } else if let rise = p.rise, rise < t.end {
                parts.append("rises \(time(rise))")
            }
            // A best point at the end of the window means it is still climbing at dawn.
            if t.end.timeIntervalSince(best.date) < 900 {
                parts.append(String(format: "%.0f° %@ by dawn", best.position.altitude, compass(best.position.azimuth)))
            } else {
                parts.append(String(format: "highest %@ at %.0f°", time(best.date), best.position.altitude))
            }
            return (name, parts.joined(separator: " · "))
        })
    }

    private func sun(_ t: Tonight) -> some View {
        rows([
            ("Sunset", t.sunset.map(time) ?? "already set"),
            ("Sunrise", t.sunrise.map(time) ?? "–"),
        ])
    }

    @ViewBuilder
    private var satellites: some View {
        let shown = model.passes.filter(\.featured).prefix(8)
        if shown.isEmpty {
            Text("No passes above 10° in the next three days.").font(.subheadline).dimmed(0.6)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(shown)) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(p.displayName).font(.subheadline.weight(.medium))
                            if p.visible {
                                Text("Visible").font(.caption2.weight(.medium)).padding(.horizontal, 5).padding(.vertical, 1)
                                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(lineWidth: 1))
                            }
                        }
                        Text(p.rise.formatted(.dateTime.weekday(.abbreviated).hour().minute()) + String(format: " · rises %@, highest %.0f°, sets %@", compass(p.riseAzimuth), p.maxAltitude, compass(p.setAzimuth))
                             + (p.moonNote(from: model.observer).map { " · \($0)" } ?? ""))
                            .font(.footnote.monospacedDigit()).dimmed(0.8)
                    }
                    .accessibilityElement(children: .combine)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 44)
                    .overlay(alignment: .trailing) { PassFollowButton(pass: p) }
                }
                let others = alsoVisible
                if !others.isEmpty {
                    Text("Also visible tonight").font(.caption2.weight(.medium)).textCase(.uppercase).tracking(0.8).dimmed(0.6).padding(.top, 6)
                    ForEach(others) { p in
                        Text("\(p.displayName) · \(p.rise.formatted(date: .omitted, time: .shortened)), highest \(Int(p.maxAltitude.rounded()))°" + (p.moonNote(from: model.observer).map { " · \($0)" } ?? ""))
                            .font(.footnote.monospacedDigit()).dimmed(0.8)
                    }
                }
                Text("Visible means sunlit while your sky is dark. Orbits: CelesTrak.").font(.caption2).dimmed(0.6)
            }
        }
    }

    /// The five highest passes tonight of other bright satellites (rocket bodies, old satellites), in time order.
    private var alsoVisible: [SatellitePass] {
        guard let t = model.tonight else { return [] }
        return Array(model.passes
            .filter { !$0.featured && $0.visible && $0.rise >= t.start && $0.rise <= t.end && $0.maxAltitude >= 30 }
            .sorted { $0.maxAltitude > $1.maxAltitude }
            .prefix(5))
            .sorted { $0.rise < $1.rise }
    }

    @ViewBuilder
    private var weather: some View {
        if let w = model.spaceWeather {
            rows([
                ("Kp now", String(format: "%.1f%@", w.kpNow, SpaceWeather.gScale(w.kpNow).map { " (G\($0) storm)" } ?? "")),
                ("Next 24 h", w.kpNext24h.map { String(format: "up to Kp %.1f%@", $0, SpaceWeather.gScale($0).map { " (G\($0))" } ?? "") } ?? "–"),
                ("Updated", time(w.observedAt)),
            ])
        } else {
            Text("Loading").font(.footnote).dimmed(0.6)
        }
    }

    private func rows(_ items: [(String, String)]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            ForEach(items, id: \.0) { item in
                GridRow {
                    Text(item.0).dimmed(0.7)
                    Text(item.1).monospacedDigit()
                }
                .font(.subheadline)
            }
        }
    }

    private func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }

    private func compass(_ azimuth: Double) -> String {
        ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Int(((azimuth + 22.5) / 45).rounded(.down)) % 8]
    }
}

/// Bottom bar on the sky: time scrubber and a one-line summary that opens the Today sheet.
struct TodayBar: View {
    @Bindable var model: SkyModel
    var ink: Color
    var background: Color
    var onExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            scrubber
            Button(action: onExpand) {
                HStack {
                    Text(summary).font(.footnote).dimmed(0.8)
                    Spacer()
                    Image(systemName: "chevron.up").font(.caption.weight(.medium)).dimmed(0.6)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows tonight's details")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(background.opacity(0.92))
        .task {
            while !Task.isCancelled {
                await model.refreshSpaceWeather()
                try? await Task.sleep(for: .seconds(600))
            }
        }
    }

    private var summary: String {
        var parts: [String] = []
        if let t = model.tonight {
            parts.append("Moon \(Int((t.moonIllumination * 100).rounded()))%")
            let up = t.planets.filter { $0.best != nil }.map { $0.body.rawValue.capitalized }
            parts.append(up.isEmpty ? "No bright planets tonight" : up.joined(separator: ", "))
        }
        if let w = model.spaceWeather { parts.append(String(format: "Kp %.1f", w.kpNow)) }
        return parts.joined(separator: " · ")
    }

    private var scrubber: some View {
        HStack(spacing: 12) {
            Text(model.displayedDate.formatted(date: .omitted, time: .shortened))
                .font(.footnote.monospacedDigit())
                .fixedSize()
            Slider(value: $model.offsetHours, in: -12...12, step: 0.25).tint(ink)
            Button { model.offsetHours = 0 } label: {
                Text("Now").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }
            .font(.footnote.weight(.medium))
            .opacity(model.offsetHours == 0 ? 0.6 : 1)
        }
    }

}
