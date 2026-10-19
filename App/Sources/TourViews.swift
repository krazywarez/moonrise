import Library
import SwiftUI

/// The tours, starting with the one for this month.
struct TourPicker: View {
    var onPick: (Tour) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(Tour.ordered(month: Calendar.current.component(.month, from: .now))) { tour in
                Button {
                    onPick(tour)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tour.title).font(.body.weight(.medium))
                        Text(tour.intro).font(.footnote).foregroundStyle(.secondary)
                        Text("\(tour.steps.count) stops").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Guided tours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

/// One stop of a tour, with back, next and a link to the Library page.
struct TourCard: View {
    var tour: Tour
    @Binding var step: Int
    /// Whether the target is below the horizon at the time shown.
    var belowHorizon: Bool
    var ink: Color
    var background: Color
    var onOpen: (LibraryPage) -> Void
    var onEnd: () -> Void

    var body: some View {
        let s = tour.steps[step]
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(tour.title) · \(step + 1) of \(tour.steps.count)").font(.caption2).dimmed(0.7)
                Spacer()
                Button("End tour", action: onEnd).font(.caption.weight(.medium))
            }
            Text(s.title).font(.headline)
            Text(s.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            if belowHorizon {
                Text("Below your horizon at this time. Try later in the evening or another month.").font(.footnote).dimmed(0.7)
            }
            HStack {
                if step > 0 {
                    Button { step -= 1 } label: { Label("Back", systemImage: "chevron.left") }
                }
                Spacer()
                if let page = s.libraryPage {
                    Button("Read more") { onOpen(page) }
                    Spacer()
                }
                if step < tour.steps.count - 1 {
                    Button { step += 1 } label: { Label("Next", systemImage: "chevron.right").labelStyle(.titleAndIcon) }
                }
            }
            .font(.subheadline.weight(.medium))
            .padding(.top, 2)
        }
        .padding(16)
        .background(background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(ink.opacity(0.15), lineWidth: 0.5))
        .foregroundStyle(ink)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}
