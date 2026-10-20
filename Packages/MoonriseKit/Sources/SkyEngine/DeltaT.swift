import CAstronomy
import Foundation

/// ΔT = TT − UT1, seconds. Measured and predicted IERS values from 2020, with the difference from
/// Astronomy Engine's Espenak–Meeus polynomial fading to zero by 2010 and by 2050, so other eras are unchanged.
enum DeltaT {
    /// Decimal year and 32.184 s + (TAI − UTC = 37 s) − (UT1 − UTC), from IERS finals2000A as of
    /// Bulletin A of 15 October 2026. Later entries are its predictions.
    static let table: [(year: Double, seconds: Double)] = [
        (2020.0, 69.361), (2021.0, 69.359), (2022.0, 69.295), (2023.0, 69.204), (2024.0, 69.175), (2025.0, 69.138),
        (2026.0, 69.110), (2026.789, 69.221), (2027.0, 69.308), (2027.584, 69.382), (2027.748, 69.371),
    ]
    static let fadeFrom = 2010.0, fadeTo = 2050.0

    /// `ut`: days since J2000, as Astronomy Engine passes it.
    static func seconds(ut: Double) -> Double {
        let model = Astronomy_DeltaT_EspenakMeeus(ut)
        // The polynomial's own year scale.
        let year = 2000 + (ut - 14) / 365.24217
        guard year > fadeFrom, year < fadeTo else { return model }
        let first = table[0], last = table[table.count - 1]
        if year < first.year {
            return model + (first.seconds - polynomial(first.year)) * (year - fadeFrom) / (first.year - fadeFrom)
        }
        if year > last.year {
            return model + (last.seconds - polynomial(last.year)) * (fadeTo - year) / (fadeTo - last.year)
        }
        let i = table.firstIndex { $0.year >= year }!
        guard i > 0 else { return first.seconds }
        let a = table[i - 1], b = table[i]
        return a.seconds + (b.seconds - a.seconds) * (year - a.year) / (b.year - a.year)
    }

    static func polynomial(_ year: Double) -> Double {
        Astronomy_DeltaT_EspenakMeeus((year - 2000) * 365.24217 + 14)
    }

    /// Astronomy Engine reads ΔT through a global function pointer; `SkyEngine.time` touches this first.
    static let installed: Void = Astronomy_SetDeltaTFunction { DeltaT.seconds(ut: $0) }
}
