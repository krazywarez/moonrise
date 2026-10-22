import SkyEngine
import SwiftUI
import WatchKit

/// A total or annular eclipse at the Watch's position within two weeks, and its second and third contacts.
struct WatchEclipse: Sendable, Equatable {
    var kind: String
    var c2: Date
    var c3: Date

    static func next(from date: Date, observer: Observer) -> WatchEclipse? {
        let events = SkyEngine.events(from: date, days: 14, observer: observer)
        for e in events where e.kind == .solarEclipse && e.visibleHere == true {
            if let l = LocalEclipse.at(observer, near: e.date), let c2 = l.centralBegin, let c3 = l.centralEnd, c3 > date {
                return WatchEclipse(kind: l.kind, c2: c2, c3: c3)
            }
        }
        return nil
    }
}

/// Taps the wrist at second and third contact. A smart alarm session may start in the background at a set time
/// (within 36 hours) and run for 30 minutes, so it is scheduled a minute before second contact.
@MainActor
@Observable
final class EclipseHaptics: NSObject, WKExtendedRuntimeSessionDelegate {
    private(set) var armed: Date?
    private var session: WKExtendedRuntimeSession?
    private var eclipse: WatchEclipse?

    func arm(_ e: WatchEclipse) {
        session?.invalidate()
        eclipse = e
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start(at: max(.now.addingTimeInterval(5), e.c2.addingTimeInterval(-60)))
        session = s
        armed = e.c2
    }

    func disarm() {
        session?.invalidate()
        session = nil
        armed = nil
    }

    nonisolated func extendedRuntimeSessionDidStart(_ started: WKExtendedRuntimeSession) {
        let id = ObjectIdentifier(started)
        Task { @MainActor in
            guard let e = eclipse, let s = session, ObjectIdentifier(s) == id else { return }
            for contact in [e.c2, e.c3] where contact > .now {
                try? await Task.sleep(for: .seconds(contact.timeIntervalSinceNow))
                s.notifyUser(hapticType: .notification) { _ in 0 }
            }
            s.invalidate()
        }
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ s: WKExtendedRuntimeSession) {}

    nonisolated func extendedRuntimeSession(_ ended: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        let id = ObjectIdentifier(ended)
        Task { @MainActor in
            if session.map({ ObjectIdentifier($0) == id }) == true { session = nil; armed = nil }
        }
    }
}

/// Contact times and the switch for the wrist taps.
struct EclipseSection: View {
    var eclipse: WatchEclipse
    @Bindable var haptics: EclipseHaptics

    var body: some View {
        let central = eclipse.kind == "Total" ? "Totality" : "Annularity"
        VStack(alignment: .leading, spacing: 4) {
            Text("\(eclipse.kind) eclipse").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
            row("\(central) begins", eclipse.c2)
            row("\(central) ends", eclipse.c3)
            if haptics.armed == eclipse.c2 {
                Button("Stop wrist taps") { haptics.disarm() }
                Text("Taps at both contacts, with the app closed.").font(.caption2).foregroundStyle(.secondary)
            } else {
                Button("Tap at both contacts") { haptics.arm(eclipse) }
                Text("Times are for the Watch's position. Taps only: follow your glasses' guidance.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ label: String, _ d: Date) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(d.formatted(date: .omitted, time: .standard)).monospacedDigit().foregroundStyle(.secondary)
        }
        .font(.footnote)
    }
}
