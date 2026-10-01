import Foundation

/// Keeps Settings (handicap, average, eliminator, Island) in iCloud key-value
/// storage, so they come back with the league on a new phone or a reinstall,
/// and stay the same on every device.
enum SettingsSync {
    static let keys = ["handicapBase", "handicapPercent", "fourPlacesFrom",
                       "useBowledAverage", "bowledAverageGames", "islandWeeks"]

    private static var store: NSUbiquitousKeyValueStore { .default }

    static func start() {
        let center = NotificationCenter.default
        // Changed on another device, or first arriving after a reinstall.
        center.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                           object: NSUbiquitousKeyValueStore.default, queue: .main) { _ in
            MainActor.assumeIsolated { pull(overwrite: true) }
        }
        // Changed here: send it up.
        center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { push() }
        }
        store.synchronize()
        // A fresh install has no settings of its own yet; take iCloud's.
        pull(overwrite: false)
    }

    /// Copies iCloud's settings onto this device. Without `overwrite`, only
    /// fills in settings never set here.
    static func pull(overwrite: Bool) {
        let defaults = UserDefaults.standard
        for key in keys {
            guard let value = store.object(forKey: key) else { continue }
            if overwrite || defaults.object(forKey: key) == nil {
                if !isEqual(defaults.object(forKey: key), value) { defaults.set(value, forKey: key) }
            }
        }
    }

    private static func push() {
        let defaults = UserDefaults.standard
        for key in keys {
            guard let value = defaults.object(forKey: key), !isEqual(store.object(forKey: key), value) else { continue }
            store.set(value, forKey: key)
        }
    }

    private static func isEqual(_ a: Any?, _ b: Any) -> Bool {
        (a as? NSObject)?.isEqual(b) ?? false
    }

    /// Whether iCloud has settings saved, from this device or another.
    static var hasSavedSettings: Bool {
        keys.contains { store.object(forKey: $0) != nil }
    }
}
