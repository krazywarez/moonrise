import Foundation

/// General perturbations orbital elements in CelesTrak's OMM JSON form.
public struct OrbitalElements: Codable, Sendable, Hashable {
    public var OBJECT_NAME: String
    public var NORAD_CAT_ID: Int
    /// UTC, ISO 8601 without a zone, e.g. "2026-10-18T03:28:15.076416".
    public var EPOCH: String
    /// Revolutions per day.
    public var MEAN_MOTION: Double
    public var ECCENTRICITY: Double
    /// Degrees.
    public var INCLINATION: Double
    public var RA_OF_ASC_NODE: Double
    public var ARG_OF_PERICENTER: Double
    public var MEAN_ANOMALY: Double
    public var BSTAR: Double

    public init(name: String, norad: Int, epoch: String, meanMotion: Double, eccentricity: Double, inclination: Double, raan: Double, argPerigee: Double, meanAnomaly: Double, bstar: Double) {
        OBJECT_NAME = name; NORAD_CAT_ID = norad; EPOCH = epoch; MEAN_MOTION = meanMotion; ECCENTRICITY = eccentricity
        INCLINATION = inclination; RA_OF_ASC_NODE = raan; ARG_OF_PERICENTER = argPerigee; MEAN_ANOMALY = meanAnomaly; BSTAR = bstar
    }

    public var epochDate: Date? {
        let parts = EPOCH.split(separator: ".")
        guard let whole = try? Date(String(parts[0]) + "Z", strategy: .iso8601) else { return nil }
        let frac = parts.count > 1 ? Double("0." + parts[1]) ?? 0 : 0
        return whole.addingTimeInterval(frac)
    }
}

/// Near-Earth SGP4 (Vallado et al. 2006, "Revisiting Spacetrack Report #3"), WGS-72 constants.
/// Deep-space orbits (period of 225 minutes or more) are not supported.
public struct SGP4: Sendable {
    // WGS-72
    static let mu = 398600.8
    static let re = 6378.135
    static let xke = 60.0 / ((re * re * re) / mu).squareRoot()
    static let j2 = 0.001082616
    static let j3 = -0.00000253881
    static let j4 = -0.00000165597
    static let j3oj2 = j3 / j2
    static let twoPi = 2 * Double.pi

    public let epoch: Date
    let ecco, inclo, nodeo, argpo, mo, bstar: Double
    let noUnkozai, ao, con41, x1mth2, x7thm1, eta, cc1, cc4, cc5, d2, d3, d4, t2cof, t3cof, t4cof, t5cof: Double
    let mdot, argpdot, nodedot, nodecf, omgcof, xmcof, xlcof, aycof, delmo, sinmao, cosio, sinio: Double
    let isimp: Bool

    public enum Failure: Error { case deepSpace, badEpoch }

    public init(_ el: OrbitalElements) throws {
        guard let epoch = el.epochDate else { throw Failure.badEpoch }
        self.epoch = epoch
        let r = Double.pi / 180
        ecco = el.ECCENTRICITY
        inclo = el.INCLINATION * r
        nodeo = el.RA_OF_ASC_NODE * r
        argpo = el.ARG_OF_PERICENTER * r
        mo = el.MEAN_ANOMALY * r
        bstar = el.BSTAR
        let noKozai = el.MEAN_MOTION * Self.twoPi / 1440
        let x2o3 = 2.0 / 3.0

        // initl
        let eccsq = ecco * ecco, omeosq = 1 - eccsq, rteosq = omeosq.squareRoot()
        cosio = cos(inclo)
        let cosio2 = cosio * cosio
        let ak = pow(Self.xke / noKozai, x2o3)
        let d1 = 0.75 * Self.j2 * (3 * cosio2 - 1) / (rteosq * omeosq)
        var del = d1 / (ak * ak)
        let adel = ak * (1 - del * del - del * (1.0 / 3.0 + 134 * del * del / 81))
        del = d1 / (adel * adel)
        noUnkozai = noKozai / (1 + del)
        guard Self.twoPi / noUnkozai < 225 else { throw Failure.deepSpace }
        ao = pow(Self.xke / noUnkozai, x2o3)
        sinio = sin(inclo)
        let po = ao * omeosq
        let con42 = 1 - 5 * cosio2
        con41 = -con42 - cosio2 - cosio2
        let posq = po * po
        let rp = ao * (1 - ecco)

        // sgp4init
        let ss = 78 / Self.re + 1
        let qzms2t = pow((120 - 78) / Self.re, 4)
        isimp = rp < 220 / Self.re + 1
        var sfour = ss, qzms24 = qzms2t
        let perige = (rp - 1) * Self.re
        if perige < 156 {
            sfour = perige < 98 ? 20 : perige - 78
            qzms24 = pow((120 - sfour) / Self.re, 4)
            sfour = sfour / Self.re + 1
        }
        let pinvsq = 1 / posq
        let tsi = 1 / (ao - sfour)
        eta = ao * ecco * tsi
        let etasq = eta * eta, eeta = ecco * eta
        let psisq = abs(1 - etasq)
        let coef = qzms24 * pow(tsi, 4)
        let coef1 = coef / pow(psisq, 3.5)
        let cc2 = coef1 * noUnkozai * (ao * (1 + 1.5 * etasq + eeta * (4 + etasq)) + 0.375 * Self.j2 * tsi / psisq * con41 * (8 + 3 * etasq * (8 + etasq)))
        cc1 = bstar * cc2
        let cc3 = ecco > 1e-4 ? -2 * coef * tsi * Self.j3oj2 * noUnkozai * sinio / ecco : 0
        x1mth2 = 1 - cosio2
        cc4 = 2 * noUnkozai * coef1 * ao * omeosq * (eta * (2 + 0.5 * etasq) + ecco * (0.5 + 2 * etasq)
            - Self.j2 * tsi / (ao * psisq) * (-3 * con41 * (1 - 2 * eeta + etasq * (1.5 - 0.5 * eeta)) + 0.75 * x1mth2 * (2 * etasq - eeta * (1 + etasq)) * cos(2 * argpo)))
        cc5 = 2 * coef1 * ao * omeosq * (1 + 2.75 * (etasq + eeta) + eeta * etasq)
        let cosio4 = cosio2 * cosio2
        let temp1 = 1.5 * Self.j2 * pinvsq * noUnkozai
        let temp2 = 0.5 * temp1 * Self.j2 * pinvsq
        let temp3 = -0.46875 * Self.j4 * pinvsq * pinvsq * noUnkozai
        mdot = noUnkozai + 0.5 * temp1 * rteosq * con41 + 0.0625 * temp2 * rteosq * (13 - 78 * cosio2 + 137 * cosio4)
        argpdot = -0.5 * temp1 * con42 + 0.0625 * temp2 * (7 - 114 * cosio2 + 395 * cosio4) + temp3 * (3 - 36 * cosio2 + 49 * cosio4)
        let xhdot1 = -temp1 * cosio
        nodedot = xhdot1 + (0.5 * temp2 * (4 - 19 * cosio2) + 2 * temp3 * (3 - 7 * cosio2)) * cosio
        omgcof = bstar * cc3 * cos(argpo)
        xmcof = ecco > 1e-4 ? -x2o3 * coef * bstar / eeta : 0
        nodecf = 3.5 * omeosq * xhdot1 * cc1
        t2cof = 1.5 * cc1
        xlcof = -0.25 * Self.j3oj2 * sinio * (3 + 5 * cosio) / (abs(cosio + 1) > 1.5e-12 ? 1 + cosio : 1.5e-12)
        aycof = -0.5 * Self.j3oj2 * sinio
        delmo = pow(1 + eta * cos(mo), 3)
        sinmao = sin(mo)
        x7thm1 = 7 * cosio2 - 1
        if !isimp {
            let cc1sq = cc1 * cc1
            d2 = 4 * ao * tsi * cc1sq
            let temp = d2 * tsi * cc1 / 3
            d3 = (17 * ao + sfour) * temp
            d4 = 0.5 * temp * ao * tsi * (221 * ao + 31 * sfour) * cc1
            t3cof = d2 + 2 * cc1sq
            t4cof = 0.25 * (3 * d3 + cc1 * (12 * d2 + 10 * cc1sq))
            t5cof = 0.2 * (3 * d4 + 12 * cc1 * d3 + 6 * d2 * d2 + 15 * cc1sq * (2 * d2 + cc1sq))
        } else {
            d2 = 0; d3 = 0; d4 = 0; t3cof = 0; t4cof = 0; t5cof = 0
        }
    }

    /// Position (km) and velocity (km/s) in the TEME frame, `minutes` after epoch.
    public func propagate(minutes t: Double) -> (r: SIMD3<Double>, v: SIMD3<Double>)? {
        let x2o3 = 2.0 / 3.0
        let xmdf = mo + mdot * t
        let argpdf = argpo + argpdot * t
        let nodedf = nodeo + nodedot * t
        var argpm = argpdf, mm = xmdf
        let t2 = t * t
        var nodem = nodedf + nodecf * t2
        var tempa = 1 - cc1 * t
        var tempe = bstar * cc4 * t
        var templ = t2cof * t2
        if !isimp {
            let delomg = omgcof * t
            let delm = xmcof * (pow(1 + eta * cos(xmdf), 3) - delmo)
            let temp = delomg + delm
            mm = xmdf + temp
            argpm = argpdf - temp
            let t3 = t2 * t, t4 = t3 * t
            tempa = tempa - d2 * t2 - d3 * t3 - d4 * t4
            tempe = tempe + bstar * cc5 * (sin(mm) - sinmao)
            templ = templ + t3cof * t3 + t4 * (t4cof + t * t5cof)
        }
        let am = pow(Self.xke / noUnkozai, x2o3) * tempa * tempa
        let nm = Self.xke / pow(am, 1.5)
        var em = ecco - tempe
        guard em < 1, am >= 0.95 else { return nil }
        if em < 1e-6 { em = 1e-6 }
        mm += noUnkozai * templ
        var xlm = mm + argpm + nodem
        nodem = fmod(nodem, Self.twoPi)
        argpm = fmod(argpm, Self.twoPi)
        xlm = fmod(xlm, Self.twoPi)
        mm = fmod(xlm - argpm - nodem, Self.twoPi)

        // Long-period periodics
        let axnl = em * cos(argpm)
        var temp = 1 / (am * (1 - em * em))
        let aynl = em * sin(argpm) + temp * aycof
        let xl = mm + argpm + nodem + temp * xlcof * axnl

        // Kepler's equation
        let u = fmod(xl - nodem, Self.twoPi)
        var eo1 = u, tem5 = 9999.9, ktr = 1
        var sineo1 = 0.0, coseo1 = 0.0
        while abs(tem5) >= 1e-12 && ktr <= 10 {
            sineo1 = sin(eo1); coseo1 = cos(eo1)
            tem5 = 1 - coseo1 * axnl - sineo1 * aynl
            tem5 = (u - aynl * coseo1 + axnl * sineo1 - eo1) / tem5
            if abs(tem5) >= 0.95 { tem5 = tem5 > 0 ? 0.95 : -0.95 }
            eo1 += tem5
            ktr += 1
        }

        // Short-period periodics
        let ecose = axnl * coseo1 + aynl * sineo1
        let esine = axnl * sineo1 - aynl * coseo1
        let el2 = axnl * axnl + aynl * aynl
        let pl = am * (1 - el2)
        guard pl >= 0 else { return nil }
        let rl = am * (1 - ecose)
        let rdotl = am.squareRoot() * esine / rl
        let rvdotl = pl.squareRoot() / rl
        let betal = (1 - el2).squareRoot()
        temp = esine / (1 + betal)
        let sinu = am / rl * (sineo1 - aynl - axnl * temp)
        let cosu = am / rl * (coseo1 - axnl + aynl * temp)
        var su = atan2(sinu, cosu)
        let sin2u = (cosu + cosu) * sinu
        let cos2u = 1 - 2 * sinu * sinu
        temp = 1 / pl
        let temp1 = 0.5 * Self.j2 * temp
        let temp2 = temp1 * temp
        let mrt = rl * (1 - 1.5 * temp2 * betal * con41) + 0.5 * temp1 * x1mth2 * cos2u
        su -= 0.25 * temp2 * x7thm1 * sin2u
        let xnode = nodem + 1.5 * temp2 * cosio * sin2u
        let xinc = inclo + 1.5 * temp2 * cosio * sinio * cos2u
        let mvt = rdotl - nm * temp1 * x1mth2 * sin2u / Self.xke
        let rvdot = rvdotl + nm * temp1 * (x1mth2 * cos2u + 1.5 * con41) / Self.xke

        let sinsu = sin(su), cossu = cos(su), snod = sin(xnode), cnod = cos(xnode), sini = sin(xinc), cosi = cos(xinc)
        let xmx = -snod * cosi, xmy = cnod * cosi
        let uv = SIMD3(xmx * sinsu + cnod * cossu, xmy * sinsu + snod * cossu, sini * sinsu)
        let vv = SIMD3(xmx * cossu - cnod * sinsu, xmy * cossu - snod * sinsu, sini * cossu)
        let vkmpersec = Self.re * Self.xke / 60
        return (mrt * uv * Self.re, (mvt * uv + rvdot * vv) * vkmpersec)
    }

    public func position(at date: Date) -> SIMD3<Double>? {
        propagate(minutes: date.timeIntervalSince(epoch) / 60)?.r
    }
}
