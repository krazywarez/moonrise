import Answers
import SkyRenderer
import SwiftUI

/// Result view for Siri and Shortcuts, in the Today sheet's style: section label, hairline, label/value grid.
struct AnswerSnippet: View {
    var heading: String
    var lead: String?
    var rows: [AnswerRow]
    var footnote: String?
    var moon: (fraction: Double, waxing: Bool)?

    private let ink = Color(red: 0.95, green: 0.95, blue: 0.93)
    private let accent = Color(red: 0.88, green: 0.24, blue: 0.19)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading).font(.caption2.weight(.medium)).textCase(.uppercase).tracking(0.8).dimmed(0.6)
            if let lead { Text(lead).font(.subheadline) }
            Rectangle().fill(ink.opacity(0.25)).frame(height: 0.5)
            HStack(alignment: .center, spacing: 16) {
                if let moon { MoonDisc(fraction: moon.fraction, waxing: moon.waxing).frame(width: 52) }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    ForEach(rows, id: \.self) { row in
                        GridRow {
                            Text(row.label).dimmed(0.7)
                            Text(row.value).monospacedDigit().foregroundStyle(row.alert ? accent : ink)
                        }
                        .font(.subheadline)
                    }
                }
            }
            if let footnote {
                Rectangle().fill(ink.opacity(0.25)).frame(height: 0.5)
                Text(footnote).font(.caption2.monospacedDigit()).dimmed(0.6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .foregroundStyle(ink)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }
}
