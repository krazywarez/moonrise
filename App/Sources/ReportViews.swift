import ObservingLog
import SwiftUI

/// Fields for an IMO, COBS or AAVSO report, stored as Org properties on the entry.
struct ReportFields: View {
    @Binding var observation: Observation

    private func field(_ label: String, _ key: String, prompt: String = "", keyboard: UIKeyboardType = .default) -> some View {
        TextField(label, text: Binding { observation[property: key] } set: { observation[property: key] = $0 }, prompt: Text(prompt))
            .keyboardType(keyboard)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
    }

    var body: some View {
        Section {
            Picker("Report", selection: $observation.report) {
                Text("None").tag(ReportKind?.none)
                Text("Variable star (AAVSO)").tag(ReportKind?.some(.variable))
                Text("Comet (COBS)").tag(ReportKind?.some(.comet))
                Text("Meteor count (IMO)").tag(ReportKind?.some(.meteors))
            }
            switch observation.report {
            case .variable:
                field("Star", ":DESIGNATION:", prompt: observation.object)
                field("Magnitude", ":MAGNITUDE:", prompt: "10.9, or <11.1 if fainter")
                field("Comparison stars", ":COMPARISON:", prompt: "110 113")
                field("Chart", ":CHART:", prompt: "X12345ABC")
                field("Comment code", ":COMMENT_CODE:", prompt: "Optional, e.g. B")
            case .comet:
                field("Comet", ":DESIGNATION:", prompt: "C/2023 A3 or 12P")
                field("Magnitude", ":MAGNITUDE:", prompt: "7.8; 7.8: if unsure; [12.0 not seen")
                field("Method", ":METHOD:", prompt: "S, M, B or I")
                field("Reference", ":REFERENCE:", prompt: "Comparison catalogue, e.g. TK")
                field("Aperture, cm", ":APERTURE:", keyboard: .decimalPad)
                field("Instrument", ":INSTRUMENT:", prompt: "B, L, R, T or E")
                field("Focal ratio", ":FOCAL_RATIO:", keyboard: .decimalPad)
                field("Magnification", ":POWER:", keyboard: .numberPad)
                field("Coma, arcmin", ":COMA:", keyboard: .decimalPad)
                field("DC", ":DC:", prompt: "0–9")
                field("Tail, degrees", ":TAIL:", keyboard: .decimalPad)
                field("Tail PA, degrees", ":PA:", keyboard: .numberPad)
            case .meteors:
                field("Minutes watched", ":MINUTES:", keyboard: .numberPad)
                field("Limiting magnitude", ":LIMITING_MAG:", keyboard: .decimalPad)
                field("Cloud, % of field", ":CLOUD:", keyboard: .numberPad)
                field("Counts", ":COUNTS:", prompt: "ORI 12 SPO 4")
                field("Elevation, m", ":ELEVATION:", keyboard: .numberPad)
                field("Country", ":COUNTRY:", prompt: Locale.current.region.flatMap { Locale.current.localizedString(forRegionCode: $0.identifier) } ?? "")
            case nil:
                EmptyView()
            }
        } header: {
            Text("Report")
        } footer: {
            switch observation.report {
            case .variable: Text("Comparison stars are the labels on the AAVSO chart, magnitude × 10.")
            case .comet: Text("ICQ codes, as COBS uses them. S: Sidgwick, M: Morris, B: Bobrovnikoff, I: in-out. B: binoculars, L: reflector, R: refractor, T: Schmidt-Cassegrain, E: naked eye.")
            case .meteors: Text("The time above is when counting started. Counts are IAU shower codes and numbers; SPO for sporadics.")
            case nil: Text("Adds the fields an IMO, COBS or AAVSO report needs.")
            }
        }
    }
}

/// Writes the AAVSO, COBS and IMO files for the entries marked with a report.
struct ReportExportSheet: View {
    var log: [Observation]
    @AppStorage("aavsoCode") private var aavsoCode = ""
    @AppStorage("icqCode") private var icqCode = ""
    @AppStorage("imoName") private var imoName = ""
    @Environment(\.dismiss) private var dismiss

    private var software: String { "Moonrise \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")" }

    private func count(_ k: ReportKind) -> Int { log.filter { $0.report == k }.count }

    private func write(_ name: String, _ text: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: name)
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Observer code", text: $aavsoCode).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    if !aavsoCode.isEmpty {
                        ShareLink(item: write("aavso-visual.txt", AAVSOVisual.file(log, observerCode: aavsoCode, software: software))) {
                            Label("AAVSO visual file", systemImage: "doc.text")
                        }
                    }
                } header: {
                    Text("Variable stars, \(count(.variable))")
                } footer: {
                    Text("Upload with WebObs › Upload a file at aavso.org.")
                }
                Section {
                    TextField("ICQ observer code", text: $icqCode).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    if !icqCode.isEmpty {
                        ShareLink(item: write("cobs-icq.txt", ICQ.file(log, observerCode: icqCode))) {
                            Label("ICQ file for COBS", systemImage: "doc.text")
                        }
                    }
                } header: {
                    Text("Comets, \(count(.comet))")
                } footer: {
                    Text("For import on cobs.si as ICQ format. COBS issues ICQ observer codes.")
                }
                Section {
                    TextField("Observer name", text: $imoName)
                    if !imoName.isEmpty {
                        let region = Locale.current.region.flatMap { Locale(identifier: "en_US").localizedString(forRegionCode: $0.identifier) } ?? ""
                        let files = IMOReport.files(log, observerName: imoName, defaultCountry: region)
                        ShareLink(items: [write("imo-sessions.csv", files.sessions), write("imo-rates.csv", files.rates)]) {
                            Label("IMO session and rate files", systemImage: "doc.text")
                        }
                    }
                } header: {
                    Text("Meteor counts, \(count(.meteors))")
                } footer: {
                    Text("Semicolon-separated CSV in the IMO Visual Meteor Database's columns. Times are UTC.")
                }
            }
            .navigationTitle("Export reports")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// A program's log as a US Letter PDF: each object with the date, place and equipment of its first observation.
enum ProgramLogPDF {
    static func write(_ program: ObservingProgram, progress: ProgramProgress?) -> URL {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792), margin: CGFloat = 54
        let width = page.width - 2 * margin
        let title: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 20, weight: .semibold)]
        let body: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10)]
        let bold: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10, weight: .semibold)]
        let small: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.darkGray]
        let url = FileManager.default.temporaryDirectory.appending(path: "\(program.title).pdf")
        let data = UIGraphicsPDFRenderer(bounds: page).pdfData { ctx in
            var y = page.height
            func draw(_ s: String, _ a: [NSAttributedString.Key: Any], x: CGFloat = margin, w: CGFloat = width) -> CGFloat {
                let text = NSAttributedString(string: s, attributes: a)
                let h = ceil(text.boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, context: nil).height)
                text.draw(with: CGRect(x: x, y: y, width: w, height: h), options: .usesLineFragmentOrigin, context: nil)
                return h
            }
            func room(_ h: CGFloat) {
                if y + h > page.height - margin { ctx.beginPage(); y = margin }
            }
            room(page.height)
            y += draw(program.title, title) + 4
            y += draw("\(progress?.count ?? 0) of \(program.objects.count) logged · \(Date.now.formatted(date: .long, time: .omitted))", small) + 14
            for o in program.objects {
                let logged = progress?.first[o.id]
                let detail = logged.map { [$0.date.formatted(date: .abbreviated, time: .shortened), $0.place, $0.equipment].filter { !$0.isEmpty }.joined(separator: " · ") } ?? ""
                room(30)
                let mark = draw(logged == nil ? "☐" : "☑", body, w: 14)
                let name = draw(o.name, bold, x: margin + 18, w: width * 0.4 - 18)
                let right = draw(detail, body, x: margin + width * 0.4, w: width * 0.6)
                y += max(mark, name, right)
                if !o.detail.isEmpty { y += draw(o.detail, small, x: margin + 18, w: width * 0.4 - 18) }
                y += 6
            }
        }
        try? data.write(to: url)
        return url
    }
}
