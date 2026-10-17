import SkyRenderer
import SwiftUI

struct SkyScreen: View {
    @State private var model = SkyModel()
    @State private var azimuth = 180.0
    @State private var altitude = 45.0
    @State private var fieldOfView = 100.0
    @GestureState private var drag: CGSize = .zero
    @GestureState private var zoom: CGFloat = 1
    private let stats = DrawStats()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color(red: 0.043, green: 0.078, blue: 0.141).ignoresSafeArea()
                if let scene = model.scene {
                    let view = current(width: geo.size.width)
                    SkyView(scene: scene, centerAzimuth: view.azimuth, centerAltitude: view.altitude, fieldOfView: view.fieldOfView) { [stats] d in
                        stats.record(d)
                    }
                    .ignoresSafeArea()
                    .gesture(panGesture(width: geo.size.width).simultaneously(with: zoomGesture))
                }
                header
            }
        }
        .task {
            model.start()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                model.refresh()
            }
        }
    }

    /// The view direction with any in-progress gestures applied.
    private func current(width: CGFloat) -> (azimuth: Double, altitude: Double, fieldOfView: Double) {
        let fov = min(max(fieldOfView / Double(zoom), 30), 140)
        let degreesPerPoint = fov / Double(max(width, 1))
        let az = (azimuth - Double(drag.width) * degreesPerPoint).truncatingRemainder(dividingBy: 360)
        let alt = min(max(altitude + Double(drag.height) * degreesPerPoint, 0), 90)
        return ((az + 360).truncatingRemainder(dividingBy: 360), alt, fov)
    }

    private func panGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
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
        VStack(alignment: .leading, spacing: 4) {
            Text("Tonight").font(.system(size: 22, weight: .medium))
            Text(model.hasLocation ? "Your location" : "Chicago (location unavailable)")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(stats.summary(build: model.lastBuild))
                    .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(Color(red: 0.95, green: 0.95, blue: 0.93))
        .padding(.horizontal, 20)
        .padding(.top, 8)
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
