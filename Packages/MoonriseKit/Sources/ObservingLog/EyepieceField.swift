import Foundation

/// A true field of view from the inventory: each telescope with each eyepiece, and each pair of binoculars.
public struct EyepieceField: Sendable, Equatable, Identifiable {
    public var name: String
    /// Degrees across.
    public var degrees: Double
    public var magnification: Double?
    public var id: String { name }

    /// True field = apparent field × eyepiece focal length / telescope focal length; binoculars give theirs.
    public static func all(in items: [Equipment]) -> [EyepieceField] {
        let active = items.filter { !$0.retired }
        var out: [EyepieceField] = []
        for t in active where t.kind == .telescope {
            guard let tfl = t.focalLength, tfl > 0 else { continue }
            for e in active where e.kind == .eyepiece {
                guard let efl = e.focalLength, let afov = e.fieldOfView, efl > 0 else { continue }
                out.append(EyepieceField(name: "\(t.name) + \(e.name)", degrees: afov * efl / tfl, magnification: tfl / efl))
            }
        }
        for b in active where b.kind == .binoculars {
            guard let f = b.fieldOfView else { continue }
            out.append(EyepieceField(name: b.name, degrees: f, magnification: b.magnification))
        }
        return out
    }
}
