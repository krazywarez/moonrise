import SwiftUI

extension EnvironmentValues {
    /// True while the Sky tab draws in night mode; dimmed text stays above 90% so red text keeps AA contrast.
    @Entry var nightMode = false
}

/// Secondary text: dimmed by `opacity`, but never below 90% in night mode and not at all with Increase Contrast.
struct Dimmed: ViewModifier {
    var opacity: Double
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.nightMode) private var night

    func body(content: Content) -> some View {
        content.opacity(contrast == .increased ? 1 : night ? max(opacity, 0.9) : opacity)
    }
}

extension View {
    func dimmed(_ opacity: Double) -> some View { modifier(Dimmed(opacity: opacity)) }
}
