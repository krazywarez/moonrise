import Library
import SwiftUI

/// Every rocket in the Library drawn side by side at the same scale, shortest first.
/// Each rocket is a column (height above, name below), so labels never overlap; tapping one opens its page.
struct RocketLineup: View {
    var highlight: String?
    var ink: Color
    var accent: Color

    private let column: CGFloat = 84
    private let top: CGFloat = 20
    private let bottom: CGFloat = 36
    private let axis: CGFloat = 40

    private var rockets: [LibraryPage] {
        Library.pages(in: .rockets).filter { $0.drawing?.heightM != nil }.sorted { ($0.drawing?.heightM ?? 0) < ($1.drawing?.heightM ?? 0) }
    }

    var body: some View {
        GeometryReader { geo in
            let tallest = rockets.compactMap(\.drawing?.heightM).max() ?? 1
            let scale = max(geo.size.height - top - bottom - 8, 40) / tallest
            // Ground: below the name (bottom - 6), the line and two 4-point gaps.
            let ground = geo.size.height - (bottom - 6) - 8.5
            ForEach(Array(stride(from: 25.0, through: tallest, by: 25)), id: \.self) { m in
                let y = ground - m * scale
                Path { p in p.move(to: CGPoint(x: axis, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y)) }
                    .stroke(ink.opacity(0.12), style: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
            }
            .accessibilityHidden(true)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(rockets) { r in
                            Group {
                                if r.id == highlight {
                                    rocketColumn(r, scale: scale)
                                } else {
                                    NavigationLink { LibraryPageView(page: r) } label: { rocketColumn(r, scale: scale) }
                                        .buttonStyle(.plain)
                                }
                            }
                            .id(r.id)
                        }
                    }
                    .padding(.leading, axis)
                    .padding(.trailing, 12)
                    .frame(minHeight: geo.size.height, alignment: .bottom)
                }
                .onAppear { if let highlight { proxy.scrollTo(highlight, anchor: .center) } }
            }
            // A fixed axis on the left that the rockets scroll beneath.
            ZStack(alignment: .topLeading) {
                Color.black.frame(width: axis)
                ForEach(Array(stride(from: 25.0, through: tallest, by: 25)), id: \.self) { m in
                    Text("\(Int(m)) m").font(.caption2.monospacedDigit()).foregroundStyle(ink.opacity(0.5))
                        .position(x: axis / 2, y: ground - m * scale)
                }
            }
            .frame(width: axis, height: geo.size.height)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rockets to scale")
    }

    private func rocketColumn(_ r: LibraryPage, scale: Double) -> some View {
        let d = r.drawing!
        let mine = r.id == highlight
        let h = d.heightM! * scale
        let w = max((d.diameterM ?? 3) * scale, 4)
        // Fins reach 0.35 × width past each side, so wide rockets get a wider column.
        let width = max(column, w * 1.7 + 14)
        return VStack(spacing: 4) {
            Text(String(format: "%.0f m", d.heightM!)).font(.caption2.monospacedDigit()).foregroundStyle(ink.opacity(0.7))
                .frame(height: top - 4)
            RocketShape()
                .fill(mine ? accent : ink.opacity(0.75))
                .frame(width: w, height: h)
            Rectangle().fill(ink.opacity(0.35)).frame(width: width, height: 0.5)
            Text(r.title).font(.caption2.weight(mine ? .semibold : .regular))
                .foregroundStyle(mine ? accent : ink.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: width - 6, height: bottom - 6, alignment: .top)
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(r.title), \(Int(d.heightM!)) metres")
    }
}

/// A generic rocket: ogive nose, straight body, small fins at the base. Drawn to the frame,
/// with fins reaching a little outside the body's width.
struct RocketShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let nose = min(h * 0.14, w * 2.4)
        let fin = min(h * 0.08, w * 1.2)
        let spread = w * 0.35
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + nose), control: CGPoint(x: rect.maxX, y: rect.minY + nose * 0.25))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - fin))
        p.addLine(to: CGPoint(x: rect.maxX + spread, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX - spread, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - fin))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + nose))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY + nose * 0.25))
        p.closeSubpath()
        return p
    }
}
