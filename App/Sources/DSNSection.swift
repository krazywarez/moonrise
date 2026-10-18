import Feeds
import SwiftUI

/// Which Deep Space Network dishes are talking to which spacecraft right now.
struct DSNSection: View {
    var ink: Color
    var accent: Color
    @State private var status: DSNStatus?
    @State private var failed = false

    private var activeDishes: [DSNStatus.Dish] {
        status?.dishes.filter { !$0.links.isEmpty } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Deep Space Network now").font(.caption2.weight(.medium)).textCase(.uppercase).tracking(0.8).dimmed(0.6)
            if let status {
                ForEach(["Goldstone", "Madrid", "Canberra"], id: \.self) { station in
                    let dishes = activeDishes.filter { $0.station == station }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(station).font(.subheadline.weight(.medium))
                        if dishes.isEmpty {
                            Text("No spacecraft in contact").font(.footnote).dimmed(0.6)
                        }
                        ForEach(dishes) { dish in
                            ForEach(dish.links, id: \.self) { link in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(link.spacecraft).font(.footnote)
                                    Spacer()
                                    Text(describe(link, dish: dish)).font(.footnote.monospacedDigit()).dimmed(0.7)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Text("Updated \(status.updated.formatted(date: .omitted, time: .shortened)). Data: NASA/JPL Deep Space Network.")
                    .font(.caption2).dimmed(0.5)
            } else if failed {
                Text("Couldn't load Deep Space Network status.").font(.footnote).foregroundStyle(accent)
            } else {
                ProgressView().tint(ink)
            }
        }
        .task {
            while !Task.isCancelled {
                do { status = try await DSNStatus.fetch(); failed = false } catch { failed = status == nil }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func describe(_ l: DSNStatus.Link, dish: DSNStatus.Dish) -> String {
        var parts = [dish.name.replacingOccurrences(of: "DSS", with: "DSS ")]
        if l.receiving && l.sending { parts.append("two-way") } else if l.receiving { parts.append("receiving") } else { parts.append("sending") }
        if let r = l.downlinkRate { parts.append(rate(r)) }
        if let rt = l.roundTrip, rt > 60 { parts.append("round trip \(duration(rt))") }
        return parts.joined(separator: " · ")
    }

    private func rate(_ bps: Double) -> String {
        bps >= 1_000_000 ? String(format: "%.1f Mb/s", bps / 1_000_000) : bps >= 1000 ? String(format: "%.0f kb/s", bps / 1000) : String(format: "%.0f b/s", bps)
    }

    private func duration(_ s: Double) -> String {
        let h = Int(s / 3600), m = Int(s.truncatingRemainder(dividingBy: 3600) / 60)
        return h > 0 ? "\(h) h \(m) m" : "\(m) m"
    }
}
