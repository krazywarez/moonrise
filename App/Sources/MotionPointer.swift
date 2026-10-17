import CoreMotion
import Observation
import SkyEngine
import SkyRenderer

/// Points the sky where the back of the phone points, using true north.
@MainActor
@Observable
final class MotionPointer {
    private(set) var active = false
    private(set) var direction = Horizontal(altitude: 45, azimuth: 180)
    var available: Bool { CMMotionManager.availableAttitudeReferenceFrames().contains(.xTrueNorthZVertical) }

    private let manager = CMMotionManager()

    func start() {
        guard available, !active else { return }
        active = true
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates(using: .xTrueNorthZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let m = motion?.attitude.rotationMatrix else { return }
            MainActor.assumeIsolated { self.update(Pointing.direction(m31: m.m31, m32: m.m32, m33: m.m33)) }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        active = false
    }

    /// Light low-pass filter; azimuth is smoothed across the 0/360 wrap.
    private func update(_ h: Horizontal) {
        let k = 0.25
        let dAz = remainder(h.azimuth - direction.azimuth, 360)
        var az = direction.azimuth + k * dAz
        if az < 0 { az += 360 } else if az >= 360 { az -= 360 }
        direction = Horizontal(altitude: direction.altitude + k * (h.altitude - direction.altitude), azimuth: az)
    }
}
