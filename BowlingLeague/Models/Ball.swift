import Foundation
import SwiftData

/// A bowling ball in a bowler's arsenal.
@Model
final class Ball {
    // Defaults on everything and an optional relationship, for iCloud sync.
    var name = ""
    var brand = ""
    /// Pounds; 0 when not set.
    var weight = 0
    /// Downscaled JPEG. Stored outside the database file.
    @Attribute(.externalStorage) var photoData: Data?
    /// Kept for its history, but no longer offered when picking a ball.
    var isRetired = false
    var createdAt = Date.now
    var bowler: Bowler?

    init(name: String, brand: String = "", bowler: Bowler? = nil) {
        self.name = name
        self.brand = brand
        self.bowler = bowler
        self.createdAt = .now
    }
}

extension Bowler {
    /// Balls they can pick for a night, newest first.
    var activeBalls: [Ball] {
        (balls ?? []).filter { !$0.isRetired }.sorted { $0.createdAt > $1.createdAt }
    }
}
