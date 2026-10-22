import AVFoundation
import CoreMotion
import Library
import SkyEngine
import SkyRenderer
import SwiftUI

/// The sky drawn over the back camera's picture. Orientation comes from the gyroscope (Core Motion's arbitrary,
/// gravity-corrected frame), not the compass: one compass reading sets the first heading, and Align turns the heading
/// so a bright object near the centre sits at the centre. Positions include refraction.
struct ARSkyScreen: View {
    var scene: SkyScene
    @State private var attitude = ARAttitude()
    @State private var camera = CameraFeed()
    @State private var drawTime: Duration?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CameraPreview(session: camera.session).ignoresSafeArea()
                if let pose = attitude.pose(focal: camera.focal(for: geo.size)) {
                    SkyView(scene: scene, centerAzimuth: attitude.center.azimuth, centerAltitude: attitude.center.altitude,
                            fieldOfView: camera.verticalField(for: geo.size), showMilkyWay: false, camera: pose) { d in
                        Task { @MainActor in drawTime = d }
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                }
                VStack {
                    HStack {
                        Text(attitude.status).font(.caption).padding(8).background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        Spacer()
                        Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                    }
                    Spacer()
                    if let target = attitude.alignmentTarget(in: scene) {
                        Button("Align on \(target.name)") { attitude.align(on: target) }
                            .buttonStyle(.borderedProminent)
                    }
                    #if DEBUG
                    if let drawTime { Text("draw \(drawTime.formatted(.units(allowed: [.milliseconds], width: .narrow)))").font(.caption2.monospacedDigit()) }
                    #endif
                }
                .padding()
                Image(systemName: "plus").font(.title3.weight(.light)).foregroundStyle(.white.opacity(0.6)).allowsHitTesting(false)
            }
        }
        .foregroundStyle(.white)
        .onAppear { attitude.start(); camera.start() }
        .onDisappear { attitude.stop(); camera.stop() }
    }
}

/// Device attitude from the gyroscope, turned by a heading offset to true north.
@MainActor
@Observable
final class ARAttitude {
    /// The arbitrary frame's azimuth minus the true azimuth, degrees.
    private(set) var offset: Double?
    private(set) var aligned: String?
    private var rows: (SIMD3<Double>, SIMD3<Double>, SIMD3<Double>)?
    private let gyro = CMMotionManager(), compass = CMMotionManager()

    func start() {
        gyro.deviceMotionUpdateInterval = 1.0 / 60
        gyro.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let m = motion?.attitude.rotationMatrix else { return }
            MainActor.assumeIsolated {
                self.rows = (SIMD3(m.m11, m.m12, m.m13), SIMD3(m.m21, m.m22, m.m23), SIMD3(m.m31, m.m32, m.m33))
            }
        }
        // One heading from the compass to start from; the gyroscope carries on alone after that.
        guard CMMotionManager.availableAttitudeReferenceFrames().contains(.xTrueNorthZVertical) else { offset = 0; return }
        compass.startDeviceMotionUpdates(using: .xTrueNorthZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let m = motion?.attitude.rotationMatrix, let arb = self.rows else { return }
            MainActor.assumeIsolated {
                let trueAz = Pointing.direction(m31: m.m31, m32: m.m32, m33: m.m33).azimuth
                let arbAz = Pointing.direction(m31: arb.2.x, m32: arb.2.y, m33: arb.2.z).azimuth
                self.offset = remainder(arbAz - trueAz, 360)
                self.compass.stopDeviceMotionUpdates()
            }
        }
    }

    func stop() {
        gyro.stopDeviceMotionUpdates()
        compass.stopDeviceMotionUpdates()
    }

    /// The device axes in a true-north frame: each row turned by the offset about the vertical.
    func pose(focal: Double) -> CameraPose? {
        guard let rows, let offset else { return nil }
        let t = offset * .pi / 180, c = cos(t), s = sin(t)
        func turn(_ r: SIMD3<Double>) -> SIMD3<Double> { SIMD3(r.x * c - r.y * s, r.x * s + r.y * c, r.z) }
        return CameraPose(rows: (turn(rows.0), turn(rows.1), turn(rows.2)), focal: focal)
    }

    /// Where the camera points, true azimuth.
    var center: Horizontal {
        guard let rows else { return Horizontal(altitude: 0, azimuth: 0) }
        let h = Pointing.direction(m31: rows.2.x, m32: rows.2.y, m33: rows.2.z)
        let az = (h.azimuth - (offset ?? 0)).truncatingRemainder(dividingBy: 360)
        return Horizontal(altitude: h.altitude, azimuth: az < 0 ? az + 360 : az)
    }

    var status: String {
        guard offset != nil else { return "Finding a first heading" }
        return aligned.map { "Aligned on \($0)" } ?? "Heading from the compass; align on a bright object"
    }

    /// The brightest planet, the Moon or a star of magnitude 2 or brighter within 15° of the centre.
    func alignmentTarget(in scene: SkyScene) -> (name: String, position: Horizontal)? {
        let c = center
        func near(_ h: Horizontal) -> Bool { h.altitude > 0 && angle(h, c) < 15 }
        let bodies = scene.bodies.filter { near($0.position) && $0.magnitude < 2 }.map { ($0.body.rawValue.capitalized, $0.position, $0.magnitude) }
        let stars = scene.stars.filter { $0.star.magnitude <= 2 && near($0.position) }
            .map { (starName($0.star.hr), $0.position, $0.star.magnitude) }
        return (bodies + stars).min { $0.2 < $1.2 }.map { ($0.0, $0.1) }
    }

    /// Turns the heading so `target` is at the centre; altitude comes from gravity and is left alone.
    func align(on target: (name: String, position: Horizontal)) {
        guard let offset else { return }
        self.offset = remainder(offset + center.azimuth - target.position.azimuth, 360)
        aligned = target.name
    }

    private func angle(_ a: Horizontal, _ b: Horizontal) -> Double {
        let r = Double.pi / 180
        let c = sin(a.altitude * r) * sin(b.altitude * r) + cos(a.altitude * r) * cos(b.altitude * r) * cos((a.azimuth - b.azimuth) * r)
        return acos(min(1, max(-1, c))) / r
    }

    private func starName(_ hr: Int) -> String {
        Library.page(hr: hr)?.title ?? "HR \(hr)"
    }
}

/// The back wide camera, previewed with aspect fill.
@MainActor
@Observable
final class CameraFeed {
    let session = AVCaptureSession()
    /// Horizontal field of the active format (its long side) in degrees, and its size in pixels.
    private(set) var field = 65.0
    private(set) var dimensions = CGSize(width: 4, height: 3)

    func start() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
        session.addInput(input)
        field = Double(device.activeFormat.videoFieldOfView)
        let d = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        dimensions = CGSize(width: Int(d.width), height: Int(d.height))
        // AVCaptureSession is not Sendable; it is only started and stopped off the main thread, never shared otherwise.
        nonisolated(unsafe) let session = session
        Task.detached { session.startRunning() }
    }

    func stop() {
        nonisolated(unsafe) let session = session
        Task.detached { session.stopRunning() }
    }

    /// Focal length in screen points for a portrait view filled by the landscape sensor image.
    func focal(for view: CGSize) -> Double {
        let w = Double(max(dimensions.width, dimensions.height)), h = Double(min(dimensions.width, dimensions.height))
        let scale = max(Double(view.width) / h, Double(view.height) / w)
        return w / 2 / tan(field / 2 * .pi / 180) * scale
    }

    func verticalField(for view: CGSize) -> Double {
        2 * atan(Double(view.height) / 2 / focal(for: view)) * 180 / .pi
    }
}

struct CameraPreview: UIViewRepresentable {
    var session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.layer.session = session
        v.layer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        override var layer: AVCaptureVideoPreviewLayer { super.layer as! AVCaptureVideoPreviewLayer }
    }
}
