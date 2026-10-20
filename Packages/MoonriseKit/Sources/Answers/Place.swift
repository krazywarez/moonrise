import Foundation
import SkyEngine

/// Where answers are worked out for. The Sky tab saves its observer here on every fix or city change,
/// so intents launched in the background can answer without a location fix.
public struct Place: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        /// The device's own position.
        case located
        /// A city chosen in Settings.
        case city
        /// No fix and no city yet.
        case fallback
    }

    public var latitude: Double
    public var longitude: Double
    public var name: String
    public var kind: Kind

    /// Rounds to 0.1°, about 10 km, which is all any answer needs.
    public init(latitude: Double, longitude: Double, name: String, kind: Kind) {
        self.latitude = (latitude * 10).rounded() / 10
        self.longitude = (longitude * 10).rounded() / 10
        self.name = name
        self.kind = kind
    }

    public static let fallback = Place(latitude: 41.8781, longitude: -87.6298, name: "Chicago", kind: .fallback)

    public var observer: Observer { Observer(latitude: latitude, longitude: longitude) }

    /// "Your location" or the place's name.
    public var label: String { kind == .located ? "Your location" : name }

    /// Sentence that ends an answer which depends on the place; nil for the device's own position.
    public var note: String? {
        switch kind {
        case .located: nil
        case .city: "For \(name)."
        case .fallback: "For \(name); open Moonrise to set your location."
        }
    }

    static let key = "answersPlace"

    public static func saved(in defaults: UserDefaults) -> Place? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Place.self, from: $0) }
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }
}

extension [String] {
    /// Joins sentences, with the place's note, if any, last.
    func sentences(_ note: String?) -> String {
        (self + [note].compactMap { $0 }).joined(separator: " ")
    }
}
