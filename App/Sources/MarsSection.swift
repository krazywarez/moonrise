import Feeds
import SkyEngine
import SwiftUI

/// Local mean solar time and sol number at the active Mars rovers, ticking each second, and their latest raw images.
struct MarsSection: View {
    @State private var images: [MarsImage] = []
    @State private var shown: MarsImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mars now").font(.caption2.weight(.medium)).textCase(.uppercase).tracking(0.8).dimmed(0.6)
            Text("The time of day where NASA's two rovers are working, and their newest raw photos, usually a few hours old.")
                .font(.footnote).dimmed(0.75)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(MarsTime.Rover.active) { rover in
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rover.name).font(.subheadline.weight(.medium))
                                Text("\(rover.site) · sol \(MarsTime.sol(ctx.date, rover: rover))").font(.footnote).dimmed(0.7)
                            }
                            Spacer()
                            Text(MarsTime.format(hours: MarsTime.localMeanTime(ctx.date, eastLongitude: rover.longitude)))
                                .font(.title3.monospacedDigit())
                        }
                        .accessibilityElement(children: .combine)
                    }
                    strip(rover.name)
                }
            }
            Text("Local mean solar time. A Mars sol is 24 h 39 m 35 s. Raw images: NASA/JPL-Caltech.").font(.caption2).dimmed(0.5)
        }
        .task {
            // The rovers send a few batches a day; reuse a fetch from the last 30 minutes.
            if let cached: [MarsImage] = FeedMemo.get("mars", maxAge: 1800) { images = cached; return }
            if let fresh = try? await MarsImage.latest() { images = fresh; FeedMemo.set("mars", fresh) }
        }
        .sheet(item: $shown) { MarsImageView(image: $0) }
    }

    @ViewBuilder
    private func strip(_ rover: String) -> some View {
        let mine = images.filter { $0.rover == rover }
        if !mine.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(mine) { image in
                        Button { shown = image } label: {
                            RemoteImage(url: image.thumbnail, points: 130) { Color.white.opacity(0.06) }
                            .frame(width: 88, height: 88)
                            .clipped()
                        }
                        .accessibilityLabel("\(image.camera), sol \(image.sol)")
                    }
                }
            }
            .padding(.bottom, 6)
        }
    }
}

struct MarsImageView: View {
    var image: MarsImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    AsyncImage(url: image.image) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFit()
                        case .failure: Color.black.frame(height: 200).overlay(Text("Image unavailable").font(.caption).dimmed(0.6))
                        default: Color.black.frame(height: 300).overlay(ProgressView())
                        }
                    }
                    Text("\(image.rover) · \(image.camera) · sol \(image.sol)").font(.subheadline.weight(.medium))
                    Text(image.taken.formatted(date: .abbreviated, time: .shortened)).font(.footnote).dimmed(0.7)
                    Text("Raw, unprocessed image. Credit: \(image.credit).").font(.caption2).dimmed(0.55)
                }
                .padding(.horizontal, 16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
