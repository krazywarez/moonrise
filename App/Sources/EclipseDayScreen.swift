import AVFoundation
import CoreHaptics
import SkyEngine
import SwiftUI

/// Eclipse-day countdown: next contact, the cue script spoken with haptics, and the Sun's position.
/// Runs in the foreground with the screen kept awake. Rehearsal runs the same code on a clock set
/// to three minutes before totality.
struct EclipseDayScreen: View {
    var date: Date
    var observer: Observer
    var placeName: String
    var zone: TimeZone?
    var rehearsal: Bool
    var location: EclipseLocation
    @State private var timeline: EclipseTimeline?
    /// Added to the real clock; set once in rehearsal.
    @State private var shift: TimeInterval?
    @State private var player = CuePlayer()
    @State private var spoken: EclipseTimeline.Cue?
    @AppStorage(SettingsKey.locationMode) private var locationMode = "current"
    @AppStorage(SettingsKey.eclipsePhotographer) private var photographer = false
    @Environment(\.dismiss) private var dismiss

    private let ink = Color(red: 0.95, green: 0.95, blue: 0.93)
    private let accent = Color(red: 0.88, green: 0.24, blue: 0.19)

    private var fix: EclipseLocation.Fix? { locationMode == "city" ? nil : location.fix }
    private var site: Observer { fix?.observer ?? observer }

    private func now() -> Date { Date.now.addingTimeInterval(shift ?? 0) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let timeline {
                        if rehearsal {
                            Text("Rehearsal. The clock is running from three minutes before \(timeline.eclipse.kind == "Total" ? "totality" : "maximum").")
                                .font(.footnote.weight(.medium)).foregroundStyle(accent)
                        }
                        TimelineView(.periodic(from: .now, by: 0.1)) { _ in countdown(timeline, at: now()) }
                        contacts(timeline)
                        SunDiagram(timeline: timeline, ink: ink, accent: accent)
                        status(timeline)
                    } else {
                        ProgressView().tint(ink).frame(maxWidth: .infinity, minHeight: 200)
                    }
                    safety
                }
                .padding(20)
                .readableWidth()
            }
            .background(Color.black.ignoresSafeArea())
            .foregroundStyle(ink)
            .navigationTitle(rehearsal ? "Rehearsal" : "Eclipse day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task(id: [site.latitude, site.longitude, site.height, (fix?.accuracy ?? .infinity) < EclipseTimeline.maximumAccuracy ? 1 : 0, photographer ? 1 : 0]) {
            let date = date, site = site, accuracy = fix?.accuracy, photographer = photographer
            let t = await Task.detached {
                LocalEclipse.at(site, near: date).flatMap { try? EclipseTimeline($0, observer: site, accuracy: accuracy, photographer: photographer) }
            }.value
            timeline = t
            if rehearsal, shift == nil, let t { shift = t.rehearsalStart.timeIntervalSinceNow }
        }
        .task {
            // Plays each cue once, within 50 ms of its time; cues more than 2 s late (the app was away) are skipped.
            var last = now()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                let t = now()
                for cue in timeline?.cues ?? [] where cue.date > last && cue.date <= t && t.timeIntervalSince(cue.date) < 2 {
                    player.play(cue)
                    spoken = cue
                }
                last = t
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            if locationMode != "city" { location.start() }
            player.start()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            if locationMode != "city" { location.stop() }
            player.stop()
        }
    }

    private func countdown(_ t: EclipseTimeline, at now: Date) -> some View {
        let next = t.contacts.first { $0.date > now }
        let inTotality = t.eclipse.centralBegin.map { $0 <= now } == true && t.eclipse.centralEnd.map { now < $0 } == true
        return VStack(alignment: .leading, spacing: 8) {
            Text(next.map { label($0.name, t) } ?? "The eclipse is over").font(.caption2.weight(.medium)).textCase(.uppercase).tracking(0.8).dimmed(0.7)
            if let next {
                Text(clock(next.date.timeIntervalSince(now)))
                    .font(.system(size: 64, weight: .medium).monospacedDigit())
                    .foregroundStyle(inTotality ? accent : ink)
                    .contentTransition(.numericText())
            }
            if let cue = spoken, now.timeIntervalSince(cue.date) < 20 {
                Text(cue.text).font(.title3.weight(.medium)).foregroundStyle(cue.warning ? accent : ink)
            }
            let upcoming = t.cues.filter { $0.date > now && Int($0.text) == nil }.prefix(3)
            if !upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(upcoming, id: \.date) { c in
                        HStack(alignment: .firstTextBaseline) {
                            Text("in \(clock(c.date.timeIntervalSince(now)))").monospacedDigit().dimmed(0.6).frame(width: 90, alignment: .leading)
                            Text(c.text).foregroundStyle(c.warning ? accent : ink).lineLimit(2)
                        }
                    }
                }
                .font(.footnote)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func label(_ contact: String, _ t: EclipseTimeline) -> String {
        let central = t.eclipse.kind == "Total" ? "Totality" : "Annularity"
        switch contact {
        case "C1": return "First contact in"
        case "C2": return "\(central) in"
        case "Max": return "Maximum in"
        case "C3": return "\(central) ends in"
        default: return "Last contact in"
        }
    }

    private func contacts(_ t: EclipseTimeline) -> some View {
        let zones = [zone, .gmt].compactMap { $0 }
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                Text("")
                if let zone { Text("Local, \(utcOffset(zone, at: t.eclipse.peak))").dimmed(0.6) }
                Text("UTC").dimmed(0.6)
            }
            .font(.caption)
            ForEach(t.contacts, id: \.name) { c in
                GridRow {
                    Text(c.name).dimmed(0.7)
                    ForEach(zones, id: \.self) { z in
                        // A string: Text(_:format:) would replace the style's time zone with the environment's.
                        Text(Date(timeIntervalSinceReferenceDate: c.date.timeIntervalSinceReferenceDate.rounded()).formatted(Date.FormatStyle(date: .omitted, time: .standard, timeZone: z)))
                    }
                }
            }
        }
        .font(.subheadline.monospacedDigit())
    }

    private func status(_ t: EclipseTimeline) -> some View {
        let position = fix.map { "Position from GPS, ±\(Int($0.accuracy.rounded())) m." } ?? "Position: \(placeName), not a GPS fix."
        let off: String = switch t.glassesOffWithheld {
        case nil: "The totality cue says glasses off only once no sunlight shows through them."
        case .partial: "No totality here: keep your glasses on the whole time."
        case .short: "Totality here is under \(Int(EclipseTimeline.minimumTotality)) s, so there is no glasses-off cue."
        case .imprecise: locationMode == "city"
            ? "There is no glasses-off cue for a chosen city. Choose Current location in Settings for one."
            : "There is no glasses-off cue until the GPS fix is better than \(Int(EclipseTimeline.maximumAccuracy)) m."
        case .sunDown: "The Sun is below the horizon at totality here."
        }
        return VStack(alignment: .leading, spacing: 6) {
            Text(position)
            Text(off)
            Text("Times are good to about 2 s inside the path and less near its edges, where valleys on the Moon's limb shift the contacts.")
                .dimmed(0.7)
        }
        .font(.footnote)
    }

    private var safety: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Safety").font(.caption2.weight(.medium)).textCase(.uppercase).tracking(0.8).dimmed(0.6)
            ForEach(eclipseSafetyLines, id: \.self) { Text($0) }
            Text("Do not drive during totality. Keep the phone in the shade: in direct sun it can overheat and shut down.")
        }
        .font(.footnote)
        .foregroundStyle(accent)
    }

    /// "4:39" or "1:02:15", rounded up to the second.
    private func clock(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds).rounded(.up))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Speaks cues and plays their haptics. The audio session uses the playback category so speech
/// sounds with the ring switch on silent.
@MainActor
final class CuePlayer {
    private let speech = AVSpeechSynthesizer()
    private var haptics: CHHapticEngine?

    func start() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        haptics = try? CHHapticEngine()
    }

    func stop() {
        speech.stopSpeaking(at: .immediate)
        haptics?.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func play(_ cue: EclipseTimeline.Cue) {
        speech.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: cue.text)
        u.voice = AVSpeechSynthesisVoice(language: "en-US")
        speech.speak(u)

        let events: [CHHapticEvent] = switch cue.haptic {
        case .tap: [tap(at: 0)]
        case .double: [tap(at: 0), tap(at: 0.15)]
        case .long: [CHHapticEvent(eventType: .hapticContinuous, parameters: [.init(parameterID: .hapticIntensity, value: 1)], relativeTime: 0, duration: 0.8)]
        }
        guard let haptics, let pattern = try? CHHapticPattern(events: events, parameters: []) else { return }
        try? haptics.start()
        try? haptics.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
    }

    private func tap(at time: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [.init(parameterID: .hapticIntensity, value: 0.8)], relativeTime: time)
    }
}
