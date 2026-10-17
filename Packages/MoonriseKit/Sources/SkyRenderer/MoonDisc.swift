import SwiftUI

/// The moon at a given phase, filling its frame.
public struct MoonDisc: View {
    public var fraction: Double
    public var waxing: Bool
    public var light: Color
    public var dark: Color

    public init(fraction: Double, waxing: Bool, light: Color = SkyStyle().moonLight, dark: Color = SkyStyle().moonDark) {
        self.fraction = fraction
        self.waxing = waxing
        self.light = light
        self.dark = dark
    }

    public var body: some View {
        Canvas { context, size in
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(dark))
            context.fill(Path.moonLit(center: c, radius: r, fraction: fraction, waxing: waxing), with: .color(light))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Moon \(Int((fraction * 100).rounded())) percent lit, \(waxing ? "waxing" : "waning")")
    }
}
