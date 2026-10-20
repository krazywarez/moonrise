import CAstronomy
import Foundation

public struct SkyEvent: Sendable, Identifiable, Equatable {
    public enum Kind: String, Sendable {
        case moonPhase, lunarEclipse, solarEclipse, opposition, elongation, season, meteorShower
    }

    public var kind: Kind
    public var date: Date
    public var title: String
    public var detail: String
    /// Whether it can be seen from the observer's location; nil when that does not apply.
    public var visibleHere: Bool?
    /// When to look, for a forecast: the dark part of a meteor shower's peak night (the whole night where it never gets
    /// fully dark), or greatest eclipse here as a zero-length interval. Nil for other events and eclipses not seen here.
    public var window: DateInterval?
    public var id: String { "\(kind.rawValue)-\(title)-\(Int(date.timeIntervalSince1970))" }
}

/// A major annual meteor shower (International Meteor Organization working list).
public struct MeteorShower: Sendable {
    public var name: String
    /// Typical peak, month and day; the exact time varies by a day or so each year.
    public var month: Int
    public var day: Int
    /// Zenithal hourly rate at peak under ideal skies.
    public var zhr: Int

    public static let major: [MeteorShower] = [
        MeteorShower(name: "Quadrantids", month: 1, day: 3, zhr: 80),
        MeteorShower(name: "Lyrids", month: 4, day: 22, zhr: 18),
        MeteorShower(name: "Eta Aquariids", month: 5, day: 6, zhr: 50),
        MeteorShower(name: "Perseids", month: 8, day: 12, zhr: 100),
        MeteorShower(name: "Orionids", month: 10, day: 21, zhr: 20),
        MeteorShower(name: "Leonids", month: 11, day: 17, zhr: 15),
        MeteorShower(name: "Geminids", month: 12, day: 14, zhr: 150),
        MeteorShower(name: "Ursids", month: 12, day: 22, zhr: 10),
    ]
}

extension SkyEngine {
    static func eclipseKind(_ k: astro_eclipse_kind_t) -> String {
        switch k {
        case ECLIPSE_PENUMBRAL: "Penumbral"
        case ECLIPSE_PARTIAL: "Partial"
        case ECLIPSE_ANNULAR: "Annular"
        case ECLIPSE_TOTAL: "Total"
        default: ""
        }
    }

    /// Astronomical events from `start` for `days` days, sorted by date.
    public static func events(from start: Date, days: Double = 366, observer: Observer) -> [SkyEvent] {
        lock.lock()
        defer { lock.unlock() }
        let end = start.addingTimeInterval(days * 86_400)
        var out: [SkyEvent] = []

        // Full and new moons
        var t = time(start)
        while true {
            let q = Astronomy_SearchMoonQuarter(t)
            guard q.status == ASTRO_SUCCESS else { break }
            let d = date(q.time)
            if d > end { break }
            if q.quarter == 0 || q.quarter == 2 {
                out.append(SkyEvent(kind: .moonPhase, date: d, title: q.quarter == 0 ? "New moon" : "Full moon", detail: q.quarter == 0 ? "Darkest skies of the month." : "The Moon is opposite the Sun and up all night.", visibleHere: nil))
            }
            t = Astronomy_AddDays(q.time, 1)
        }

        // Lunar eclipses
        var lunar = Astronomy_SearchLunarEclipse(time(start))
        while lunar.status == ASTRO_SUCCESS, date(lunar.peak) <= end {
            var peak = lunar.peak
            let moon = Astronomy_Equator(BODY_MOON, &peak, observer.astro, EQUATOR_OF_DATE, ABERRATION)
            let alt = Astronomy_Horizon(&peak, observer.astro, moon.ra, moon.dec, REFRACTION_NORMAL).altitude
            let minutes = lunar.sd_total > 0 ? lunar.sd_total * 2 : lunar.sd_partial * 2
            let length = minutes > 0 ? String(format: " %@ phase lasts %.0f minutes.", lunar.sd_total > 0 ? "Total" : "Partial", minutes) : ""
            out.append(SkyEvent(kind: .lunarEclipse, date: date(lunar.peak), title: "\(eclipseKind(lunar.kind)) lunar eclipse", detail: (alt > 0 ? "The Moon is up here at mid-eclipse." : "The Moon is below the horizon here at mid-eclipse.") + length, visibleHere: alt > 0,
                                window: alt > 0 ? DateInterval(start: date(lunar.peak), duration: 0) : nil))
            lunar = Astronomy_NextLunarEclipse(lunar.peak)
        }

        // Solar eclipses: global, with local circumstances for the observer
        var local: [Date: astro_local_solar_eclipse_t] = [:]
        var l = Astronomy_SearchLocalSolarEclipse(time(start), observer.astro)
        while l.status == ASTRO_SUCCESS, date(l.peak.time) <= end {
            local[date(l.peak.time)] = l
            l = Astronomy_NextLocalSolarEclipse(l.peak.time, observer.astro)
        }
        var solar = Astronomy_SearchGlobalSolarEclipse(time(start))
        while solar.status == ASTRO_SUCCESS, date(solar.peak) <= end {
            let peakDate = date(solar.peak)
            let here = local.first { abs($0.key.timeIntervalSince(peakDate)) < 6 * 3600 }?.value
            var detail: String
            var visible = false
            var window: DateInterval?
            if let here, here.peak.altitude > 0 {
                visible = true
                window = DateInterval(start: date(here.peak.time), duration: 0)
                detail = String(format: "From here: %@, %.0f%% of the Sun covered at %@.", eclipseKind(here.kind).lowercased(), here.obscuration * 100, date(here.peak.time).formatted(date: .omitted, time: .shortened))
            } else {
                detail = "Not visible from here."
            }
            if solar.kind == ECLIPSE_TOTAL || solar.kind == ECLIPSE_ANNULAR {
                detail += String(format: " Greatest eclipse at %.1f°%@, %.1f°%@.", abs(solar.latitude), solar.latitude >= 0 ? "N" : "S", abs(solar.longitude), solar.longitude >= 0 ? "E" : "W")
            }
            out.append(SkyEvent(kind: .solarEclipse, date: peakDate, title: "\(eclipseKind(solar.kind)) solar eclipse", detail: detail, visibleHere: visible, window: window))
            solar = Astronomy_NextGlobalSolarEclipse(solar.peak)
        }

        // Oppositions of the outer planets
        for body in [Body.mars, .jupiter, .saturn, .uranus, .neptune] {
            let r = Astronomy_SearchRelativeLongitude(body.astro, 0, time(start))
            guard r.status == ASTRO_SUCCESS, date(r.time) <= end else { continue }
            out.append(SkyEvent(kind: .opposition, date: date(r.time), title: "\(body.rawValue.capitalized) at opposition", detail: "Opposite the Sun: up all night and at its closest and brightest for the year.", visibleHere: nil))
        }

        // Greatest elongations of Mercury and Venus
        for body in [Body.mercury, .venus] {
            var from = time(start)
            while true {
                let e = Astronomy_SearchMaxElongation(body.astro, from)
                guard e.status == ASTRO_SUCCESS, date(e.time) <= end else { break }
                let when = e.visibility == VISIBLE_MORNING ? "morning" : "evening"
                out.append(SkyEvent(kind: .elongation, date: date(e.time), title: "\(body.rawValue.capitalized) at greatest \(when) elongation", detail: String(format: "%.0f° from the Sun, best placed in the %@ sky.", e.elongation, when), visibleHere: nil))
                from = Astronomy_AddDays(e.time, 10)
            }
        }

        // Equinoxes and solstices
        let cal = Calendar(identifier: .gregorian)
        let y0 = cal.component(.year, from: start)
        for y in y0...(y0 + 1) {
            let s = Astronomy_Seasons(Int32(y))
            guard s.status == ASTRO_SUCCESS else { continue }
            for (t, name) in [(s.mar_equinox, "March equinox"), (s.jun_solstice, "June solstice"), (s.sep_equinox, "September equinox"), (s.dec_solstice, "December solstice")] {
                let d = date(t)
                if d >= start && d <= end { out.append(SkyEvent(kind: .season, date: d, title: name, detail: "", visibleHere: nil)) }
            }
        }

        // Meteor showers, with darkness and the Moon on the observer's night of the peak
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        for y in y0...(y0 + 1) {
            for m in MeteorShower.major {
                guard let d = utc.date(from: DateComponents(year: y, month: m.month, day: m.day, hour: 12)), d >= start, d <= end else { continue }
                // Local solar midnight after the evening of the peak date.
                let midnight = d.addingTimeInterval((12 - observer.longitude / 15) * 3600)
                let lit = Astronomy_Illumination(BODY_MOON, time(midnight)).phase_fraction
                let noon = midnight.addingTimeInterval(-12 * 3600)
                let sunset = riseSet(.sun, after: noon, from: observer).set ?? noon
                let night = DateInterval(start: sunset, end: riseSet(.sun, after: sunset, from: observer).rise ?? sunset.addingTimeInterval(12 * 3600))
                let dark = try? darkness(from: night.start, to: night.end, observer: observer)
                let moon = moonAndDarkness(night: night, dark: dark,
                                           moonUp: (try? moonUp(from: night.start, to: night.end, observer: observer)) ?? [], moonIllumination: lit)
                out.append(SkyEvent(kind: .meteorShower, date: d, title: "\(m.name) peak", detail: "Up to about \(m.zhr) meteors an hour under dark skies. \(moon)", visibleHere: nil, window: dark ?? night))
            }
        }

        return out.sorted { $0.date < $1.date }
    }
}
