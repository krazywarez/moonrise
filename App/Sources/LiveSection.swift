import ActivityKit
import Feeds
import SkyEngine
import SwiftUI

/// A mission being covered live: where it is between Earth and the Moon, its phase, and a Lock Screen follow.
/// Shown only while the backend reports an event. In debug builds, the user default "liveReplayAt"
/// (ISO 8601) replays a past event at that moment.
struct LiveSection: View {
    var ink: Color
    var accent: Color
    @State private var coverage: LiveCoverage?
    @State private var following = false

    private var replayAt: Date? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "liveReplayAt").flatMap { try? Date($0, strategy: .iso8601) }
        #else
        nil
        #endif
    }

    var body: some View {
        // A VStack rather than a Group: an empty Group has no view for .task to attach to.
        VStack(alignment: .leading, spacing: 0) {
            if let c = coverage {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(replayAt == nil ? "LIVE" : "REPLAY").font(.caption2.weight(.bold)).tracking(0.8)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(accent, in: RoundedRectangle(cornerRadius: 3))
                        Text(c.event.title).font(.title3.weight(.medium))
                    }
                    EarthMoonMap(coverage: c, ink: ink, accent: accent)
                        .aspectRatio(1, contentMode: .fit)
                        .accessibilityLabel("Map of \(c.event.title) between Earth and the Moon")
                    facts(c)
                    if replayAt == nil {
                        Button(following ? "Following on the Lock Screen" : "Follow on the Lock Screen") { follow(c) }
                            .disabled(following)
                            .font(.subheadline.weight(.medium))
                    }
                    Text("Trajectory: NASA/JPL Horizons, every 30 minutes.").font(.caption2).dimmed(0.5)
                }
                .padding(.bottom, 24)
            }
        }
        .task {
            while !Task.isCancelled {
                if let apiBase {
                    do {
                        let c = try await LiveCoverage.fetch(base: apiBase, at: replayAt)
                        if let c {
                            coverage = c
                            await update(c)
                        }
                    } catch {
                        log.error("live: \(error.localizedDescription, privacy: .public)")
                    }
                }
                try? await Task.sleep(for: .seconds(600))
            }
        }
    }

    private func facts(_ c: LiveCoverage) -> some View {
        let moon = SkyEngine.geocentricMoonEcliptic(at: c.at)
        let fromMoon = c.points.last.map { p in ((p.position - moon) * (p.position - moon)).sum().squareRoot() }
        let elapsed = c.at.timeIntervalSince(c.event.launch)
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow { Text("Mission time").dimmed(0.7); Text("\(Int(elapsed) / 86_400) d \(Int(elapsed) % 86_400 / 3600) h \(Int(elapsed) % 3600 / 60) m") }
            if let p = c.phase.current { GridRow { Text("Phase").dimmed(0.7); Text(p.label) } }
            if let n = c.phase.next { GridRow { Text("Next").dimmed(0.7); Text("\(n.label), \(n.at.formatted(date: .abbreviated, time: .shortened))") } }
            if let d = c.distanceKm { GridRow { Text("From Earth's centre").dimmed(0.7); Text("\(Int(d).formatted()) km") } }
            if let d = fromMoon { GridRow { Text("From the Moon's centre").dimmed(0.7); Text("\(Int(d).formatted()) km") } }
        }
        .font(.subheadline.monospacedDigit())
    }

    private func state(_ c: LiveCoverage) -> EventActivityAttributes.ContentState {
        EventActivityAttributes.ContentState(phase: c.phase.current?.label ?? "", next: c.phase.next?.label, nextAt: c.phase.next?.at, distanceKm: c.distanceKm ?? 0)
    }

    private func follow(_ c: LiveCoverage) {
        let attributes = EventActivityAttributes(eventID: c.event.id, title: c.event.title, launch: c.event.launch)
        _ = try? Activity.request(attributes: attributes, content: .init(state: state(c), staleDate: .now.addingTimeInterval(1800)))
        following = true
    }

    /// Updates a followed activity while the app runs; ends it after the event.
    private func update(_ c: LiveCoverage) async {
        for a in Activity<EventActivityAttributes>.activities where a.attributes.eventID == c.event.id {
            following = true
            if c.at > c.event.end {
                await a.end(nil, dismissalPolicy: .default)
            } else {
                await a.update(.init(state: state(c), staleDate: .now.addingTimeInterval(1800)))
            }
        }
    }
}

/// Earth at the centre, the Moon's orbit and position, and the trajectory so far, on the ecliptic plane.
struct EarthMoonMap: View {
    var coverage: LiveCoverage
    var ink: Color
    var accent: Color

    var body: some View {
        Canvas { context, size in
            let moon = SkyEngine.geocentricMoonEcliptic(at: coverage.at)
            let moonDistance = (moon * moon).sum().squareRoot()
            let farthest = coverage.points.map { ($0.position * $0.position).sum().squareRoot() }.max() ?? 0
            let scale = min(size.width, size.height) / 2 / (max(farthest, moonDistance) * 1.08)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            func pt(_ v: SIMD3<Double>) -> CGPoint { CGPoint(x: c.x + v.x * scale, y: c.y - v.y * scale) }

            let r = moonDistance * scale
            context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(ink.opacity(0.2)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
            context.fill(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)), with: .color(Color(red: 0.35, green: 0.6, blue: 0.95)))
            context.draw(Text("Earth").font(.caption2).foregroundStyle(ink.opacity(0.7)), at: CGPoint(x: c.x, y: c.y + 14))

            let m = pt(moon)
            context.fill(Path(ellipseIn: CGRect(x: m.x - 4, y: m.y - 4, width: 8, height: 8)), with: .color(ink))
            context.draw(Text("Moon").font(.caption2).foregroundStyle(ink.opacity(0.7)), at: CGPoint(x: m.x, y: m.y + 13))

            if let first = coverage.points.first, let last = coverage.points.last {
                var path = Path()
                path.move(to: pt(first.position))
                for p in coverage.points.dropFirst() { path.addLine(to: pt(p.position)) }
                context.stroke(path, with: .color(accent.opacity(0.8)), lineWidth: 1.2)
                let q = pt(last.position)
                context.fill(Path(ellipseIn: CGRect(x: q.x - 4, y: q.y - 4, width: 8, height: 8)), with: .color(accent))
                context.draw(Text(coverage.event.title).font(.caption2).foregroundStyle(accent), at: CGPoint(x: q.x + 7, y: q.y), anchor: .leading)
            }
        }
    }
}
