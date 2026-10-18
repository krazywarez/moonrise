import Library
import SkyEngine
import SkyRenderer
import SwiftUI

struct SkyScreen: View {
    @State private var model = SkyModel()
    @State private var pointer = MotionPointer()
    @State private var azimuth = 180.0
    @State private var altitude = 45.0
    @State private var fieldOfView = 100.0
    @State private var night = false
    @State private var showToday = false
    @State private var libraryPage: LibraryPage?
    @State private var selection: SkyObject?
    @State private var details: BodyDetails?
    @GestureState private var drag: CGSize = .zero
    @GestureState private var zoom: CGFloat = 1
    private let stats = DrawStats()

    private var style: SkyStyle { night ? .night : SkyStyle() }
    private var ink: Color { night ? Color(red: 0.85, green: 0.12, blue: 0.08) : Color(red: 0.95, green: 0.95, blue: 0.93) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                style.background.ignoresSafeArea()
                if let scene = model.scene {
                    let view = current(width: geo.size.width)
                    SkyView(scene: scene, centerAzimuth: view.azimuth, centerAltitude: view.altitude, fieldOfView: view.fieldOfView, style: style) { [stats] d in
                        stats.record(d)
                    }
                    .ignoresSafeArea()
                    .gesture(panGesture(width: geo.size.width).simultaneously(with: zoomGesture))
                    .onTapGesture(coordinateSpace: .local) { location in
                        let p = Projection(centerAzimuth: view.azimuth, centerAltitude: view.altitude, fieldOfView: view.fieldOfView, size: geo.size)
                        select(scene.object(at: location, projection: p))
                    }
                }
                VStack(spacing: 0) {
                    header
                    if let selection { card(for: selection).padding(.horizontal, 16).padding(.top, 8) }
                    Spacer()
                    TodayBar(model: model, ink: ink, background: style.ground) { showToday = true }
                }
            }
        }
        .foregroundStyle(ink)
        .sheet(item: $libraryPage) { page in
            NavigationStack { LibraryPageView(page: page) }
        }
        .sheet(isPresented: $showToday) {
            TodaySheet(model: model, ink: ink, background: style.ground)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: model.offsetHours) { select(selection) }
        .task {
            model.start()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                model.refresh()
            }
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
                Text(model.offsetHours == 0 ? "Tonight" : "Sky at \(model.displayedDate.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 22, weight: .medium))
                Text(model.hasLocation ? "Your location" : "Chicago (location unavailable)")
                    .font(.system(size: 11)).opacity(0.7)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(stats.summary(build: model.lastBuild))
                        .font(.system(size: 10).monospacedDigit()).opacity(0.7)
                }
            }
            Spacer()
            if pointer.available {
                Button {
                    pointer.active ? pointer.stop() : pointer.start()
                } label: {
                    Image(systemName: pointer.active ? "scope" : "hand.draw")
                        .font(.system(size: 17))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(pointer.active ? "Stop following the phone" : "Point the phone at the sky")
            }
            Button {
                night.toggle()
            } label: {
                Image(systemName: night ? "eye.fill" : "eye")
                    .font(.system(size: 17))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(night ? "Turn off night mode" : "Turn on night mode")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func card(for object: SkyObject) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title(for: object)).font(.system(size: 20, weight: .medium))
                Spacer()
                Button { selection = nil } label: { Image(systemName: "xmark").frame(width: 32, height: 32) }
                    .accessibilityLabel("Close")
            }
            switch object {
            case .body:
                if let d = details { bodyFacts(d) } else { ProgressView().tint(ink) }
            case .constellation(let id):
                Text("Constellation · \(id)").font(.system(size: 13)).opacity(0.7)
            }
            if let page = libraryPage(for: object) {
                Button { libraryPage = page } label: {
                    Label("Read more", systemImage: "book").font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(style.background.opacity(0.92), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ink.opacity(0.25), lineWidth: 0.5))
    }

    private func libraryPage(for object: SkyObject) -> LibraryPage? {
        switch object {
        case .body(let b): Library.page(body: b.rawValue)
        case .constellation(let id): Library.page(constellation: id)
        }
    }

    private func title(for object: SkyObject) -> String {
        switch object {
        case .body(let b): b.rawValue.capitalized
        case .constellation(let id): constellationNames[id] ?? id
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
                    Text(row.0).opacity(0.7)
                    Text(row.1).monospacedDigit()
                }
                .font(.system(size: 13))
            }
        }
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
