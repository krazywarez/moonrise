import SwiftUI

extension View {
    /// Keeps text columns to a comfortable reading width on iPad, centred.
    func readableWidth() -> some View {
        frame(maxWidth: 720).frame(maxWidth: .infinity)
    }
}
