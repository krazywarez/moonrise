import SkyEngine
import SwiftUI

/// Local mean solar time and sol number at the active Mars rovers, ticking each second.
struct MarsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mars now").font(.caption2.weight(.medium)).textCase(.uppercase).tracking(0.8).dimmed(0.6)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(MarsTime.Rover.active) { rover in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rover.name).font(.subheadline.weight(.medium))
                                Text("\(rover.site) · sol \(MarsTime.sol(ctx.date, rover: rover))").font(.footnote).dimmed(0.7)
                            }
                            Spacer()
                            Text(MarsTime.format(hours: MarsTime.localMeanTime(ctx.date, eastLongitude: rover.longitude)))
                                .font(.title3.monospacedDigit())
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Text("Local mean solar time. A Mars sol is 24 h 39 m 35 s.").font(.caption2).dimmed(0.5)
        }
    }
}
