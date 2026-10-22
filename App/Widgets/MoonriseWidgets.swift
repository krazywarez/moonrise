import CoreLocation
import SkyEngine
import SkyRenderer
import SwiftUI
import WidgetKit

@main
struct MoonriseWidgets: WidgetBundle {
    var body: some Widget {
        MoonWidget()
        PlanetsWidget()
        #if os(iOS)
        KpWidget()
        NextLaunchWidget()
        VoyagerWidget()
        SunWidget()
        SkyControl()
        SunControl()
        LaunchesControl()
        LaunchLiveActivity()
        EventLiveActivity()
        EclipseLiveActivity()
        PassLiveActivity()
        #endif
    }
}

/// The Sky tab's place (iPhone, through the App Group), else the last known location, else Chicago.
/// The widget does not request a fresh fix.
func widgetObserver() -> (Observer, Bool) {
    #if os(iOS)
    if let p = sharedPlace(), p.kind != .fallback { return (p.observer, true) }
    #endif
    if let c = CLLocationManager().location?.coordinate {
        return (Observer(latitude: c.latitude, longitude: c.longitude), true)
    }
    return (Observer(latitude: 41.8781, longitude: -87.6298), false)
}

/// Astronomy Engine is not thread-safe and WidgetKit may build timelines concurrently.
let engineLock = NSLock()

/// Hourly entries for the next 12 hours.
func hourly(from date: Date) -> [Date] {
    (0..<12).map { date.addingTimeInterval(Double($0) * 3600) }
}

// MARK: - Moon

struct MoonEntry: TimelineEntry {
    var date: Date
    var illumination: Double
    var waxing: Bool
    var nextQuarter: (SkyEngine.MoonQuarter, Date)?
}

struct MoonProvider: TimelineProvider {
    func placeholder(in context: Context) -> MoonEntry {
        MoonEntry(date: .now, illumination: 0.44, waxing: true, nextQuarter: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (MoonEntry) -> Void) {
        completion(entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MoonEntry>) -> Void) {
        completion(Timeline(entries: hourly(from: .now).map(entry), policy: .atEnd))
    }

    func entry(at date: Date) -> MoonEntry {
        engineLock.lock()
        defer { engineLock.unlock() }
        let illumination = (try? SkyEngine.illumination(.moon, at: date).phaseFraction) ?? 0
        let phase = (try? SkyEngine.moonPhase(at: date)) ?? 0
        let q = try? SkyEngine.nextMoonQuarter(after: date)
        return MoonEntry(date: date, illumination: illumination, waxing: phase < 180, nextQuarter: q.map { ($0.quarter, $0.date) })
    }
}

func quarterName(_ q: SkyEngine.MoonQuarter) -> String {
    switch q {
    case .new: "New moon"
    case .firstQuarter: "First quarter"
    case .full: "Full moon"
    case .lastQuarter: "Last quarter"
    }
}

struct MoonWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: MoonEntry

    var percent: String { "\(Int((entry.illumination * 100).rounded()))%" }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                MoonDisc(fraction: entry.illumination, waxing: entry.waxing, light: .white, dark: .white.opacity(0.15))
                    .padding(6)
            }
        case .accessoryInline:
            Text("Moon \(percent) \(entry.waxing ? "waxing" : "waning")")
        #if os(watchOS)
        case .accessoryCorner:
            MoonDisc(fraction: entry.illumination, waxing: entry.waxing, light: .white, dark: .white.opacity(0.15))
                .padding(4)
                .widgetLabel(percent)
        #endif
        default:
            VStack(alignment: .leading, spacing: 6) {
                MoonDisc(fraction: entry.illumination, waxing: entry.waxing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 64)
                Spacer(minLength: 0)
                Text("Moon \(percent)").font(.system(size: 15, weight: .medium))
                if let (q, d) = entry.nextQuarter {
                    Text("\(quarterName(q)) \(d.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                        .font(.system(size: 11)).opacity(0.7)
                }
            }
            .foregroundStyle(Color(red: 0.95, green: 0.95, blue: 0.93))
        }
    }
}

struct MoonWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "moon", provider: MoonProvider()) { entry in
            MoonWidgetView(entry: entry)
                .containerBackground(Color(red: 0.043, green: 0.078, blue: 0.141), for: .widget)
        }
        .configurationDisplayName("Moon")
        .description("Tonight's moon phase.")
        #if os(watchOS)
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryCorner])
        #else
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
        #endif
    }
}

// MARK: - Planets

struct PlanetsEntry: TimelineEntry {
    struct Row: Hashable {
        var name: String
        var detail: String
    }

    var date: Date
    var rows: [Row]
    var located: Bool
}

struct PlanetsProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlanetsEntry {
        PlanetsEntry(date: .now, rows: [.init(name: "Saturn", detail: "up now, 30° SE")], located: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (PlanetsEntry) -> Void) {
        completion(entries(at: [.now])[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlanetsEntry>) -> Void) {
        completion(Timeline(entries: entries(at: hourly(from: .now)), policy: .atEnd))
    }

    func entries(at dates: [Date]) -> [PlanetsEntry] {
        let (observer, located) = widgetObserver()
        engineLock.lock()
        defer { engineLock.unlock() }
        guard let nights = try? Tonight.visiblePlanets(at: dates, from: observer) else {
            return dates.map { PlanetsEntry(date: $0, rows: [], located: located) }
        }
        let time: (Date) -> String = { $0.formatted(date: .omitted, time: .shortened) }
        return zip(dates, nights).map { date, night in
            let rows = night.planets.map { p -> PlanetsEntry.Row in
                let name = p.body.rawValue.capitalized
                if p.now.altitude > 0 { return .init(name: name, detail: String(format: "up, %.0f°", p.now.altitude)) }
                if let rise = p.rise, rise < night.end { return .init(name: name, detail: "rises \(time(rise))") }
                return .init(name: name, detail: "tonight")
            }
            return PlanetsEntry(date: date, rows: rows, located: located)
        }
    }
}

struct PlanetsWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: PlanetsEntry

    var body: some View {
        if family == .accessoryRectangular { compact } else { full }
    }

    /// Watch complication and Lock Screen: up to three planets, no header.
    private var compact: some View {
        VStack(alignment: .leading, spacing: 1) {
            if entry.rows.isEmpty { Text("No planets tonight").font(.system(size: 13)) }
            ForEach(entry.rows.prefix(3), id: \.self) { row in
                HStack {
                    Text(row.name).font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(row.detail).font(.system(size: 12).monospacedDigit())
                }
            }
        }
    }

    private var full: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Planets tonight").font(.system(size: 11, weight: .medium)).textCase(.uppercase).opacity(0.6)
            if entry.rows.isEmpty {
                Text("None well placed").font(.system(size: 13))
            }
            ForEach(entry.rows, id: \.self) { row in
                HStack {
                    Text(row.name).font(.system(size: 14, weight: .medium))
                    Spacer()
                    Text(row.detail).font(.system(size: 12).monospacedDigit()).opacity(0.75)
                }
            }
            Spacer(minLength: 0)
            if !entry.located {
                Text("Open Moonrise to set location").font(.system(size: 11)).opacity(0.7)
            }
        }
        .foregroundStyle(Color(red: 0.95, green: 0.95, blue: 0.93))
    }
}

struct PlanetsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "planets", provider: PlanetsProvider()) { entry in
            PlanetsWidgetView(entry: entry)
                .containerBackground(Color(red: 0.043, green: 0.078, blue: 0.141), for: .widget)
        }
        .configurationDisplayName("Planets tonight")
        .description("Which planets are up tonight and when they rise.")
        #if os(watchOS)
        .supportedFamilies([.accessoryRectangular])
        #else
        .supportedFamilies([.systemSmall, .systemMedium])
        #endif
    }
}
