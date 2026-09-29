import SwiftUI

@main
struct BowlingWatchApp: App {
    init() {
        ShotLink.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
