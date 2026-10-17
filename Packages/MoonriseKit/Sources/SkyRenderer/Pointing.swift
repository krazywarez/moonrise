import Foundation
import SkyEngine

public enum Pointing {
    /// Where the back of the phone points, from the third row of a Core Motion
    /// rotation matrix in the x-true-north, z-vertical reference frame
    /// (x north, y west, z up). The camera looks along the device's −z axis.
    public static func direction(m31: Double, m32: Double, m33: Double) -> Horizontal {
        let north = -m31, west = -m32, up = -m33
        let altitude = asin(max(-1, min(1, up))) * 180 / .pi
        var azimuth = atan2(-west, north) * 180 / .pi
        if azimuth < 0 { azimuth += 360 }
        return Horizontal(altitude: altitude, azimuth: azimuth)
    }
}
