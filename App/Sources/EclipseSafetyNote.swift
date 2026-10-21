import SwiftUI

/// Eye safety for eclipse day, after the AAS Solar Eclipse Task Force and NASA.
let eclipseSafetyLines = [
    "Look at the Sun only through eclipse glasses or a handheld viewer that meets ISO 12312-2. Sunglasses, even very dark ones, are not safe.",
    "Take them off only during totality, inside the path, once no sunlight shows through them. Put them back on as soon as the Sun starts to reappear. Partial and annular eclipses never have a safe moment without them.",
    "Cameras, binoculars and telescopes need a solar filter on the front. Never look through them while wearing eclipse glasses.",
    "Damage to the eye is painless and shows only hours later.",
]

/// Shown once before the first countdown or rehearsal, and from the eclipse screen.
struct EclipseSafetyNote: View {
    /// A countdown or rehearsal starts when the note closes.
    var starting: Bool
    @Environment(\.dismiss) private var dismiss

    private let ink = Color(red: 0.95, green: 0.95, blue: 0.93)
    private let accent = Color(red: 0.88, green: 0.24, blue: 0.19)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(eclipseSafetyLines, id: \.self) { Text($0) }
                    Text("Check your viewers first and throw away any that are scratched, torn or coming loose.")
                    Text("Cue times can be off by a few seconds, more near the edge of the path. If sunlight still shows through your glasses, keep them on whatever a cue says.")
                    Link(destination: URL(string: "https://eclipse.aas.org/eye-safety")!) {
                        Text("Eye safety from the American Astronomical Society").multilineTextAlignment(.leading).foregroundStyle(accent)
                    }
                }
                .padding(20)
                .readableWidth()
            }
            .background(Color.black.ignoresSafeArea())
            .foregroundStyle(ink)
            .navigationTitle("Eye safety")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(starting ? "Continue" : "Done") { dismiss() } } }
        }
        .interactiveDismissDisabled(starting)
    }
}
