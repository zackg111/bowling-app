import SwiftUI
import SwiftData

@main
struct BowlingLeagueApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Bowler.self, Night.self, Entry.self])
    }
}
