import Foundation
import Testing
@testable import ObservingLog

@Test func eyepieceFieldsFromTheInventory() {
    let items = [
        Equipment(kind: .telescope, name: "8-inch Dobsonian", aperture: 203, focalLength: 1200),
        Equipment(kind: .eyepiece, name: "25 mm Plössl", focalLength: 25, fieldOfView: 52),
        Equipment(kind: .eyepiece, name: "Old 10 mm", focalLength: 10, fieldOfView: 50, retired: true),
        Equipment(kind: .binoculars, name: "10×50", aperture: 50, magnification: 10, fieldOfView: 6.5),
    ]
    let f = EyepieceField.all(in: items)
    #expect(f.map(\.name) == ["8-inch Dobsonian + 25 mm Plössl", "10×50"])
    #expect(abs(f[0].degrees - 52 * 25 / 1200) < 1e-9)
    #expect(f[0].magnification == 48)
    #expect(f[1].degrees == 6.5)
}
