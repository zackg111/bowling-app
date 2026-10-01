import CloudKit
import CoreData
import Observation

/// Watches the league's iCloud sync (SwiftData runs it through Core Data's
/// CloudKit mirroring), so restoring on a new phone can show its progress.
@Observable
final class CloudSyncMonitor {
    static let shared = CloudSyncMonitor()

    /// Bringing changes down from iCloud right now.
    private(set) var isImporting = false
    /// Imports finished since the app opened.
    private(set) var importsFinished = 0
    private(set) var lastError: String?
    /// Last time changes came down from iCloud, on this device.
    private(set) var lastSynced: Date? = UserDefaults.standard.object(forKey: "lastICloudImport") as? Date

    @ObservationIgnored private var watching: Task<Void, Never>?

    func start() {
        guard watching == nil else { return }
        watching = Task {
            let events = NotificationCenter.default.notifications(named: NSPersistentCloudKitContainer.eventChangedNotification)
            for await note in events {
                guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                        as? NSPersistentCloudKitContainer.Event,
                      event.type == .import else { continue }
                if let end = event.endDate {
                    isImporting = false
                    if event.succeeded {
                        importsFinished += 1
                        lastError = nil
                        lastSynced = end
                        UserDefaults.standard.set(end, forKey: "lastICloudImport")
                    } else {
                        lastError = event.error?.localizedDescription
                    }
                } else {
                    isImporting = true
                }
            }
        }
    }

    /// Whether this iCloud account already holds a league, from another phone
    /// or from before the app was deleted. Looks in the zone SwiftData syncs to.
    static func iCloudHasLeague() async -> Bool {
        let database = CKContainer(identifier: BowlingLeagueApp.cloudContainer).privateCloudDatabase
        let zone = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)
        do {
            let changes = try await database.recordZoneChanges(inZoneWith: zone, since: nil, resultsLimit: 1)
            return !changes.modificationResultsByID.isEmpty
        } catch {
            // No zone yet means nothing was ever synced.
            return false
        }
    }
}
