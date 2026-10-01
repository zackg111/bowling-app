import SwiftUI
import SwiftData

@main
struct BowlingLeagueApp: App {
    let container: ModelContainer

    /// The iCloud container the league syncs through.
    static let cloudContainer = "iCloud.com.goodnite.bowl"

    init() {
        container = Self.makeContainer()
        let context = container.mainContext

        // Shots from the Apple Watch are saved as they arrive, no tap needed.
        ShotLink.shared.onReceive = { Shot.receive($0, in: context) }
        // So are games scored on the watch.
        ShotLink.shared.onReceiveGame = { WatchScoring.receive($0, in: context) }
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

    /// The league database, kept in the user's private iCloud so it's backed
    /// up, comes back on a new phone, and stays in step on their other devices.
    /// Without iCloud it keeps working on this device and syncs once signed in.
    private static func makeContainer() -> ModelContainer {
        backUpStore()
        let schema = Schema([Bowler.self, Night.self, Entry.self, Shot.self, Ball.self])
        let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .private(cloudContainer))
        if let container = try? ModelContainer(for: schema, configurations: cloud) {
            return container
        }
        // iCloud couldn't be set up (e.g. missing entitlement): same file, this device only.
        let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: local)
        } catch {
            fatalError("Couldn't open the league database: \(error)")
        }
    }

    /// Before a new build first opens the database (and possibly upgrades it),
    /// copies it to Application Support/Backups, so an upgrade gone wrong can't
    /// cost anyone their league. Keeps only the latest copy.
    private static func backUpStore() {
        let files = FileManager.default
        guard let support = files.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              files.fileExists(atPath: support.appending(path: "default.store").path()) else { return }
        let info = Bundle.main.infoDictionary
        let build = "\(info?["CFBundleShortVersionString"] as? String ?? "0")-\(info?["CFBundleVersion"] as? String ?? "0")"
        let backups = support.appending(path: "Backups")
        let folder = backups.appending(path: build)
        guard !files.fileExists(atPath: folder.path()) else { return }

        try? files.removeItem(at: backups)
        try? files.createDirectory(at: folder, withIntermediateDirectories: true)
        // The database, its journal, and the folder photos are stored in.
        for name in ["default.store", "default.store-wal", "default.store-shm", ".default_SUPPORT"] {
            let source = support.appending(path: name)
            if files.fileExists(atPath: source.path()) {
                try? files.copyItem(at: source, to: folder.appending(path: name))
            }
        }
    }
}
