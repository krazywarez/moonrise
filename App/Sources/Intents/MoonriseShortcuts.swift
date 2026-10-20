import AppIntents

/// Siri phrases. Each must contain the app's name; at most 10 shortcuts.
struct MoonriseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MoonPhaseIntent(),
            phrases: ["Moon phase in \(.applicationName)", "How full is the moon in \(.applicationName)", "\(.applicationName) moon phase"],
            shortTitle: "Moon Phase",
            systemImageName: "moonphase.waxing.gibbous"
        )
        AppShortcut(
            intent: TonightIntent(),
            phrases: ["What's in the sky tonight in \(.applicationName)", "What can I see tonight in \(.applicationName)", "\(.applicationName) tonight"],
            shortTitle: "Tonight's Sky",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: NextPassIntent(),
            phrases: ["When is the next ISS pass in \(.applicationName)", "Next pass of \(\.$satellite) in \(.applicationName)", "When can I see \(\.$satellite) in \(.applicationName)"],
            shortTitle: "Next Pass",
            systemImageName: "dot.radiowaves.up.forward"
        )
        AppShortcut(
            intent: NextLaunchIntent(),
            phrases: ["When's the next launch in \(.applicationName)", "Next rocket launch in \(.applicationName)"],
            shortTitle: "Next Launch",
            systemImageName: "airplane.departure"
        )
        AppShortcut(
            intent: SpaceWeatherIntent(),
            phrases: ["Aurora chance in \(.applicationName)", "What's the Kp index in \(.applicationName)", "Space weather in \(.applicationName)"],
            shortTitle: "Aurora and Kp",
            systemImageName: "sun.max"
        )
        AppShortcut(
            intent: ProbeDistanceIntent(),
            phrases: ["How far is \(\.$probe) in \(.applicationName)", "How far away is \(\.$probe) in \(.applicationName)"],
            shortTitle: "Probe Distance",
            systemImageName: "antenna.radiowaves.left.and.right"
        )
        AppShortcut(
            intent: LookUpIntent(),
            phrases: ["Look up \(\.$page) in \(.applicationName)", "Look up something in \(.applicationName)"],
            shortTitle: "Look Up",
            systemImageName: "books.vertical"
        )
        AppShortcut(
            intent: ShowInSkyIntent(),
            phrases: ["Show \(\.$target) in the sky with \(.applicationName)", "Find \(\.$target) in \(.applicationName)", "Show something in the sky with \(.applicationName)"],
            shortTitle: "Show in Sky",
            systemImageName: "scope"
        )
        AppShortcut(
            intent: SearchLibraryIntent(),
            phrases: ["Search the \(.applicationName) Library", "Search \(.applicationName)"],
            shortTitle: "Search Library",
            systemImageName: "magnifyingglass"
        )
    }
}
