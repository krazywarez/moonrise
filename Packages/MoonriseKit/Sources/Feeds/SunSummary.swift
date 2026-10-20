import Foundation

/// One or two plain sentences on what the Sun is doing to Earth now, from NOAA's feeds.
/// The first matching rule wins: a geomagnetic storm, then a radiation storm, then a flare, then quiet.
/// Every sentence names a figure from a feed and its time.
public enum SunSummary {
    /// Geomagnetic latitude of the auroral oval's equatorward edge for a Kp value.
    /// Must match `ovalEdge` and `visibleFrom` in server/src/aurora.ts.
    static func visibleFrom(kp: Double) -> Double {
        66.5 - 2.04 * kp - 6
    }

    /// Lowest Kp at which aurora may be seen low on the horizon from this geomagnetic latitude.
    static func kpNeeded(at geomagneticLatitude: Double) -> Double {
        (66.5 - 6 - abs(geomagneticLatitude)) / 2.04
    }

    /// `nil` when none of the feeds has loaded. `night` is the current or next night at the observer.
    public static func text(
        scales: NOAAScales?, kp: [KpBar], probabilities: SolarProbabilities?, xray: [XRaySample],
        geomagneticLatitude: Double, night: DateInterval, at now: Date,
        timeZone: TimeZone = .current, locale: Locale = .current
    ) -> String? {
        guard scales != nil || !kp.isEmpty || !xray.isEmpty else { return nil }
        var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)
        style.timeZone = timeZone
        let time = { (d: Date) in d.formatted(style) }
        let current = scales?.current ?? .init(r: 0, s: 0, g: 0)
        let asOf = scales.map { " as of \(time($0.asOf))" } ?? ""

        // Storm-level bars (Kp 5 or more, G1) from now to 24 hours ahead.
        let bar: TimeInterval = 3 * 3600
        let storms = kp.filter { $0.kp >= 5 && $0.start.addingTimeInterval(bar) > now && $0.start < now.addingTimeInterval(86_400) }
        let visible = storms.filter {
            visibleFrom(kp: $0.kp) <= abs(geomagneticLatitude)
                && overlaps($0.start, bar, night)
        }
        let sky = geomagneticLatitude >= 0 ? "northern" : "southern"

        // 1. Geomagnetic storm.
        if let b = visible.max(by: { $0.kp < $1.kp }), let g = SpaceWeather.gScale(b.kp) {
            let end = time(b.start.addingTimeInterval(bar))
            let when = b.start > now ? "forecast for \(time(b.start))–\(end)" : night.contains(now) ? "now" : "forecast until \(end)"
            return "\(name(g)) storm (G\(g)) \(when), Kp \(String(format: "%.1f", b.kp)). Aurora possible low in the \(sky) sky."
        }
        if current.g >= 1 {
            let needed = kpNeeded(at: geomagneticLatitude)
            var text = "\(name(current.g)) storm (G\(current.g))\(asOf)."
            if needed > 9 {
                text += " Aurora at your latitude would need more than Kp 9."
            } else if needed > 5 {
                text += " Aurora at your latitude needs Kp \(String(format: "%.1f", needed))."
            } else if kp.contains(where: { overlaps($0.start, bar, night) }) {
                text += " Kp is forecast below 5 after dark."
            }
            return text
        }

        // 2. Solar radiation storm.
        if current.s >= 1 {
            return "\(name(current.s)) radiation storm (S\(current.s))\(asOf). It affects polar flights and satellites, not people on the ground."
        }

        // 3. Flare of class M or above in the last 6 hours, or a strong radio blackout now.
        if let peak = xray.filter({ $0.time > now.addingTimeInterval(-6 * 3600) }).max(by: { $0.flux < $1.flux }), peak.flux >= 1e-5 {
            return "\(name(rScale(peak.flux))) flare (\(XRay.flareClass(peak.flux))) at \(time(peak.time)). Brief radio blackout on Earth's day side."
        }
        if current.r >= 3 {
            return "\(name(current.r)) radio blackout (R\(current.r))\(asOf). It affects radio on Earth's day side."
        }

        // 4. Quiet.
        if let next = storms.min(by: { $0.start < $1.start }), let g = SpaceWeather.gScale(next.kp) {
            return "Quiet now. \(name(g)) storm (G\(g)) forecast from \(time(next.start)), Kp \(String(format: "%.1f", next.kp))."
        }
        if let m = probabilities?.day(at: now)?.m {
            return "Quiet. \(m)% chance of an M-class flare today."
        }
        return "Quiet. No storms, and no flare of class M or above in the last 6 hours."
    }

    private static func overlaps(_ start: Date, _ duration: TimeInterval, _ interval: DateInterval) -> Bool {
        (DateInterval(start: start, duration: duration).intersection(with: interval)?.duration ?? 0) > 0
    }

    private static func name(_ level: Int) -> String {
        NOAAScales.levelName(level).capitalized
    }

    /// NOAA R scale for a flare's peak flux: R1 at M1, R2 at M5, R3 at X1, R4 at X10, R5 at X20.
    private static func rScale(_ flux: Double) -> Int {
        [1e-5, 5e-5, 1e-4, 1e-3, 2e-3].lastIndex { flux >= $0 }.map { $0 + 1 } ?? 0
    }
}
