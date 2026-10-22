import Answers
import Feeds
import SkyEngine
import SwiftUI
import WidgetKit

/// Backend base URL from Info.plist (MOONRISE_API_URL build setting).
let widgetAPIBase: URL? = (Bundle.main.object(forInfoDictionaryKey: "MoonriseAPIURL") as? String)
    .flatMap { $0.isEmpty ? nil : URL(string: $0) }

/// The place the Sky tab last used (a fix or the city chosen in Settings), shared through the App Group.
func sharedPlace() -> Place? {
    Place.shared.flatMap(Place.saved)
}

/// Runs `work` and hands its result to a WidgetKit completion handler, which is not Sendable.
func deliver<T>(_ completion: @escaping (T) -> Void, _ work: @escaping @Sendable () async -> T) {
    nonisolated(unsafe) let completion = completion
    Task { completion(await work()) }
}

// MARK: - Kp

struct KpEntry: TimelineEntry {
    var date: Date
    var weather: SpaceWeather?
}

struct KpProvider: TimelineProvider {
    func placeholder(in context: Context) -> KpEntry {
        KpEntry(date: .now, weather: SpaceWeather(kpNow: 2.33, observedAt: .now, kpNext24h: 4))
    }

    func getSnapshot(in context: Context, completion: @escaping (KpEntry) -> Void) {
        if context.isPreview { return completion(placeholder(in: context)) }
        deliver(completion) { KpEntry(date: .now, weather: try? await SpaceWeather.fetch(base: widgetAPIBase)) }
    }

    /// The backend polls SWPC every 5 minutes; widgets refresh every 30, or 15 after a failure.
    func getTimeline(in context: Context, completion: @escaping (Timeline<KpEntry>) -> Void) {
        deliver(completion) {
            let weather = try? await SpaceWeather.fetch(base: widgetAPIBase)
            let next = Date.now.addingTimeInterval(weather == nil ? 15 * 60 : 30 * 60)
            return Timeline(entries: [KpEntry(date: .now, weather: weather)], policy: .after(next))
        }
    }
}

struct KpWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: KpEntry

    private func kp(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(1))) }

    var body: some View {
        if let w = entry.weather {
            switch family {
            case .accessoryCircular:
                Gauge(value: min(w.kpNow, 9), in: 0...9) { Text("Kp") } currentValueLabel: { Text(kp(w.kpNow)) }
                    .gaugeStyle(.accessoryCircular)
            case .accessoryInline:
                Text("Kp \(kp(w.kpNow))" + (w.kpNext24h.map { " · up to \(kp($0)) today" } ?? ""))
            default:
                VStack(alignment: .leading, spacing: 1) {
                    Text("KP INDEX").font(.system(size: 11, weight: .medium)).tracking(0.6).widgetAccentable()
                    Text("\(kp(w.kpNow)) now").font(.system(size: 17, weight: .medium)).monospacedDigit()
                    if let next = w.kpNext24h {
                        Text("Up to \(kp(next)) in 24 h" + (SpaceWeather.gScale(next).map { ", G\($0)" } ?? ""))
                            .font(.system(size: 13)).monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text(family == .accessoryCircular ? "Kp" : "Kp unavailable")
        }
    }
}

struct KpWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "kp", provider: KpProvider()) { entry in
            KpWidgetView(entry: entry).containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Kp index")
        .description("Geomagnetic activity now and the highest forecast in the next 24 hours. Data: NOAA SWPC.")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}

// MARK: - Next launch

struct LaunchEntry: TimelineEntry {
    var date: Date
    var launch: Launch?
}

struct NextLaunchProvider: TimelineProvider {
    func placeholder(in context: Context) -> LaunchEntry { LaunchEntry(date: .now, launch: nil) }

    func getSnapshot(in context: Context, completion: @escaping (LaunchEntry) -> Void) {
        deliver(completion) { LaunchEntry(date: .now, launch: await Self.next()) }
    }

    /// Hourly, and again 15 minutes after the launch so the next one replaces it.
    func getTimeline(in context: Context, completion: @escaping (Timeline<LaunchEntry>) -> Void) {
        deliver(completion) {
            let launch = await Self.next()
            var refresh = Date.now.addingTimeInterval(3600)
            if let net = launch?.net { refresh = min(refresh, net.addingTimeInterval(15 * 60)) }
            return Timeline(entries: [LaunchEntry(date: .now, launch: launch)], policy: .after(refresh))
        }
    }

    private static func next() async -> Launch? {
        guard let base = widgetAPIBase, let list = try? await LaunchFeed.fetch(base: base) else { return nil }
        return list.launches.first { $0.net > .now.addingTimeInterval(-15 * 60) }
    }
}

struct NextLaunchWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: LaunchEntry

    var body: some View {
        if let l = entry.launch {
            let soon = l.net.timeIntervalSince(entry.date) < 24 * 3600
            switch family {
            case .accessoryInline:
                if soon {
                    Text("\(l.rocket) \(Text(l.net, style: .relative))")
                } else {
                    Text("\(l.rocket) \(l.net.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                }
            default:
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.rocket).font(.system(size: 15, weight: .medium)).lineLimit(1).widgetAccentable()
                    Text(l.mission ?? l.name).font(.system(size: 13)).lineLimit(1)
                    if soon {
                        HStack(spacing: 2) {
                            Text(l.net > entry.date ? "T−" : "T+")
                            Text(l.net, style: .timer)
                        }
                        .font(.system(size: 13, weight: .medium)).monospacedDigit()
                    } else {
                        Text(l.net.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                            .font(.system(size: 13)).monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("No launch data")
        }
    }
}

struct NextLaunchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "next-launch", provider: NextLaunchProvider()) { entry in
            NextLaunchWidgetView(entry: entry).containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Next launch")
        .description("The next rocket launch with a countdown. Data: Launch Library 2.")
        .supportedFamilies([.accessoryInline, .accessoryRectangular])
    }
}
