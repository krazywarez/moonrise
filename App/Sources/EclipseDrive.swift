import MapKit
import SkyEngine
import SwiftUI

/// The nearest place on land where the central phase lasts at least 95% of its centre-line length, with directions.
struct EclipseDrive: View {
    var path: EclipsePath
    var site: Observer
    var accent: Color
    @State private var found: (site: EclipseSite, item: MKMapItem)?
    @State private var inBand = false
    @State private var searched = false

    private var central: String { path.kind == "Total" ? "totality" : "the annular phase" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Getting to the path").font(.caption2.weight(.medium)).textCase(.uppercase).tracking(0.8).dimmed(0.6)
            if inBand {
                Text("You are within the band where \(central) lasts at least 95% as long as on the centre line.").font(.subheadline)
            } else if let (s, item) = found {
                Text("Nearest place with at least 95% of the centre-line duration: \(item.address?.shortAddress ?? item.name ?? "unnamed place"), \(Int(s.distanceKm.rounded())) km away in a straight line. \(central.prefix(1).uppercased() + central.dropFirst()) there lasts \(minutes(s.duration)); on the centre line, \(minutes(s.centerDuration)).")
                    .font(.subheadline)
                Button("Directions in Maps") {
                    item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                }
                .tint(accent)
                Text("Arrive the day before if you can: roads near the path fill up. Do not drive during the eclipse.")
                    .font(.footnote).dimmed(0.7)
            } else if searched {
                Text("No place on land within reach of the path could be found. Check your connection.").font(.footnote).dimmed(0.7)
            } else {
                ProgressView().tint(accent)
            }
        }
        .task(id: [(site.latitude * 10).rounded(), (site.longitude * 10).rounded()]) {
            found = nil
            inBand = false
            searched = false
            let path = path, site = site
            let candidates = await Task.detached { path.candidates(near: site) }.value
            if let first = candidates.first, first.distanceKm < 3, await Task.detached(operation: { path.site(first) }).value != nil {
                inBand = true
                return
            }
            // Nearest first, about one lookup a second. Offshore, Apple's geocoder names the sea and gives the country as
            // the city ("Alboran Sea, Spain"); on land the city is a locality.
            for c in candidates.prefix(40) {
                guard !Task.isCancelled else { return }
                guard let s = await Task.detached(operation: { path.site(c) }).value else { continue }
                if let request = MKReverseGeocodingRequest(location: CLLocation(latitude: c.latitude, longitude: c.longitude)),
                   let item = try? await request.mapItems.first, let a = item.addressRepresentations,
                   let region = a.regionName, let city = a.cityName, !city.isEmpty, city != region {
                    found = (s, item)
                    break
                }
                try? await Task.sleep(for: .seconds(1))
            }
            searched = true
        }
    }

    private func minutes(_ s: TimeInterval) -> String {
        let n = Int(s.rounded())
        return "\(n / 60) min \(n % 60) s"
    }
}
