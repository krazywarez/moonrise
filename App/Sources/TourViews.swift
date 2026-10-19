import Library
import SwiftUI

/// The tours, starting with the one for this month.
struct TourPicker: View {
    var onPick: (Tour) -> Void
    @Environment(\.dismiss) private var dismiss

    private let ink = Color(red: 0.95, green: 0.95, blue: 0.93)
    private let accent = Color(red: 0.88, green: 0.24, blue: 0.19)
    private let month = Calendar.current.component(.month, from: .now)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Guided tours").font(.title.weight(.medium))
                    Rectangle().fill(accent).frame(width: 48, height: 5).padding(.top, 8).padding(.bottom, 12)
                    Text("A walk around the evening sky, one sight at a time. The view turns to each stop and marks what to look for. Best outside after dark, but they work anywhere.")
                        .font(.subheadline).foregroundStyle(ink.opacity(0.75))
                        .padding(.bottom, 20)
                    ForEach(Tour.ordered(month: month)) { tour in card(tour) }
                }
                .padding(20)
                .readableWidth()
            }
            .background(Color.black.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .foregroundStyle(ink)
        .tint(accent)
    }

    private func card(_ tour: Tour) -> some View {
        let now = tour.months.contains(month)
        return Button {
            onPick(tour)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if now {
                        Text("THIS MONTH").font(.caption2.weight(.bold)).tracking(0.8)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(accent, in: RoundedRectangle(cornerRadius: 3))
                    }
                    Text(tour.title).font(.caption.weight(.medium)).foregroundStyle(ink.opacity(0.7))
                    Spacer()
                    Text("\(tour.steps.count) stops").font(.caption).foregroundStyle(ink.opacity(0.6))
                }
                Text(tour.steps.prefix(4).map(\.title).joined(separator: " · ") + (tour.steps.count > 4 ? " …" : ""))
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.leading)
                Text(tour.intro).font(.footnote).foregroundStyle(ink.opacity(0.75)).multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text("Start tour").font(.subheadline.weight(.semibold))
                    Image(systemName: "arrow.right").font(.footnote.weight(.semibold))
                }
                .foregroundStyle(now ? accent : ink.opacity(0.8))
                .padding(.top, 2)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ink.opacity(now ? 0.09 : 0.05), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(now ? accent.opacity(0.6) : ink.opacity(0.1), lineWidth: now ? 1 : 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 14)
        .accessibilityHint("Starts the tour")
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
