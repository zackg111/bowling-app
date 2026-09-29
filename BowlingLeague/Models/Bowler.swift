import Foundation
import SwiftData

@Model
final class Bowler {
    var name: String
    /// The average the league uses for handicap. Entered by hand to start;
    /// `BowlerStats` can suggest one from bowled games.
    var average: Int
    var createdAt: Date
    /// Profile photo, downscaled JPEG. Stored outside the database file.
    @Attribute(.externalStorage) var photoData: Data?
    /// False once the bowler has left the league. Their history and stats stay.
    var isActive = true

    /// Island (the season-long survivor game).
    var onIsland = false
    var hasImmunity = false
    /// Kicked off last week; gets back on by bowling the highest series this week.
    var islandSwimming = false
    /// Off the island for the rest of the season.
    var islandOutDate: Date?

    var isIslandCastaway: Bool { onIsland && !islandSwimming && islandOutDate == nil }
    var isIslandSwimmer: Bool { onIsland && islandSwimming && islandOutDate == nil }

    @Relationship(deleteRule: .cascade, inverse: \Entry.bowler)
    var entries: [Entry] = []

    init(name: String, average: Int) {
        self.name = name
        self.average = average
        self.createdAt = .now
    }

    var stats: BowlerStats {
        BowlerStats(nights: entries.map(\.games))
    }
}
