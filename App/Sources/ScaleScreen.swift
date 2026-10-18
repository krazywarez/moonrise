import Library
import SwiftUI

/// Bodies, stars, nebulae and galaxies at true relative size. Zoom with the slider or a pinch;
/// objects between 1/100 of the shown width and the full width are drawn side by side.
struct ScaleScreen: View {
    var ink: Color
    var accent: Color
    /// log10 of the width shown, in metres.
    @State private var exponent = 7.4
    @State private var pinchStart: Double?
    @State private var selected: LibraryPage?

    private let range = 2.5...27.0

    private var width: Double { pow(10, exponent) }

    /// The width to two significant figures, for the label.
    private var roundedWidth: Double {
        let p = pow(10, floor(exponent) - 1)
        return (width / p).rounded() * p
    }

    private var shown: [ScaleObject] {
        Library.scaleObjects.filter { $0.meters <= width && $0.meters >= width / 100 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Width shown: \(Library.formatSize(roundedWidth))").font(.subheadline.monospacedDigit()).dimmed(0.8)
            GeometryReader { geo in
                let side = geo.size.width
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 16) {
                        if shown.isEmpty {
                            Text("Nothing in the Library at this scale.").font(.footnote).dimmed(0.6)
                        }
                        ForEach(shown) { o in
                            let d = max(o.meters / width * side, 2)
                            Button {
                                selected = o.page.flatMap { Library.page(id: $0) }
                            } label: {
                                VStack(spacing: 6) {
                                    Circle().fill(o.page == nil ? ink.opacity(0.18) : ink.opacity(0.55))
                                        .overlay(Circle().stroke(ink.opacity(0.5), lineWidth: 0.5))
                                        .frame(width: d, height: d)
                                    Text(o.name).font(.caption2).lineLimit(1)
                                    Text(Library.formatSize(o.meters)).font(.caption2.monospacedDigit()).dimmed(0.6)
                                }
                                .frame(minWidth: 64)
                            }
                            .buttonStyle(.plain)
                            .disabled(o.page == nil)
                            .accessibilityLabel("\(o.name), \(Library.formatSize(o.meters))")
                        }
                    }
                    .frame(minHeight: geo.size.height, alignment: .bottom)
                    .padding(.horizontal, 4)
                }
                .defaultScrollAnchor(.trailing)
                .scrollClipDisabled()
            }
            .frame(maxHeight: .infinity)
            .gesture(MagnifyGesture()
                .onChanged { g in
                    if pinchStart == nil { pinchStart = exponent }
                    exponent = min(max(pinchStart! - log10(g.magnification), range.lowerBound), range.upperBound)
                }
                .onEnded { _ in pinchStart = nil })
            Slider(value: $exponent, in: range) { Text("Width shown") } minimumValueLabel: {
                Image(systemName: "plus.magnifyingglass")
            } maximumValueLabel: {
                Image(systemName: "minus.magnifyingglass")
            }
            .accessibilityValue(Library.formatSize(roundedWidth))
            Text("The slider spans 300 m to the observable universe; each tenth of it is a factor of ten. Pinch to zoom. Objects without a Library page are drawn faint.")
                .font(.caption2).dimmed(0.5)
        }
        .padding(20)
        .foregroundStyle(ink)
        .tint(accent)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Scale of the universe")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { page in NavigationStack { LibraryPageView(page: page) } }
    }
}
