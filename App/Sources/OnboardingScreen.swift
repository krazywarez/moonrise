import SkyRenderer
import SwiftUI
import UserNotifications

/// First launch: what the app does, optional alerts, and location. Can be shown again from Settings.
struct OnboardingScreen: View {
    @AppStorage(SettingsKey.onboarded) private var onboarded = false
    @AppStorage(SettingsKey.locationMode) private var locationMode = "current"
    @AppStorage(SettingsKey.cityName) private var cityName = "Chicago"
    @AppStorage(SettingsKey.cityLatitude) private var cityLatitude = 41.878
    @AppStorage(SettingsKey.cityLongitude) private var cityLongitude = -87.630
    @AppStorage(SettingsKey.dailySummary) private var dailySummary = false
    @State private var alerts = AuroraAlerts.shared
    @State private var page = 0
    @State private var choosingCity = false
    @State private var notificationsDenied = false

    private let ink = Color(red: 0.95, green: 0.95, blue: 0.93)
    private let accent = Color(red: 0.88, green: 0.24, blue: 0.19)
    private let pages = 5

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if page < pages - 1 {
                    Button("Skip") { withAnimation { page = pages - 1 } }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ink.opacity(0.7))
                        .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 24)
            .frame(height: 44)

            TabView(selection: $page) {
                welcome.tag(0)
                sky.tag(1)
                beyond.tag(2)
                loop.tag(3)
                location.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 6) {
                ForEach(0..<pages, id: \.self) { i in
                    Capsule().fill(i == page ? ink : ink.opacity(0.25)).frame(width: i == page ? 18 : 6, height: 6)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: page)
            .accessibilityHidden(true)
            .padding(.bottom, 16)

            if page < pages - 1 {
                button("Continue", filled: true) { withAnimation { page += 1 } }
                    .padding(.horizontal, 24)
            }
        }
        .padding(.bottom, 24)
        .foregroundStyle(ink)
        .background(Color.black.ignoresSafeArea())
        .tint(accent)
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            MoonDisc(fraction: 0.55, waxing: true)
                .frame(width: 96, height: 96)
                .padding(.bottom, 28)
                .accessibilityHidden(true)
            Text("Moonrise").font(.largeTitle.weight(.medium))
            Rectangle().fill(accent).frame(width: 48, height: 5).padding(.vertical, 14)
            Text("The night sky, the Sun and spaceflight in one place: what's up tonight, what's coming, and the story behind it.")
                .font(.title3)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private var sky: some View {
        pageLayout {
            heading("Your sky, tonight", "The Sky tab shows the stars and planets above you right now.")
            point("hand.tap", "Tap anything", "A star, planet or constellation shows what it is and opens its Library page.")
            point("hand.draw", "Look around", "Drag to turn and pinch to zoom, or point your phone at the sky from the Explore menu.")
            point("clock", "Change the time", "Slide along the bottom to see the sky later tonight.")
            point("figure.walk", "Take a tour", "Guided tours walk you through the brightest sights of the season, one at a time.")
        }
    }

    private var beyond: some View {
        pageLayout {
            heading("Beyond tonight", "Four more tabs, each answering a different question.")
            point("circle.circle", "System", "Where the planets and the spacecraft heading out of the solar system are, from 1958 to 2050.")
            point("sun.max", "Sun", "Today's Sun from NASA, solar flares, and where the aurora may be visible tonight.")
            point("airplane.departure", "News & launches", "Upcoming rocket launches with countdowns, and the day's space news.")
            point("books.vertical", "Library", "370 illustrated pages on planets, stars, missions, rockets and more.")
        }
    }

    private var loop: some View {
        pageLayout {
            heading("Stay in the loop", "The sky changes every night. Moonrise can tell you when something is worth stepping outside for. All optional; change them any time in Settings.")
            toggle("Daily summary", "Each evening: the Moon, the planets up, the best satellite pass and any events. Worked out on your phone.", isOn: Binding(
                get: { dailySummary },
                set: { on in Task {
                    if on, !(await permission()) { return }
                    dailySummary = on
                } }
            ))
            toggle("Aurora alerts", "When the aurora may be visible from your area at night.", isOn: Binding(
                get: { alerts.enabled },
                set: { on in Task { await alerts.setEnabled(on) } }
            ))
            toggle("Space news", "Three of the day's headlines at 9 a.m.", isOn: Binding(
                get: { alerts.news },
                set: { on in Task { await alerts.setNews(on) } }
            ))
            if notificationsDenied || alerts.status != nil {
                Text("Notifications are off for Moonrise. You can turn them on in the Settings app.")
                    .font(.footnote).foregroundStyle(accent)
            }
        }
    }

    private var location: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Where are you?", "Moonrise draws the sky for where you are. Your location is used on this phone to work out positions and is never sent to us or anyone else.")
            Spacer(minLength: 0)
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
                button("Back", filled: false) { choosingCity = false }
            } else {
                // App Review 5.1.1(iv): the button before the system prompt must not direct the choice.
                button("Continue", filled: true) {
                    locationMode = "current"
                    onboarded = true
                }
                button("Choose a city instead", filled: false) { choosingCity = true }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    // MARK: Parts

    private func pageLayout(@ViewBuilder _ content: () -> some View) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func heading(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title.weight(.medium))
            Rectangle().fill(accent).frame(width: 48, height: 5)
            Text(text).font(.body).foregroundStyle(ink.opacity(0.75))
        }
        .padding(.bottom, 24)
    }

    private func point(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3).frame(width: 30).foregroundStyle(accent).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(ink.opacity(0.75))
            }
        }
        .padding(.bottom, 18)
        .accessibilityElement(children: .combine)
    }

    private func toggle(_ title: String, _ text: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(ink.opacity(0.75))
            }
        }
        .padding(.bottom, 18)
    }

    private func permission() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        notificationsDenied = !granted
        return granted
    }

    private func button(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(filled ? Color.black : ink)
                .background(filled ? ink : .clear, in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ink.opacity(filled ? 0 : 0.5), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(.top, 10)
    }
}
