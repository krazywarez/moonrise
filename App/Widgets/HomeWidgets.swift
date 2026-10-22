import Answers
import Feeds
import ImageIO
import SwiftUI
import UIKit
import WidgetKit

private let night = Color(red: 0.043, green: 0.078, blue: 0.141)
private let paper = Color(red: 0.95, green: 0.95, blue: 0.93)

// MARK: - Voyager 1

struct VoyagerEntry: TimelineEntry {
    var date: Date
    var answer: ProbeAnswer?
}

/// Worked out on the device from the bundled trajectory, so no network. Hourly entries for a day.
struct VoyagerProvider: TimelineProvider {
    func placeholder(in context: Context) -> VoyagerEntry { entry(at: .now) }

    func getSnapshot(in context: Context, completion: @escaping (VoyagerEntry) -> Void) {
        completion(entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VoyagerEntry>) -> Void) {
        completion(Timeline(entries: (0..<24).map { entry(at: .now.addingTimeInterval(Double($0) * 3600)) }, policy: .atEnd))
    }

    func entry(at date: Date) -> VoyagerEntry {
        engineLock.lock()
        defer { engineLock.unlock() }
        return VoyagerEntry(date: date, answer: try? ProbeAnswer(probe: .voyager1, at: date))
    }
}

struct VoyagerWidgetView: View {
    var entry: VoyagerEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("VOYAGER 1").font(.system(size: 11, weight: .medium)).tracking(0.6).opacity(0.7)
            Spacer(minLength: 0)
            if let a = entry.answer {
                Text((a.fromEarthKm / 1e9).formatted(.number.precision(.fractionLength(2))))
                    .font(.system(size: 30, weight: .medium)).monospacedDigit()
                Text("billion km from Earth").font(.system(size: 11)).opacity(0.8)
                Text("Light time \(Duration.seconds(a.lightTime).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))")
                    .font(.system(size: 11)).monospacedDigit().opacity(0.7)
            } else {
                Text("No trajectory data").font(.system(size: 13))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(paper)
    }
}

struct VoyagerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "voyager1", provider: VoyagerProvider()) { entry in
            VoyagerWidgetView(entry: entry).containerBackground(night, for: .widget)
        }
        .configurationDisplayName("Voyager 1")
        .description("How far Voyager 1 is from Earth, and how long its signal takes. Trajectory: JPL Horizons.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Sun

struct SunEntry: TimelineEntry {
    var date: Date
    var image: UIImage?
    /// When the frame was taken, for a frame older than SDO's latest.
    var frameTime: Date?
}

/// SDO's latest 171 Å frame, hourly; when it is black or partly covered, the newest usable frame from the archive.
struct SunProvider: TimelineProvider {
    func placeholder(in context: Context) -> SunEntry { SunEntry(date: .now, image: nil) }

    func getSnapshot(in context: Context, completion: @escaping (SunEntry) -> Void) {
        if context.isPreview { return completion(placeholder(in: context)) }
        deliver(completion) { await Self.load() }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SunEntry>) -> Void) {
        deliver(completion) {
            let entry = await Self.load()
            return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(entry.image == nil ? 15 * 60 : 3600)))
        }
    }

    static func load() async -> SunEntry {
        let w = SolarImage.corona
        if let (data, _) = try? await URLSession.shared.data(from: w.url(size: 512)), w.isUsable(data), let image = thumbnail(data) {
            return SunEntry(date: .now, image: image)
        }
        if let frame = await w.lastUsableFrame(), let image = thumbnail(frame.data) {
            return SunEntry(date: .now, image: image, frameTime: frame.time)
        }
        return SunEntry(date: .now, image: nil)
    }

    /// Decoded at 400 px, within a widget's memory limit whatever size the frame is.
    static func thumbnail(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 400,
              ] as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct SunWidgetView: View {
    var entry: SunEntry

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image = entry.image {
                Image(uiImage: image).resizable().scaledToFill()
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("SUN · 171 Å").font(.system(size: 11, weight: .medium)).tracking(0.6)
                Text(entry.frameTime.map { "Frame \($0.formatted(date: .omitted, time: .shortened))" } ?? (entry.image == nil ? "No image" : "NASA/SDO"))
                    .font(.system(size: 9)).opacity(0.8)
            }
            .foregroundStyle(paper)
            .shadow(color: .black, radius: 2)
            .padding(10)
        }
    }
}

struct SunWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "sun", provider: SunProvider()) { entry in
            SunWidgetView(entry: entry).containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Sun today")
        .description("The Sun's corona from NASA's Solar Dynamics Observatory, updated hourly. Courtesy of NASA/SDO and the AIA, EVE, and HMI science teams.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}
