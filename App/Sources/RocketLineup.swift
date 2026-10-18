import Library
import SwiftUI

/// Every rocket in the Library drawn side by side at the same scale, tallest last.
struct RocketLineup: View {
    var highlight: String?
    var ink: Color
    var accent: Color

    private var rockets: [LibraryPage] {
        Library.pages(in: .rockets).filter { $0.drawing?.heightM != nil }.sorted { ($0.drawing?.heightM ?? 0) < ($1.drawing?.heightM ?? 0) }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Canvas { context, size in
                let tallest = rockets.compactMap(\.drawing?.heightM).max() ?? 1
                let scale = (size.height - 36) / tallest
                var x = 12.0
                for r in rockets {
                    let h = r.drawing!.heightM! * scale
                    let w = max((r.drawing?.diameterM ?? 3) * scale, 3)
                    let rect = CGRect(x: x, y: size.height - 24 - h, width: w, height: h)
                    let mine = r.id == highlight
                    var body = Path(roundedRect: rect, cornerRadius: w / 2)
                    body.addRect(rect.insetBy(dx: 0, dy: w / 2))
                    context.fill(body, with: .color(mine ? accent : ink.opacity(0.55)))
                    context.draw(Text(String(format: "%.0f m", r.drawing!.heightM!)).font(.caption2).foregroundStyle(ink.opacity(0.7)), at: CGPoint(x: x + w / 2, y: rect.minY - 8))
                    context.draw(Text(r.title).font(.caption2).foregroundStyle(mine ? accent : ink.opacity(0.8)), at: CGPoint(x: x + w / 2, y: size.height - 10))
                    x += max(w, 64) + 10
                }
                var ground = Path()
                ground.move(to: CGPoint(x: 0, y: size.height - 24))
                ground.addLine(to: CGPoint(x: size.width, y: size.height - 24))
                context.stroke(ground, with: .color(ink.opacity(0.4)), lineWidth: 0.5)
            }
            .frame(width: CGFloat(rockets.count) * 74 + 24)
        }
        .accessibilityElement()
        .accessibilityLabel("Rockets to scale: " + rockets.map { "\($0.title) \(Int($0.drawing!.heightM!)) metres" }.joined(separator: ", "))
    }
}
