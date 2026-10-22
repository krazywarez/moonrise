import Foundation
import Testing
@testable import ObservingLog

private let utc = TimeZone(identifier: "UTC")!

private func entry(_ object: String, _ iso: String, _ props: [String: String], notes: String = "") throws -> Observation {
    var o = Observation(object: object, date: try Date(iso, strategy: .iso8601), place: "Peak Crossing", latitude: -27.78, longitude: 152.73, notes: notes)
    for (k, v) in props { o[property: k] = v }
    return o
}

@Test func propertiesSetAndClear() throws {
    var o = try entry("SS Cyg", "2026-10-20T03:00:00Z", [":REPORT:": "variable", ":MAGNITUDE:": " 10.9 "])
    #expect(o.report == .variable)
    #expect(o[property: ":MAGNITUDE:"] == "10.9")
    o[property: ":MAGNITUDE:"] = ""
    #expect(o.otherProperties == [OrgProperty(key: ":REPORT:", value: "variable")])
    #expect(Observation(org: o.org)?.report == .variable)
}

/// COBS observation by DRE01 on 2024-10-03, rebuilt from its fields (extinction note and tail modifier left out).
@Test func icqLineMatchesCOBSColumns() throws {
    let o = try entry("Tsuchinshan–ATLAS", "2024-10-03T18:43:12Z", [
        ":REPORT:": "comet", ":DESIGNATION:": "C/2023 A3", ":METHOD:": "M", ":MAGNITUDE:": "1.5:", ":REFERENCE:": "TT",
        ":APERTURE:": "5", ":INSTRUMENT:": "B", ":POWER:": "12", ":COMA:": "2.5", ":DC:": "7/", ":TAIL:": "3.9", ":PA:": "258",
    ])
    #expect(ICQ.line(o, observerCode: "DRE01") == "   2023A3  2024 10 03.78  M  1.5:TT  5.0B    12   2.5  7/  3.90 258 ICQ XX DRE01")
    #expect(ICQ.designation("12P") == " 12")
    #expect(ICQ.designation("12P/Pons-Brooks") == " 12")
    #expect(ICQ.designation("P/2010 H2") == "  P2010H2 ")
    #expect(ICQ.magnitude("[12") == "[12.0 ")
    #expect(ICQ.magnitude("bright") == nil)
}

@Test func aavsoFileFollowsTheManualExample() throws {
    let a = try entry("SS Cyg", "2008-08-24T14:57:41Z", [":REPORT:": "variable", ":MAGNITUDE:": "<11.1", ":COMMENT_CODE:": "U", ":COMPARISON:": "110 113", ":CHART:": "070613"], notes: "Partly cloudy, low")
    let b = try entry("SS Cyg", "2008-08-25T14:57:41Z", [":REPORT:": "variable", ":MAGNITUDE:": "10.9", ":COMPARISON:": "110"])
    let skipped = try entry("M31", "2008-08-25T15:00:00Z", [:])
    let lines = AAVSOVisual.file([b, skipped, a], observerCode: "tst01", software: "Moonrise 5.6.0").split(separator: "\n")
    #expect(lines.prefix(6) == ["#TYPE=VISUAL", "#OBSCODE=TST01", "#SOFTWARE=Moonrise 5.6.0", "#DELIM=,", "#DATE=JD", "#OBSTYPE=Visual"])
    #expect(lines[7] == "SS CYG,2454703.1234,<11.1,U,110,113,070613,Partly cloudy; low")
    #expect(lines[8] == "SS CYG,2454704.1234,10.9,na,110,na,na,na")
    #expect(lines.count == 9)
}

@Test func imoSessionAndRates() throws {
    let o = try entry("Orionids", "2026-10-21T09:00:00Z", [
        ":REPORT:": "meteors", ":MINUTES:": "90", ":LIMITING_MAG:": "6.2", ":CLOUD:": "20", ":COUNTS:": "ori 14, SPO 5", ":ELEVATION:": "120",
    ])
    let (sessions, rates) = IMOReport.files([o], observerName: "A. Observer", defaultCountry: "Australia")
    #expect(sessions == "session_id;observer_name;latitude;longitude;elevation;country;location_name\n1;A. Observer;-27.7800;152.7300;0.120;Australia;Peak Crossing\n")
    #expect(rates.split(separator: "\n") == [
        "rate_id;session_id;shower;period_start;period_end;freq;lim_magn;t_eff;f",
        "1;1;ORI;2026-10-21 09:00:00;2026-10-21 10:30:00;14;6.20;1.500;1.25",
        "2;1;SPO;2026-10-21 09:00:00;2026-10-21 10:30:00;5;6.20;1.500;1.25",
    ])
}
