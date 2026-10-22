import Library
import ObservingLog
import SkyEngine
import SkyRenderer
import SwiftUI

struct SkyScreen: View {
    @State private var model = SkyModel.shared
    @State private var pointer = MotionPointer()
    @State private var azimuth = 180.0
    @State private var altitude = 45.0
    @State private var fieldOfView = 100.0
    @AppStorage(SettingsKey.nightMode) private var nightMode = "auto"
    @AppStorage(SettingsKey.skyCulture) private var skyCulture = "western"
    @AppStorage(SettingsKey.showDeepSky) private var showDeepSky = true
    @AppStorage(SettingsKey.showMilkyWay) private var showMilkyWay = true
    @State private var showSettings = false
    @State private var showEvents = false
    @State private var showLog = false
    @State private var logEntry: Observation?
    @AppStorage(SettingsKey.onboarded) private var onboarded = false
    @AppStorage(SettingsKey.nightActive) private var nightActive = false
    @State private var showToday = false
    @State private var showYear = false
    @State private var showTours = false
    @State private var tour: Tour?
    @State private var tourStep = 0
    @State private var turning: Task<Void, Never>?
    @State private var router = Router.shared
    /// Object asked for from Siri or Shortcuts, highlighted until the view is dragged.
    @State private var shown: Tour.Target?
    @Environment(\.scenePhase) private var scenePhase
    @State private var libraryPage: LibraryPage?
    @State private var selection: SkyObject?
    @State private var details: BodyDetails?
    @GestureState private var drag: CGSize = .zero
    @GestureState private var zoom: CGFloat = 1
    private let stats = DrawStats()

    private var night: Bool { nightMode == "on" || (nightMode == "auto" && model.sunAltitude < -12) }
    private var style: SkyStyle { night ? .night : SkyStyle() }
    private var ink: Color { night ? SkyStyle.nightRed : Color(red: 0.95, green: 0.95, blue: 0.93) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                style.background.ignoresSafeArea()
                if let scene = model.scene {
                    let view = current(width: geo.size.width)
                    SkyView(scene: scene, centerAzimuth: view.azimuth, centerAltitude: view.altitude, fieldOfView: view.fieldOfView, style: style, culture: Catalog.skyCultures.first { $0.id == skyCulture }, highlight: (tour.map { $0.steps[tourStep].target } ?? shown).flatMap(highlight), showDeepSky: showDeepSky, showMilkyWay: showMilkyWay) { [stats] d in
                        stats.record(d)
                    }
                    .ignoresSafeArea()
                    .gesture(panGesture(width: geo.size.width).simultaneously(with: zoomGesture))
                    .onTapGesture(coordinateSpace: .local) { location in
                        let p = Projection(centerAzimuth: view.azimuth, centerAltitude: view.altitude, fieldOfView: view.fieldOfView, size: geo.size)
                        select(scene.object(at: location, projection: p, deepSky: showDeepSky))
                    }
                    .accessibilityElement()
                    .accessibilityLabel(skyDescription(scene, azimuth: view.azimuth))
                    .accessibilityHint("Swipe up or down to turn. Planets and the Moon are listed in the Tonight summary.")
                    .accessibilityAdjustableAction { direction in
                        azimuth = (azimuth + (direction == .increment ? 45 : -45) + 360).truncatingRemainder(dividingBy: 360)
                    }
                }
                VStack(spacing: 0) {
                    header
                    if pointer.active {
                        Button { pointer.stop() } label: {
                            Label("Following your phone · Stop", systemImage: "iphone.gen3.radiowaves.left.and.right")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .glassEffect(in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                    if let selection { card(for: selection).padding(.horizontal, 16).padding(.top, 8) }
                    Spacer()
                    if let tour {
                        TourCard(tour: tour, step: $tourStep, belowHorizon: (tourTarget(tour.steps[tourStep].target)?.altitude ?? 0) < 0,
                                 ink: ink, background: style.ground, onOpen: { libraryPage = $0 }, onEnd: { self.tour = nil })
                    } else if model.historicalYear == nil {
                        TodayBar(model: model, ink: ink, background: style.ground) { showToday = true }
                    }
                }
            }
        }
        .foregroundStyle(ink)
        .environment(\.nightMode, night)
        .sheet(isPresented: $showLog) {
            LogScreen { newObservation("") }.preferredColorScheme(.dark).tint(.blue)
        }
        .sheet(item: $logEntry) { o in
            ObservationEditor(observation: o).preferredColorScheme(.dark).tint(.blue)
        }
        .sheet(isPresented: $showEvents) {
            EventsScreen(observer: model.observer, placeName: model.placeName, forecast: model.forecast)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showTours) {
            TourPicker(tonight: model.tonight) { tour = $0; tourStep = 0; aim(at: $0.steps[0].target) }.preferredColorScheme(.dark)
        }
        .onChange(of: tourStep) { if let tour { aim(at: tour.steps[tourStep].target) } }
        .sheet(isPresented: $showYear) {
            YearSheet(year: $model.historicalYear, south: model.observer.latitude < 0).preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showSettings, onDismiss: rescheduleNotifications) {
            SettingsScreen { model.applyLocationSettings() }
                .preferredColorScheme(.dark)
                .tint(.blue)
        }
        .sheet(item: $libraryPage) { page in
            NavigationStack { LibraryPageView(page: page) }
        }
        .sheet(isPresented: $showToday) {
            TodaySheet(model: model, ink: ink, background: style.ground)
                .environment(\.nightMode, night)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: model.offsetHours) { select(selection) }
        .onChange(of: router.skyTarget, initial: true) { showRequestedTarget() }
        .onChange(of: model.scene == nil) { showRequestedTarget() }
        .onChange(of: onboarded) { if onboarded { model.start() } }
        .onChange(of: night, initial: true) { nightActive = night }
        .onChange(of: model.observer) { rescheduleNotifications() }
        .onChange(of: scenePhase) { if scenePhase == .active { rescheduleNotifications() } }
        .task {
            if onboarded { model.start() }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                model.refresh()
            }
        }
    }

    /// Where a tour target is in the current scene; constellations use the mean direction of their stars.
    private func tourTarget(_ t: Tour.Target) -> Horizontal? {
        guard let scene = model.scene else { return nil }
        if let hr = t.hr { return scene.starsByHR[hr] }
        if let b = t.body { return scene.bodies.first { $0.body.rawValue == b }?.position }
        guard let c = t.constellation, let figure = Catalog.constellations.first(where: { $0.id == c }) else { return nil }
        let positions = Set(figure.lines.joined()).compactMap { scene.starsByHR[$0] }
        guard !positions.isEmpty else { return nil }
        var v = SIMD3<Double>.zero
        for h in positions {
            let alt = h.altitude * .pi / 180, az = h.azimuth * .pi / 180
            v += SIMD3(cos(alt) * sin(az), cos(alt) * cos(az), sin(alt))
        }
        var az = atan2(v.x, v.y) * 180 / .pi
        if az < 0 { az += 360 }
        return Horizontal(altitude: asin(v.z / (v * v).sum().squareRoot()) * 180 / .pi, azimuth: az)
    }

    private func highlight(_ t: Tour.Target) -> SkyHighlight? {
        if let c = t.constellation { return .constellation(c) }
        if let hr = t.hr { return .star(hr) }
        if let b = t.body.flatMap(SkyBody.init(rawValue:)) { return .body(b) }
        return nil
    }

    /// Pans the view to a tour target over a second, the short way round, keeping it at least
    /// 10° up so the horizon stays in view. The Canvas redraws each frame, so the turn is stepped by hand.
    private func aim(at t: Tour.Target) {
        guard let h = tourTarget(t) else { return }
        pointer.stop()
        turning?.cancel()
        let from = (az: azimuth, alt: altitude, fov: fieldOfView)
        let dAz = (h.azimuth - from.az + 540).truncatingRemainder(dividingBy: 360) - 180
        let to = (alt: max(h.altitude, 10), fov: 80.0)
        turning = Task {
            let frames = 60
            for f in 1...frames {
                try? await Task.sleep(for: .milliseconds(16))
                if Task.isCancelled { return }
                let x = Double(f) / Double(frames)
                let e = x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
                azimuth = (from.az + dAz * e + 360).truncatingRemainder(dividingBy: 360)
                altitude = from.alt + (to.alt - from.alt) * e
                fieldOfView = from.fov + (to.fov - from.fov) * e
            }
        }
    }

    /// Turns to the object in `router.skyTarget` once there is a scene to find it in.
    private func showRequestedTarget() {
        guard let t = router.skyTarget, model.scene != nil else { return }
        router.skyTarget = nil
        tour = nil
        shown = t
        aim(at: t)
    }

    /// The daily summary and ISS pass alerts.
    private func rescheduleNotifications() {
        Task {
            await DailySummaryNotifications.reschedule(model)
            await ISSPassNotifications.reschedule(model)
        }
    }

    private func select(_ object: SkyObject?) {
        selection = object
        details = nil
        guard case .body(let body) = object else { return }
        Task { details = await model.details(of: body) }
    }

    /// The view direction with any in-progress gestures applied.
    private func current(width: CGFloat) -> (azimuth: Double, altitude: Double, fieldOfView: Double) {
        let fov = min(max(fieldOfView / Double(zoom), 30), 140)
        if pointer.active { return (pointer.direction.azimuth, pointer.direction.altitude, fov) }
        let degreesPerPoint = fov / Double(max(width, 1))
        let az = (azimuth - Double(drag.width) * degreesPerPoint).truncatingRemainder(dividingBy: 360)
        let alt = min(max(altitude + Double(drag.height) * degreesPerPoint, 0), 90)
        return ((az + 360).truncatingRemainder(dividingBy: 360), alt, fov)
    }

    private func panGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { _ in
                turning?.cancel()
                shown = nil
                if pointer.active {
                    azimuth = pointer.direction.azimuth
                    altitude = min(max(pointer.direction.altitude, 0), 90)
                    pointer.stop()
                }
            }
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                let degreesPerPoint = fieldOfView / Double(max(width, 1))
                azimuth = ((azimuth - Double(value.translation.width) * degreesPerPoint).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
                altitude = min(max(altitude + Double(value.translation.height) * degreesPerPoint, 0), 90)
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .updating($zoom) { value, state, _ in state = value.magnification }
            .onEnded { value in fieldOfView = min(max(fieldOfView / Double(value.magnification), 30), 140) }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                if let y = model.historicalYear {
                    Text("Sky in \(YearSheet.label(y))").font(.title2.weight(.medium))
                    if let p = model.poleStar {
                        Text(String(format: "Pole star: %@, %.1f° from the pole", p.name, p.degrees)).font(.caption2).dimmed(0.8)
                    }
                    Button("Back to today") { model.historicalYear = nil }.font(.caption.weight(.medium))
                } else {
                    Text(model.offsetHours == 0 ? "Tonight" : "Sky at \(model.displayedDate.formatted(date: .omitted, time: .shortened))")
                        .font(.title2.weight(.medium))
                }
                Text(model.placeName)
                    .font(.caption2).dimmed(0.7)
                #if DEBUG
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(stats.summary(build: model.lastBuild))
                        .font(.caption2.monospacedDigit()).dimmed(0.7)
                }
                #endif
            }
            Spacer()
            Menu {
                Section("Tonight") {
                    Button { showTours = true } label: { Label("Guided tours", systemImage: "figure.walk") }
                    Button { showEvents = true } label: { Label("Events and eclipses", systemImage: "calendar") }
                    if pointer.available {
                        Button { pointer.active ? pointer.stop() : pointer.start() } label: {
                            Label(pointer.active ? "Stop following the phone" : "Point the phone at the sky", systemImage: "iphone.gen3.radiowaves.left.and.right")
                        }
                    }
                }
                Section("Explore") {
                    Button { showYear = true } label: { Label("Sky in another year", systemImage: "hourglass") }
                    Button { showLog = true } label: { Label("Observing log", systemImage: "book.closed") }
                }
                Section {
                    Button { nightMode = night ? "off" : "on" } label: {
                        Label(night ? "Turn off night mode" : "Night mode (red light)", systemImage: night ? "eye.slash" : "eye")
                    }
                    Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                }
            } label: {
                Label("Explore", systemImage: "sparkle.magnifyingglass")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .glassEffect(in: .capsule)
            }
            .accessibilityHint("Tours, events, night mode, settings and more")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func card(for object: SkyObject) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title(for: object)).font(.title3.weight(.medium))
                Spacer()
                Button { selection = nil } label: { Image(systemName: "xmark").frame(width: 32, height: 32) }
                    .accessibilityLabel("Close")
            }
            switch object {
            case .body:
                if let d = details { bodyFacts(d) } else { ProgressView().tint(ink) }
            case .constellation(let id):
                Text("Constellation · \(id)").font(.footnote).dimmed(0.7)
            case .deepSky(let m):
                if let d = model.scene?.deepSky.first(where: { $0.object.messier == m }) { deepSkyFacts(d) }
            }
            HStack(spacing: 20) {
                Button { logEntry = newObservation(title(for: object)) } label: {
                    Label("Log", systemImage: "square.and.pencil").font(.footnote.weight(.medium))
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                if let page = libraryPage(for: object) {
                    Button { libraryPage = page } label: {
                        Label("Read more", systemImage: "book").font(.footnote.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                }
            }
        }
        .padding(16)
        .background(style.background.opacity(0.92), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ink.opacity(0.25), lineWidth: 0.5))
    }

    private func newObservation(_ object: String) -> Observation {
        Observation(object: object, date: model.displayedDate, place: model.placeName == "Your location" ? "" : model.placeName,
                    latitude: model.observer.latitude, longitude: model.observer.longitude)
    }

    private func libraryPage(for object: SkyObject) -> LibraryPage? {
        switch object {
        case .body(let b): Library.page(body: b.rawValue)
        case .constellation(let id): Library.page(constellation: id)
        case .deepSky(let m): Catalog.deepSky.first { $0.messier == m }.flatMap { Library.page(id: $0.page) }
        }
    }

    private func title(for object: SkyObject) -> String {
        switch object {
        case .body(let b): b.rawValue.capitalized
        case .constellation(let id): constellationNames[id] ?? id
        case .deepSky(let m): "M\(m)"
        }
    }

    private func bodyFacts(_ d: BodyDetails) -> some View {
        let time: (Date?) -> String = { $0?.formatted(date: .omitted, time: .shortened) ?? "–" }
        let distance = d.body == .moon
            ? "\(Int((d.distanceAU * 149_597_870.7).rounded()).formatted()) km"
            : String(format: "%.2f AU", d.distanceAU)
        let rows: [(String, String)] = [
            ("Altitude", String(format: "%.0f°", d.position.altitude)),
            ("Direction", String(format: "%.0f° %@", d.position.azimuth, compass(d.position.azimuth))),
            ("Magnitude", String(format: "%.1f", d.magnitude)),
            (d.body == .moon ? "Illuminated" : "Phase", String(format: "%.0f%%", d.phaseFraction * 100)),
            ("Distance", distance),
            ("Next rise", time(d.rise)),
            ("Next set", time(d.set)),
        ]
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            ForEach(rows, id: \.0) { row in
                GridRow {
                    Text(row.0).dimmed(0.7)
                    Text(row.1).monospacedDigit()
                }
                .font(.footnote)
            }
        }
    }

    private func deepSkyFacts(_ d: PlacedDeepSky) -> some View {
        let o = d.object
        var rows: [(String, String)] = [
            ("Altitude", String(format: "%.0f°", d.position.altitude)),
            ("Direction", String(format: "%.0f° %@", d.position.azimuth, compass(d.position.azimuth))),
        ]
        if let m = o.magnitude { rows.append(("Magnitude", String(format: "%.1f", m))) }
        if let a = o.majorAxis {
            let b = o.minorAxis.map { String(format: " × %.0f", $0) } ?? ""
            rows.append(("Size", String(format: "%.0f%@′", a, b)))
        }
        return VStack(alignment: .leading, spacing: 8) {
            if let page = Library.page(id: o.page) { Text(page.subtitle).font(.footnote).dimmed(0.7) }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                ForEach(rows, id: \.0) { row in
                    GridRow {
                        Text(row.0).dimmed(0.7)
                        Text(row.1).monospacedDigit()
                    }
                    .font(.footnote)
                }
            }
        }
    }

    /// VoiceOver summary: which way the view faces and what bright bodies are up.
    private func skyDescription(_ scene: SkyScene, azimuth: Double) -> String {
        let up = scene.bodies.filter { $0.position.altitude > 0 && $0.magnitude <= 6 }.map { b -> String in
            let name = b.body.rawValue.capitalized
            return "\(name), \(Int(b.position.altitude.rounded())) degrees up in the \(compass(b.position.azimuth))"
        }
        let facing = "Sky facing \(compass(azimuth))."
        return up.isEmpty ? facing + " No planets or Moon above the horizon." : facing + " Above the horizon: " + up.joined(separator: "; ") + "."
    }

    private func compass(_ azimuth: Double) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return points[Int(((azimuth + 22.5) / 45).rounded(.down)) % 8]
    }
}

/// Draw timings for the debug readout. Written from the Canvas closure, read once a second.
final class DrawStats: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Duration] = []

    func record(_ d: Duration) {
        lock.withLock {
            samples.append(d)
            if samples.count > 120 { samples.removeFirst(samples.count - 120) }
        }
    }

    func summary(build: Duration) -> String {
        let s = lock.withLock { samples }
        let ms = s.map { Double($0.components.attoseconds) / 1e15 + Double($0.components.seconds) * 1000 }.sorted()
        guard let median = ms.isEmpty ? nil : ms[ms.count / 2], let worst = ms.last else { return "draw –" }
        let b = Double(build.components.attoseconds) / 1e15 + Double(build.components.seconds) * 1000
        return String(format: "draw %.1f ms median, %.1f ms max · scene %.0f ms", median, worst, b)
    }
}

/// SkyEngine's Body, named so it isn't shadowed by View.Body.
private typealias SkyBody = Body
