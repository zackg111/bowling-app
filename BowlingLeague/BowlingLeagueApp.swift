import SwiftUI
import SwiftData

@main
struct BowlingLeagueApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Bowler.self, Night.self, Entry.self, Shot.self)
        } catch {
            fatalError("Couldn't open the league database: \(error)")
        }

        let context = container.mainContext
        SeedData.loadOnFirstLaunch(into: context)

        // Shots from the Apple Watch are saved as they arrive, no tap needed.
        ShotLink.shared.onReceive = { Shot.receive($0, in: context) }
        ShotLink.shared.activate()

        #if DEBUG
        // Launch with -SimulateWatchShot to test the phone side without a watch.
        if ProcessInfo.processInfo.arguments.contains("-SimulateWatchShot") {
            let shot = ShotMetrics(date: .now, releaseSpeedMPH: .random(in: 14...18), wristRotationRPM: .random(in: 250...400))
            Task { @MainActor in ShotLink.shared.onReceive?(shot) }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
