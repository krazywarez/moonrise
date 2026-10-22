import Foundation
import SkyEngine

public struct Star: Sendable {
    public var hr: Int
    public var ra: Double
    public var dec: Double
    public var magnitude: Double
    public var colorIndex: Double
    /// Proper motion in arcseconds per year; `pmRA` already includes cos(dec).
    public var pmRA: Double = 0
    public var pmDec: Double = 0

    /// J2000 coordinates moved by proper motion to `date` (linear, which is close enough over a few thousand years).
    public func position(at date: Date) -> (ra: Double, dec: Double) {
        let years = date.timeIntervalSince(SkyEngine.j2000) / (365.25 * 86_400)
        let dec = self.dec + pmDec * years / 3600
        let ra = self.ra + pmRA * years / 3600 / max(cos(self.dec * .pi / 180), 1e-6)
        return (ra, dec)
    }
}

public struct Constellation: Sendable, Decodable {
    public var id: String
    /// Polylines of HR numbers.
    public var lines: [[Int]]
}

/// Another culture's figures over the same stars, from Stellarium's sky cultures (CC BY-SA).
public struct SkyCulture: Sendable, Decodable, Identifiable {
    public struct Figure: Sendable, Decodable {
        public var name: String
        public var native: String?
        /// Polylines of HR numbers.
        public var lines: [[Int]]
    }

    public var id: String
    public var name: String
    public var region: String
    public var licence: String
    public var source: URL
    public var constellations: [Figure]
}

/// A Messier object from OpenNGC (CC BY-SA 4.0).
public struct DeepSkyObject: Sendable, Decodable {
    public enum Kind: Sendable { case galaxy, openCluster, globularCluster, nebula, planetaryNebula }

    public var messier: Int
    /// OpenNGC type code, e.g. "G", "OCl", "GCl", "PN", "Neb".
    public var type: String
    /// J2000, degrees.
    public var ra: Double
    public var dec: Double
    public var magnitude: Double?
    /// Arcminutes.
    public var majorAxis: Double?
    public var minorAxis: Double?
    /// Degrees east of north.
    public var positionAngle: Double?
    /// Library page id; empty for NGC and IC objects.
    public var page: String
    /// "NGC 7000" or "IC 434"; nil for Messier objects.
    public var designation: String?

    /// "M42" or "NGC 7000".
    public var name: String { designation ?? "M\(messier)" }

    public var kind: Kind {
        switch type {
        case "G": .galaxy
        case "GCl": .globularCluster
        case "PN": .planetaryNebula
        case "Neb", "HII", "RfN", "Cl+N", "SNR": .nebula
        // OCl, and the star cloud M24, double star M40 and asterism M73.
        default: .openCluster
        }
    }
}

public enum Catalog {
    /// Yale Bright Star Catalogue, 5th ed. (VizieR V/50): HR, RA and Dec (J2000, degrees), V, B−V,
    /// proper motion in RA (× cos dec) and Dec (arcsec/yr).
    public static let stars: [Star] = {
        let url = Bundle.module.url(forResource: "bsc5", withExtension: "json")!
        let rows = try! JSONDecoder().decode([[Double]].self, from: Data(contentsOf: url))
        return rows.map { Star(hr: Int($0[0]), ra: $0[1], dec: $0[2], magnitude: $0[3], colorIndex: $0[4], pmRA: $0[5], pmDec: $0[6]) }
    }()

    /// Tycho-2 stars from V 6 to 9 not in the Bright Star Catalogue (ESA; Høg et al. 2000), sorted by V, built by
    /// scripts/make-tycho.py; `hr` is 0. About 121,000 stars, decoded on first use.
    public static let faintStars: [Star] = {
        let url = Bundle.module.url(forResource: "tycho2", withExtension: "bin")!
        let data = try! Data(contentsOf: url)
        return stride(from: 0, to: data.count - 13, by: 14).map { o in
            data.withUnsafeBytes { b in
                let ra = Double(b.loadUnaligned(fromByteOffset: o, as: UInt32.self).littleEndian) / 4_294_967_296 * 360
                let dec = Double(b.loadUnaligned(fromByteOffset: o + 4, as: Int32.self).littleEndian) / 2_147_483_647 * 90
                let v = Double(b[o + 8]) / 20 - 2
                let bv = Double(Int8(bitPattern: b[o + 9])) / 50
                let pmRA = Double(b.loadUnaligned(fromByteOffset: o + 10, as: Int16.self).littleEndian) / 1000
                let pmDec = Double(b.loadUnaligned(fromByteOffset: o + 12, as: Int16.self).littleEndian) / 1000
                return Star(hr: 0, ra: ra, dec: dec, magnitude: v, colorIndex: bv, pmRA: pmRA, pmDec: pmDec)
            }
        }
    }()

    /// Stars by HR number.
    public static let starsByHR: [Int: Star] = Dictionary(uniqueKeysWithValues: stars.map { ($0.hr, $0) })

    /// Built by scripts/make-skycultures.py.
    public static let skyCultures: [SkyCulture] = {
        let url = Bundle.module.url(forResource: "skycultures", withExtension: "json")!
        return try! JSONDecoder().decode([SkyCulture].self, from: Data(contentsOf: url))
    }()

    public static let constellations: [Constellation] = {
        let url = Bundle.module.url(forResource: "constellations", withExtension: "json")!
        return try! JSONDecoder().decode([Constellation].self, from: Data(contentsOf: url))
    }()

    /// Milky Way brightness on a 2° J2000 grid (rows Dec −89° to +89°, columns RA 1° to 359°), from ESA's "Gaia's sky
    /// in colour" (ESA/Gaia/DPAC, CC BY-SA 3.0 IGO), built by scripts/make-milkyway.swift.
    public static let milkyWay: [UInt8] = {
        let url = Bundle.module.url(forResource: "milkyway", withExtension: "bin")!
        return [UInt8](try! Data(contentsOf: url))
    }()

    /// Built by scripts/make-messier.py.
    public static let deepSky: [DeepSkyObject] = {
        let url = Bundle.module.url(forResource: "messier", withExtension: "json")!
        return try! JSONDecoder().decode([DeepSkyObject].self, from: Data(contentsOf: url))
    }()

    /// NGC and IC objects to magnitude 11 not in Messier's list, from OpenNGC (CC BY-SA 4.0), built by
    /// scripts/make-ngc.py.
    public static let ngc: [DeepSkyObject] = {
        let url = Bundle.module.url(forResource: "ngc", withExtension: "json")!
        return try! JSONDecoder().decode([DeepSkyObject].self, from: Data(contentsOf: url))
    }()
}

public struct PlacedStar: Sendable {
    public var star: Star
    public var position: Horizontal
}

public struct PlacedDeepSky: Sendable {
    public var object: DeepSkyObject
    public var position: Horizontal
    /// A point 0.1° north (J2000), for the symbol's scale and orientation on screen.
    public var north: Horizontal
}

public struct PlacedBody: Sendable {
    public var body: Body
    public var position: Horizontal
    public var magnitude: Double
    public var phaseFraction: Double
}

/// Everything above (and just below) the horizon for one place and time.
public struct SkyScene: Sendable {
    public var date: Date
    public var observer: Observer
    public var stars: [PlacedStar]
    public var starsByHR: [Int: Horizontal]
    public var bodies: [PlacedBody]
    public var deepSky: [PlacedDeepSky]
    public var ngc: [PlacedDeepSky]
    /// Moon's elongation east of the sun, degrees (0 new, 180 full).
    public var moonPhase: Double
    /// Milky Way cells brighter than `milkyWayFloor`, above −3° (the rest are dropped before projection).
    public var milkyWay: [(position: Horizontal, value: UInt8)]

    static let milkyWayFloor: UInt8 = 48

    /// Tycho-2 stars within `radius` degrees of a direction, placed for this scene. The region is chosen with an
    /// approximate inverse transform, so `radius` should allow a degree or two.
    public func faintStars(around center: Horizontal, radius: Double) -> [PlacedStar] {
        let c = SkyEngine.approximateJ2000(of: center, at: date, from: observer)
        let r = Double.pi / 180
        let cosLimit = cos(radius * r), sinDec = sin(c.dec * r), cosDec = cos(c.dec * r)
        let near = Catalog.faintStars.filter { s in
            sin(s.dec * r) * sinDec + cos(s.dec * r) * cosDec * cos((s.ra - c.ra) * r) >= cosLimit
        }
        let placed = SkyEngine.horizontal(j2000: near.map { $0.position(at: date) }, at: date, from: observer)
        return zip(near, placed).map { PlacedStar(star: $0, position: $1) }
    }

    public init(date: Date, observer: Observer, magnitudeLimit: Double = 6.5) throws {
        self.date = date
        self.observer = observer
        let visible = Catalog.stars.filter { $0.magnitude <= magnitudeLimit }
        let positions = SkyEngine.horizontal(j2000: visible.map { $0.position(at: date) }, at: date, from: observer)
        stars = zip(visible, positions).map { PlacedStar(star: $0, position: $1) }
        starsByHR = Dictionary(uniqueKeysWithValues: stars.map { ($0.star.hr, $0.position) })
        let dso = SkyEngine.horizontal(j2000: Catalog.deepSky.flatMap { [($0.ra, $0.dec), ($0.ra, $0.dec + 0.1)] }, at: date, from: observer)
        deepSky = Catalog.deepSky.enumerated().map { i, o in PlacedDeepSky(object: o, position: dso[2 * i], north: dso[2 * i + 1]) }
        let n = SkyEngine.horizontal(j2000: Catalog.ngc.flatMap { [($0.ra, $0.dec), ($0.ra, $0.dec + 0.1)] }, at: date, from: observer)
        ngc = Catalog.ngc.enumerated().map { i, o in PlacedDeepSky(object: o, position: n[2 * i], north: n[2 * i + 1]) }
        bodies = try ([.moon] + Body.planets).map { body in
            let i = try SkyEngine.illumination(body, at: date)
            return PlacedBody(
                body: body,
                position: try SkyEngine.horizontal(body, at: date, from: observer),
                magnitude: i.magnitude,
                phaseFraction: i.phaseFraction
            )
        }
        moonPhase = try SkyEngine.moonPhase(at: date)
        let cells = Catalog.milkyWay.enumerated().filter { $0.element > Self.milkyWayFloor }
        let centres = cells.map { (ra: 1 + 2 * Double($0.offset % 180), dec: -89 + 2 * Double($0.offset / 180)) }
        let placed = SkyEngine.horizontal(j2000: centres, at: date, from: observer)
        milkyWay = zip(placed, cells).filter { $0.0.altitude > -3 }.map { ($0.0, $0.1.element) }
    }
}
