import SwiftUI

/// First launch: what the app does and why it asks for location, before iOS asks.
struct OnboardingScreen: View {
    @AppStorage(SettingsKey.onboarded) private var onboarded = false
    @AppStorage(SettingsKey.locationMode) private var locationMode = "current"
    @AppStorage(SettingsKey.cityName) private var cityName = "Chicago"
    @AppStorage(SettingsKey.cityLatitude) private var cityLatitude = 41.878
    @AppStorage(SettingsKey.cityLongitude) private var cityLongitude = -87.630
    @State private var choosingCity = false

    private let ink = Color(red: 0.95, green: 0.95, blue: 0.93)
    private let accent = Color(red: 0.88, green: 0.24, blue: 0.19)
    private let background = Color.black

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Text("Moonrise").font(.largeTitle.weight(.medium))
            Rectangle().fill(accent).frame(width: 48, height: 5).padding(.top, 10).padding(.bottom, 24)
            VStack(alignment: .leading, spacing: 14) {
                Text("The sky above you tonight, the Sun today, launches, the solar system, and a library of everything up there.")
                Text("To draw the sky for where you are, Moonrise uses your location. It is used on this device to work out positions and is not sent to us or anyone else.")
                    .foregroundStyle(ink.opacity(0.75))
            }
            .font(.body)
            Spacer()
            if choosingCity {
                Picker("City", selection: $cityName) {
                    ForEach(City.all) { Text($0.name).tag($0.name) }
                }
                .pickerStyle(.wheel)
                .frame(height: 140)
                button("Use \(cityName)", filled: true) {
                    if let c = City.all.first(where: { $0.name == cityName }) {
                        cityLatitude = c.latitude
                        cityLongitude = c.longitude
                    }
                    locationMode = "city"
                    onboarded = true
                }
            } else {
                button("Use my location", filled: true) {
                    locationMode = "current"
                    onboarded = true
                }
                button("Choose a city instead", filled: false) { choosingCity = true }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .foregroundStyle(ink)
        .background(background.ignoresSafeArea())
    }

    private func button(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(filled ? Color.black : ink)
                .background(filled ? ink : .clear, in: .rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ink.opacity(filled ? 0 : 0.5), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(.top, 10)
    }
}
